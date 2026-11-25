import Foundation

/// `GET /v1/me/saved` 한 페이지.
public struct SavedPage: Sendable, Equatable {
    public var items: [SavedSpot]
    public var nextCursor: String?

    public init(items: [SavedSpot], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// `POST /v1/me/saved:import` 결과.
public struct SavedImportResult: Sendable, Equatable {
    /// 새로 저장한 수(이미 있던 항목 제외) — 토스트 "기기에 저장했던 N개를 계정으로 옮겼어요"의 N.
    public var imported: Int
    /// 서버에 없어 건너뛴 수(정리된 볼거리).
    public var skippedUnknown: Int

    public init(imported: Int, skippedUnknown: Int) {
        self.imported = imported
        self.skippedUnknown = skippedUnknown
    }
}

/// 계정 API 오류(인증 오류는 `AuthError`).
public enum AccountError: Error, Sendable, Equatable {
    /// 409 `saved_limit_exceeded` — 사용자당 500개.
    case savedLimitExceeded
    /// 404 — 없는 볼거리(정리됨 포함).
    case notFound
    /// 인터넷 연결 없음·타임아웃.
    case offline
    /// 그 밖의 서버 오류(5xx 등).
    case server
}

/// Port: 로그인 사용자 API(`/v1/me/*`). `Networking.LiveAccountService`가 구현한다.
/// 401은 `AuthError.unauthorized`, 503 `auth_*`는 `AuthError.unavailable`로 던진다 (`AuthService.authorized`가 처리).
public protocol AccountService: Sendable {
    func savedPage(cursor: String?, accessToken: String) async throws -> SavedPage
    func save(spotID: String, accessToken: String) async throws
    func unsave(spotID: String, accessToken: String) async throws
    func importSaved(spotIDs: [String], accessToken: String) async throws -> SavedImportResult
    /// 회원 탈퇴 (`DELETE /v1/me`).
    func deleteAccount(accessToken: String) async throws
}

/// Port: 카카오 SDK (App 레이어가 구현 — 카카오 SDK는 App에서만 import).
@MainActor
public protocol KakaoLoginProviding: AnyObject {
    /// 카카오톡이 있으면 카카오톡으로, 없으면 카카오 계정(웹)으로 로그인해 OIDC id_token을 돌려준다.
    /// `nonce`는 SHA-256 해시 값(id_token의 `nonce` 클레임). 취소하면 `AuthError.cancelled`.
    func idToken(nonce: String) async throws -> String
    /// 카카오 SDK 토큰 지우기(로그아웃). 실패해도 무시.
    func logout() async
    /// 앱 연결 끊기(탈퇴). 실패해도 서버 탈퇴는 진행.
    func unlink() async
}

// MARK: - Fake (미리보기·Debug 샘플 모드·테스트)

/// 메모리에 저장 목록을 두는 `AccountService`. `spots`에 있는 볼거리만 저장할 수 있다(없으면 404).
public actor FakeAccountService: AccountService {
    public static let savedLimit = 500

    private let spots: [String: Spot]
    private var saved: [(id: String, savedAt: Date)] = []
    private let now: @Sendable () -> Date
    public private(set) var deleted = false

    public init(
        spots: [Spot] = SampleSpots.all, savedIDs: [String] = [], now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.spots = Dictionary(spots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.now = now
        let start = now()
        saved = savedIDs.enumerated().map { ($0.element, start.addingTimeInterval(-Double($0.offset) * 3_600)) }
    }

    public func savedPage(cursor: String?, accessToken: String) async throws -> SavedPage {
        SavedPage(
            items: saved.compactMap { entry in spots[entry.id].map { SavedSpot(spot: $0, savedAt: entry.savedAt) } })
    }

    public func save(spotID: String, accessToken: String) async throws {
        guard spots[spotID] != nil else { throw AccountError.notFound }
        guard !saved.contains(where: { $0.id == spotID }) else { return }
        guard saved.count < Self.savedLimit else { throw AccountError.savedLimitExceeded }
        saved.insert((spotID, now()), at: 0)
    }

    public func unsave(spotID: String, accessToken: String) async throws {
        saved.removeAll { $0.id == spotID }
    }

    public func importSaved(spotIDs: [String], accessToken: String) async throws -> SavedImportResult {
        var imported = 0
        var skipped = 0
        var seen = Set<String>()
        for id in spotIDs where seen.insert(id).inserted {
            if spots[id] == nil {
                skipped += 1
            } else if !saved.contains(where: { $0.id == id }) {
                saved.insert((id, now()), at: 0)
                imported += 1
            }
        }
        return SavedImportResult(imported: imported, skippedUnknown: skipped)
    }

    public func deleteAccount(accessToken: String) async throws {
        saved = []
        deleted = true
    }
}

/// 어떤 id_token이든 세션으로 바꿔 주는 `AuthBackend` (미리보기·UI 테스트·설정값 없는 Debug).
public struct FakeAuthBackend: AuthBackend {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public static func session(provider: AuthProvider, now: Date = Date()) -> AuthSession {
        AuthSession(
            accessToken: "fake-access", refreshToken: "fake-refresh", expiresAt: now.addingTimeInterval(3_600),
            provider: provider, userID: "fake-user")
    }

    public func signIn(provider: AuthProvider, idToken: String, nonce: String?) async throws -> AuthSession {
        Self.session(provider: provider, now: now())
    }

    public func refresh(_ session: AuthSession) async throws -> AuthSession {
        Self.session(provider: session.provider, now: now())
    }

    public func signOut(accessToken: String) async {}
}

/// 메모리에만 두는 세션 보관소 (테스트·미리보기).
public final class InMemorySessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AuthSession?

    public init(_ session: AuthSession? = nil) {
        stored = session
    }

    public func load() -> AuthSession? { lock.withLock { stored } }
    public func save(_ session: AuthSession) { lock.withLock { stored = session } }
    public func clear() { lock.withLock { stored = nil } }
}

/// 카카오 로그인을 흉내 낸다. `result`가 nil이면 취소.
@MainActor
public final class FakeKakaoLogin: KakaoLoginProviding {
    public var result: Result<String, AuthError>
    public private(set) var logoutCount = 0
    public private(set) var unlinkCount = 0
    public private(set) var lastNonce: String?

    public init(result: Result<String, AuthError> = .success("fake-kakao-id-token")) {
        self.result = result
    }

    public func idToken(nonce: String) async throws -> String {
        lastNonce = nonce
        return try result.get()
    }

    public func logout() async { logoutCount += 1 }
    public func unlink() async { unlinkCount += 1 }
}

// MARK: - 로그아웃 · 탈퇴 (S6)

/// 설정(S6)의 로그아웃·회원 탈퇴. 기기 정리 순서를 한곳에 둔다.
@MainActor
public final class AccountActions {
    public let library: SavedLibrary
    private let account: any AccountService
    private let kakao: any KakaoLoginProviding

    public init(library: SavedLibrary, account: any AccountService, kakao: any KakaoLoginProviding) {
        self.library = library
        self.account = account
        self.kakao = kakao
    }

    public var auth: AuthService { library.auth }

    /// 로그아웃: 카카오 SDK 로그아웃 → 저장 목록 캐시 삭제 → 세션 삭제(서버 호출 실패해도 기기는 로그아웃).
    public func signOut() async {
        if auth.provider == .kakao { await kakao.logout() }
        library.clearLocalData()
        await auth.signOut()
    }

    /// 회원 탈퇴: 카카오면 앱 연결 끊기(실패해도 진행) → `DELETE /v1/me` → 세션·캐시·기기 로컬 저장 모두 삭제.
    /// 실패하면 아무것도 지우지 않고 던진다(세션 만료면 `AuthError.sessionExpired` — 세션은 이미 지워짐).
    public func deleteAccount() async throws {
        if auth.provider == .kakao { await kakao.unlink() }
        // TODO(herezi-api#72): Apple 로그인 사용자는 탈퇴 때 Sign in with Apple 토큰을 철회해야 한다(서버 revoke,
        // 필요하면 여기서 Apple 재인증으로 authorization code를 받아 함께 보낸다). 지금은 서버가 철회하지 않는다.
        let account = self.account
        try await auth.authorized { try await account.deleteAccount(accessToken: $0) }
        library.clearLocalData(includingLegacy: true)
        auth.clear()
    }
}
