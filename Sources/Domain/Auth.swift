import Foundation
import Observation

/// 로그인 제공자 (S7). Supabase Auth의 `provider` 값과 같다.
public enum AuthProvider: String, Codable, Sendable, CaseIterable {
    case kakao
    case apple

    /// "카카오" / "Apple" — "카카오로 로그인됨", "카카오 계정 연결이 끊어져요"에 쓴다.
    public var displayName: String {
        switch self {
        case .kakao: "카카오"
        case .apple: "Apple"
        }
    }
}

/// Supabase Auth 세션. 앱은 access token만 API에 보내고, 만료되면 refresh token으로 갱신한다.
public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var provider: AuthProvider
    /// Supabase 사용자 ID(`sub`). 저장 목록 캐시를 계정별로 나누는 데 쓴다.
    public var userID: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, provider: AuthProvider, userID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.provider = provider
        self.userID = userID
    }
}

/// 로그인·세션 오류. 어댑터(HTTP, SDK)는 자기 오류를 이것으로 바꿔 화면이 구분할 수 있게 한다.
public enum AuthError: Error, Sendable, Equatable {
    /// 사용자가 카카오·Apple 화면에서 취소 — 조용히 기본 상태로.
    case cancelled
    /// 인터넷 연결 없음.
    case offline
    /// 서버 인증 일시 불가(503 `auth_unavailable`·`auth_not_configured`) — 로그아웃하지 않는다.
    case unavailable
    /// 토큰이 거부됨(401). `AuthService.authorized`가 리프레시 후 한 번 다시 시도한다.
    case unauthorized
    /// 리프레시도 실패해 로그아웃 상태가 됨 — "다시 로그인해 주세요".
    case sessionExpired
    /// 로그인하지 않은 상태에서 계정 API를 부름.
    case notLoggedIn
    /// 앱에 Supabase·카카오 설정값이 없음(로컬 빌드에 Secrets.xcconfig 없음 등).
    case notConfigured
    /// 그 밖의 실패(제공자 오류, 서버 5xx, 응답 형식 오류).
    case failed
}

/// Port: Supabase Auth (ID 토큰 교환·리프레시·로그아웃). `Networking.SupabaseAuthBackend`가 HTTP로 구현한다.
public protocol AuthBackend: Sendable {
    /// `grant_type=id_token`. `nonce`는 원문(raw) — 제공자에는 SHA-256 해시를 넘겼다.
    func signIn(provider: AuthProvider, idToken: String, nonce: String?) async throws -> AuthSession
    /// `grant_type=refresh_token`. refresh token이 거부되면 `AuthError.unauthorized`.
    func refresh(_ session: AuthSession) async throws -> AuthSession
    /// 서버 세션 끊기. 실패해도 기기에서는 로그아웃하므로 던지지 않는다.
    func signOut(accessToken: String) async
}

/// Port: 세션 보관(키체인). `Networking.KeychainSessionStore`가 구현한다.
public protocol SessionStoring: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// 로그인 시트(S7)를 연 이유. 제목만 다르다.
public enum LoginPurpose: Sendable, Equatable {
    /// 로그아웃 상태에서 저장을 누름.
    case save
    /// S4 로그인 버튼, S6 로그인 행.
    case account

    public var title: String {
        switch self {
        case .save: "로그인하면 저장할 수 있어요"
        case .account: "로그인하고 저장한 볼거리를 모아 보세요"
        }
    }
}

/// 로그인 시트 요청 + 로그인 뒤 할 일(대기 동작). 앱 어디서 열려도 같은 시트다 (DESIGN §6.17).
public struct LoginRequest: Identifiable {
    public let id = UUID()
    public let purpose: LoginPurpose
    /// 로그인 성공 뒤 실행할 동작(예: 누른 볼거리 저장). 돌려주는 문구는 토스트로 보여준다.
    public let action: (@MainActor () async -> String?)?

    public init(purpose: LoginPurpose, action: (@MainActor () async -> String?)? = nil) {
        self.purpose = purpose
        self.action = action
    }
}

/// 로그인 상태(세션)와 토큰 갱신. Features는 이 클래스만 보고, HTTP·키체인은 포트로 받는다.
///
/// - 계정 API는 `authorized(_:)`로 부른다: 만료가 가까우면 먼저 리프레시, 401이면 리프레시 후 한 번 다시 시도,
///   리프레시가 거부되면 세션을 지우고 `AuthError.sessionExpired`. 503(`unavailable`)·오프라인은 세션을 유지한다.
@MainActor
@Observable
public final class AuthService {
    /// 만료 이만큼 전이면 미리 리프레시한다.
    public static let refreshLeeway: TimeInterval = 60

    public private(set) var session: AuthSession?
    /// 띄울 로그인 시트. App이 `.sheet(item:)`으로 보여준다.
    public var loginRequest: LoginRequest?

    private let backend: any AuthBackend
    private let storage: any SessionStoring
    private let now: @Sendable () -> Date
    @ObservationIgnored private var refreshTask: Task<AuthSession, any Error>?
    @ObservationIgnored private var observers: [@MainActor (AuthSession?) -> Void] = []

    public init(
        backend: any AuthBackend, storage: any SessionStoring, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backend = backend
        self.storage = storage
        self.now = now
        self.session = storage.load()
    }

    public var isLoggedIn: Bool { session != nil }
    public var provider: AuthProvider? { session?.provider }

    /// 로그인 사용자가 바뀔 때(로그인·로그아웃·만료) 불린다. 저장 목록이 계정별 캐시를 바꾸는 데 쓴다.
    public func observeSession(_ observer: @escaping @MainActor (AuthSession?) -> Void) {
        observers.append(observer)
    }

    /// 로그인 시트를 띄운다. 이미 로그인했으면 대기 동작을 바로 실행하지 않고 무시한다(시트가 뜰 일이 없음).
    public func requestLogin(_ purpose: LoginPurpose, then action: (@MainActor () async -> String?)? = nil) {
        guard !isLoggedIn else { return }
        loginRequest = LoginRequest(purpose: purpose, action: action)
    }

    /// 제공자 id_token을 Supabase 세션으로 바꾸고 키체인에 둔다.
    public func signIn(provider: AuthProvider, idToken: String, nonce: String?) async throws {
        let session = try await backend.signIn(provider: provider, idToken: idToken, nonce: nonce)
        storage.save(session)
        setSession(session)
    }

    /// 로그아웃: 기기 세션을 먼저 지우고 서버 세션 끊기를 시도한다(실패해도 기기는 로그아웃).
    public func signOut() async {
        let token = session?.accessToken
        clear()
        if let token { await backend.signOut(accessToken: token) }
    }

    /// 서버 호출 없이 기기 세션만 지운다(탈퇴 완료, 세션 만료).
    public func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        storage.clear()
        setSession(nil)
    }

    /// 계정 API 호출. `operation`은 access token을 받아 요청하고, 401이면 `AuthError.unauthorized`를 던져야 한다.
    public func authorized<T: Sendable>(_ operation: @Sendable (String) async throws -> T) async throws -> T {
        guard let current = session else { throw AuthError.notLoggedIn }
        var token = current.accessToken
        if current.expiresAt.timeIntervalSince(now()) < Self.refreshLeeway {
            token = try await refreshed(from: current).accessToken
        }
        do {
            return try await operation(token)
        } catch AuthError.unauthorized {
            guard let latest = session else { throw AuthError.sessionExpired }
            // 다른 요청이 이미 리프레시했으면 그 토큰으로, 아니면 리프레시하고 한 번만 다시 시도한다.
            let retryToken =
                latest.accessToken != token ? latest.accessToken : try await refreshed(from: latest).accessToken
            do {
                return try await operation(retryToken)
            } catch AuthError.unauthorized {
                expire()
                throw AuthError.sessionExpired
            }
        }
    }

    /// 동시에 여러 요청이 401을 받아도 리프레시는 한 번만 한다.
    private func refreshed(from current: AuthSession) async throws -> AuthSession {
        if let running = refreshTask { return try await running.value }
        let backend = self.backend
        let task = Task { try await backend.refresh(current) }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        do {
            let fresh = try await task.value
            // 리프레시 중에 로그아웃했으면 되살리지 않는다.
            if session?.userID == current.userID {
                storage.save(fresh)
                session = fresh
            }
            return fresh
        } catch AuthError.unauthorized {
            expire()
            throw AuthError.sessionExpired
        }
    }

    private func expire() {
        guard session != nil else { return }
        clear()
    }

    private func setSession(_ new: AuthSession?) {
        let changedUser = session?.userID != new?.userID
        session = new
        if changedUser { observers.forEach { $0(new) } }
    }
}
