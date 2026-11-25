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
    /// 400 `apple_reauth_required` — Apple 사용자 탈퇴에 재인증 코드가 없거나 Apple이 거부함(만료·재사용). 다시 인증해 재시도.
    case appleReauthRequired
}

/// Port: 로그인 사용자 API(`/v1/me/*`). `Networking.LiveAccountService`가 구현한다.
/// 401은 `AuthError.unauthorized`, 503 `auth_*`는 `AuthError.unavailable`로 던진다 (`AuthService.authorized`가 처리).
public protocol AccountService: Sendable {
    func savedPage(cursor: String?, accessToken: String) async throws -> SavedPage
    func save(spotID: String, accessToken: String) async throws
    func unsave(spotID: String, accessToken: String) async throws
    func importSaved(spotIDs: [String], accessToken: String) async throws -> SavedImportResult
    /// 회원 탈퇴 (`DELETE /v1/me`). Apple 사용자는 탈퇴 직전 재인증으로 받은 authorization code를 함께 보낸다
    /// (서버가 Apple 토큰을 철회한 뒤 지운다, herezi-api#72). 다른 제공자는 nil.
    func deleteAccount(accessToken: String, appleAuthorizationCode: String?) async throws
}

/// Port: 탈퇴 직전 Sign in with Apple 재인증 (FeatureAuth `AppleReauthorizer`가 AuthenticationServices로 구현).
@MainActor
public protocol AppleReauthorizing: AnyObject {
    /// Apple 시스템 시트를 띄워(scope 없음) 새 `authorizationCode`(5분 유효)를 받는다. 취소하면 `AuthError.cancelled`.
    func authorizationCode() async throws -> String
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

    public private(set) var lastAppleAuthorizationCode: String?

    public func deleteAccount(accessToken: String, appleAuthorizationCode: String?) async throws {
        saved = []
        deleted = true
        lastAppleAuthorizationCode = appleAuthorizationCode
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

/// Apple 재인증을 흉내 낸다. `result`가 실패면 그 오류(취소 = `AuthError.cancelled`).
@MainActor
public final class FakeAppleReauth: AppleReauthorizing {
    public var result: Result<String, AuthError>
    public private(set) var requestCount = 0

    public init(result: Result<String, AuthError> = .success("fake-apple-authorization-code")) {
        self.result = result
    }

    public func authorizationCode() async throws -> String {
        requestCount += 1
        return try result.get()
    }
}

// MARK: - 로그아웃 · 탈퇴 (S6)

/// 설정(S6)의 로그아웃·회원 탈퇴. 기기 정리 순서를 한곳에 둔다.
@MainActor
public final class AccountActions {
    public let library: SavedLibrary
    private let account: any AccountService
    private let kakao: any KakaoLoginProviding
    private let apple: any AppleReauthorizing

    public init(
        library: SavedLibrary, account: any AccountService, kakao: any KakaoLoginProviding,
        apple: any AppleReauthorizing
    ) {
        self.library = library
        self.account = account
        self.kakao = kakao
        self.apple = apple
    }

    public var auth: AuthService { library.auth }

    /// 로그아웃: 카카오 SDK 로그아웃 → 저장 목록 캐시 삭제 → 세션 삭제(서버 호출 실패해도 기기는 로그아웃).
    public func signOut() async {
        if auth.provider == .kakao { await kakao.logout() }
        library.clearLocalData()
        await auth.signOut()
    }

    /// 회원 탈퇴: Apple이면 재인증으로 authorization code 받기(취소하면 `AuthError.cancelled`로 멈춤, 아무것도 안 지움),
    /// 카카오면 앱 연결 끊기(실패해도 진행) → `DELETE /v1/me`(Apple은 코드와 함께 — 서버가 토큰 철회) →
    /// 세션·캐시·기기 로컬 저장 모두 삭제.
    /// 실패하면 아무것도 지우지 않고 던진다(세션 만료면 `AuthError.sessionExpired` — 세션은 이미 지워짐).
    public func deleteAccount() async throws {
        var code: String?
        switch auth.provider {
        case .apple: code = try await apple.authorizationCode()
        case .kakao: await kakao.unlink()
        case nil: break
        }
        let appleCode = code
        let account = self.account
        try await auth.authorized {
            try await account.deleteAccount(accessToken: $0, appleAuthorizationCode: appleCode)
        }
        library.clearLocalData(includingLegacy: true)
        auth.clear()
    }
}
