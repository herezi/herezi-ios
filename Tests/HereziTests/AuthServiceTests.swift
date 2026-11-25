import Domain
import Foundation
import Networking
import Testing

/// AuthService + SupabaseAuthBackend + LiveAccountService를 URLProtocol 스텁으로 검증한다(네트워크 없음).
@MainActor
struct AuthServiceTests {
    private let now = TestData.now
    private let supabase = URL(string: "https://test-ref.supabase.co")!
    private let api = URL(string: "https://api.test")!

    private func sessionJSON(access: String, refresh: String, expiresIn: Int = 3_600) -> Data {
        Data(
            """
            {"access_token":"\(access)","token_type":"bearer","expires_in":\(expiresIn),
             "expires_at":\(Int(now.timeIntervalSince1970) + expiresIn),"refresh_token":"\(refresh)",
             "user":{"id":"user-1","aud":"authenticated"}}
            """.utf8)
    }

    private func make(
        stored: AuthSession? = nil, _ handler: @escaping StubURLProtocol.Handler
    ) -> (AuthService, LiveAccountService, InMemorySessionStore) {
        let urlSession = StubURLProtocol.session(handler)
        let now = self.now
        let backend = SupabaseAuthBackend(
            config: .init(url: supabase, publishableKey: "pk-test"), session: urlSession, now: { now })
        let storage = InMemorySessionStore(stored)
        let auth = AuthService(backend: backend, storage: storage, now: { now })
        let account = LiveAccountService(client: APIClient(baseURL: api, session: urlSession), now: { now })
        return (auth, account, storage)
    }

    private func session(access: String = "old-access", expiresIn: TimeInterval = 3_600) -> AuthSession {
        AuthSession(
            accessToken: access, refreshToken: "old-refresh", expiresAt: now.addingTimeInterval(expiresIn),
            provider: .kakao, userID: "user-1")
    }

    @Test func id_token을_Supabase_세션으로_바꿔_보관한다() async throws {
        let log = RequestLog()
        let body = sessionJSON(access: "new-access", refresh: "new-refresh")
        let (auth, _, storage) = make { request in
            log.append(request)
            return (200, body)
        }

        try await auth.signIn(provider: .apple, idToken: "apple-jwt", nonce: "raw-nonce")

        let request = try #require(log.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://test-ref.supabase.co/auth/v1/token?grant_type=id_token")
        #expect(request.value(forHTTPHeaderField: "apikey") == "pk-test")
        let json = try #require(log.json(0))
        #expect(json["provider"] as? String == "apple")
        #expect(json["id_token"] as? String == "apple-jwt")
        #expect(json["nonce"] as? String == "raw-nonce")
        #expect(auth.session?.accessToken == "new-access")
        #expect(auth.session?.provider == .apple)
        #expect(auth.session?.userID == "user-1")
        #expect(auth.session?.expiresAt == now.addingTimeInterval(3_600))
        #expect(storage.load() == auth.session)
    }

    @Test func 거부된_id_token은_로그인_실패() async {
        let (auth, _, _) = make { _ in (400, Data(#"{"error_code":"bad_jwt"}"#.utf8)) }
        await #expect(throws: AuthError.unauthorized) {
            try await auth.signIn(provider: .kakao, idToken: "bad", nonce: nil)
        }
        #expect(!auth.isLoggedIn)
    }

    @Test func 설정값이_없으면_notConfigured() async {
        let auth = AuthService(backend: SupabaseAuthBackend(config: nil), storage: InMemorySessionStore())
        await #expect(throws: AuthError.notConfigured) {
            try await auth.signIn(provider: .kakao, idToken: "t", nonce: nil)
        }
    }

    @Test func 계정_API는_Bearer_토큰을_붙인다() async throws {
        let log = RequestLog()
        let (auth, account, _) = make(stored: session()) { request in
            log.append(request)
            return (200, Data(#"{"items":[],"next_cursor":null}"#.utf8))
        }

        _ = try await auth.authorized { try await account.savedPage(cursor: nil, accessToken: $0) }

        let request = try #require(log.requests.first)
        #expect(request.url?.path == "/v1/me/saved")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    }

    @Test func 응답이_401이면_리프레시하고_한_번_다시_시도한다() async throws {
        let log = RequestLog()
        let refreshed = sessionJSON(access: "new-access", refresh: "new-refresh")
        let (auth, account, storage) = make(stored: session()) { request in
            log.append(request)
            if request.url?.host() == "test-ref.supabase.co" { return (200, refreshed) }
            let authorized = request.value(forHTTPHeaderField: "Authorization")
            return authorized == "Bearer new-access"
                ? (204, Data()) : (401, Data(#"{"code":"unauthorized","message":"x"}"#.utf8))
        }

        try await auth.authorized { try await account.save(spotID: "sample-1", accessToken: $0) }

        let urls = log.requests.map { $0.url?.absoluteString ?? "" }
        #expect(urls.count == 3)
        #expect(urls[0] == "https://api.test/v1/me/saved/sample-1")
        #expect(urls[1] == "https://test-ref.supabase.co/auth/v1/token?grant_type=refresh_token")
        #expect(log.json(1)?["refresh_token"] as? String == "old-refresh")
        #expect(log.requests[2].httpMethod == "PUT")
        #expect(log.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
        #expect(auth.session?.accessToken == "new-access")
        #expect(storage.load()?.refreshToken == "new-refresh")
    }

    @Test func 리프레시가_거부되면_로그아웃_상태가_된다() async {
        let (auth, account, storage) = make(stored: session()) { request in
            if request.url?.host() == "test-ref.supabase.co" {
                return (400, Data(#"{"error_code":"refresh_token_not_found"}"#.utf8))
            }
            return (401, Data(#"{"code":"unauthorized","message":"x"}"#.utf8))
        }

        await #expect(throws: AuthError.sessionExpired) {
            try await auth.authorized { try await account.save(spotID: "sample-1", accessToken: $0) }
        }
        #expect(!auth.isLoggedIn)
        #expect(storage.load() == nil)
    }

    @Test func 리프레시_후에도_401이면_로그아웃() async {
        let refreshed = sessionJSON(access: "new-access", refresh: "new-refresh")
        let (auth, account, _) = make(stored: session()) { request in
            if request.url?.host() == "test-ref.supabase.co" { return (200, refreshed) }
            return (401, Data(#"{"code":"unauthorized","message":"x"}"#.utf8))
        }
        await #expect(throws: AuthError.sessionExpired) {
            try await auth.authorized { try await account.unsave(spotID: "sample-1", accessToken: $0) }
        }
        #expect(!auth.isLoggedIn)
    }

    @Test func 응답이_503_auth_unavailable이면_세션을_유지한다() async {
        let log = RequestLog()
        let (auth, account, _) = make(stored: session()) { request in
            log.append(request)
            return (503, Data(#"{"code":"auth_unavailable","message":"jwks"}"#.utf8))
        }
        await #expect(throws: AuthError.unavailable) {
            try await auth.authorized { try await account.savedPage(cursor: nil, accessToken: $0) }
        }
        #expect(auth.isLoggedIn)
        #expect(log.requests.count == 1)  // 리프레시하지 않는다
    }

    @Test func 리프레시_서버_오류면_세션을_유지한다() async {
        let (auth, account, _) = make(stored: session()) { request in
            if request.url?.host() == "test-ref.supabase.co" { return (502, Data()) }
            return (401, Data(#"{"code":"unauthorized","message":"x"}"#.utf8))
        }
        await #expect(throws: AuthError.unavailable) {
            try await auth.authorized { try await account.save(spotID: "a", accessToken: $0) }
        }
        #expect(auth.isLoggedIn)
    }

    @Test func 만료가_가까우면_먼저_리프레시한다() async throws {
        let log = RequestLog()
        let refreshed = sessionJSON(access: "new-access", refresh: "new-refresh")
        let (auth, account, _) = make(stored: session(expiresIn: 30)) { request in
            log.append(request)
            if request.url?.host() == "test-ref.supabase.co" { return (200, refreshed) }
            return (204, Data())
        }
        try await auth.authorized { try await account.unsave(spotID: "a", accessToken: $0) }
        #expect(log.requests.count == 2)
        #expect(log.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test func 저장_한도_409와_import_응답() async throws {
        let (auth, account, _) = make(stored: session()) { request in
            if request.url?.path.hasSuffix("saved:import") == true {
                return (200, Data(#"{"imported":3,"skipped_unknown":1}"#.utf8))
            }
            return (409, Data(#"{"code":"saved_limit_exceeded","message":"500"}"#.utf8))
        }
        await #expect(throws: AccountError.savedLimitExceeded) {
            try await auth.authorized { try await account.save(spotID: "a", accessToken: $0) }
        }
        let result = try await auth.authorized { try await account.importSaved(spotIDs: ["a", "b"], accessToken: $0) }
        #expect(result == SavedImportResult(imported: 3, skippedUnknown: 1))
    }

    @Test func 로그아웃은_서버가_실패해도_기기_세션을_지운다() async {
        let (auth, _, storage) = make(stored: session()) { _ in throw URLError(.notConnectedToInternet) }
        await auth.signOut()
        #expect(!auth.isLoggedIn)
        #expect(storage.load() == nil)
    }

    @Test func 오프라인이면_offline() async {
        let (auth, _, _) = make { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: AuthError.offline) {
            try await auth.signIn(provider: .kakao, idToken: "t", nonce: nil)
        }
    }
}
