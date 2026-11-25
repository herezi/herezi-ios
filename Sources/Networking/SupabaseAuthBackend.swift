import Domain
import Foundation

/// `AuthBackend` — Supabase Auth REST (supabase-swift 없이 URLSession).
///
/// - 로그인: `POST {SUPABASE_URL}/auth/v1/token?grant_type=id_token` `{provider, id_token, nonce}`
/// - 갱신: `POST {SUPABASE_URL}/auth/v1/token?grant_type=refresh_token` `{refresh_token}`
/// - 로그아웃: `POST {SUPABASE_URL}/auth/v1/logout` (Bearer access token)
///
/// 모든 요청에 `apikey: <publishable key>` 헤더를 붙인다.
public struct SupabaseAuthBackend: AuthBackend {
    public struct Config: Sendable, Equatable {
        public let url: URL
        public let publishableKey: String

        public init(url: URL, publishableKey: String) {
            self.url = url
            self.publishableKey = publishableKey
        }

        /// Info.plist `SupabaseURL`·`SupabasePublishableKey` (project.yml ← Config/Secrets.xcconfig). 없으면 nil.
        public static func from(bundle: Bundle = .main) -> Config? {
            guard let raw = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
                let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true,
                url.host() != nil,
                let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String, !key.isEmpty
            else { return nil }
            return Config(url: url, publishableKey: key)
        }
    }

    private let config: Config?
    private let session: URLSession
    private let now: @Sendable () -> Date

    /// - Parameter config: nil이면 모든 호출이 `AuthError.notConfigured`.
    public init(config: Config?, session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.session = session
        self.now = now
    }

    public func signIn(provider: AuthProvider, idToken: String, nonce: String?) async throws -> AuthSession {
        var body: [String: String] = ["provider": provider.rawValue, "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        let data = try await post(path: "token", grantType: "id_token", body: body)
        return try decodeSession(data, provider: provider)
    }

    public func refresh(_ current: AuthSession) async throws -> AuthSession {
        let data = try await post(
            path: "token", grantType: "refresh_token", body: ["refresh_token": current.refreshToken])
        return try decodeSession(data, provider: current.provider)
    }

    public func signOut(accessToken: String) async {
        _ = try? await post(path: "logout", grantType: nil, body: [:], bearer: accessToken)
    }

    // MARK: HTTP

    private func post(path: String, grantType: String?, body: [String: String], bearer: String? = nil) async throws
        -> Data
    {
        guard let config else { throw AuthError.notConfigured }
        var components = URLComponents(
            url: config.url.appending(path: "auth/v1").appending(path: path), resolvingAgainstBaseURL: false)
        if let grantType { components?.queryItems = [URLQueryItem(name: "grant_type", value: grantType)] }
        guard let url = components?.url else { throw AuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw AuthError.offline
        } catch {
            throw AuthError.failed
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        // 잘못된·만료된·이미 쓴 refresh token, 거부된 id_token은 400/401/403 — 다시 로그인해야 한다.
        case 400, 401, 403: throw AuthError.unauthorized
        case 500..<600: throw AuthError.unavailable
        default: throw AuthError.failed
        }
    }

    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
        .dataNotAllowed, .internationalRoamingOff,
    ]

    private func decodeSession(_ data: Data, provider: AuthProvider) throws -> AuthSession {
        guard let dto = try? JSONDecoder().decode(SupabaseSessionDTO.self, from: data) else { throw AuthError.failed }
        let expiresAt: Date =
            if let at = dto.expiresAt { Date(timeIntervalSince1970: at) } else {
                now().addingTimeInterval(dto.expiresIn ?? 3_600)
            }
        return AuthSession(
            accessToken: dto.accessToken, refreshToken: dto.refreshToken, expiresAt: expiresAt, provider: provider,
            userID: dto.user.id)
    }
}

/// Supabase Auth 세션 응답(필요한 필드만).
struct SupabaseSessionDTO: Decodable {
    struct User: Decodable {
        let id: String
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Double?
    let expiresAt: Double?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user = "user"
    }
}
