import Domain
import FeatureAuth
import Foundation
import Testing

/// 로그인 백엔드에 넘어온 값을 기록한다.
actor RecordingAuthBackend: AuthBackend {
    private(set) var signIns: [(AuthProvider, String, String?)] = []
    var error: AuthError?

    func fail(with error: AuthError?) { self.error = error }

    func signIn(provider: AuthProvider, idToken: String, nonce: String?) async throws -> AuthSession {
        signIns.append((provider, idToken, nonce))
        if let error { throw error }
        return FakeAuthBackend.session(provider: provider, now: TestData.now)
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession { session }
    func signOut(accessToken: String) async {}
}

@MainActor
struct LoginViewModelTests {
    private func make(
        purpose: LoginPurpose = .save, kakao: FakeKakaoLogin = FakeKakaoLogin(),
        backend: RecordingAuthBackend = RecordingAuthBackend(),
        onSignedIn: @escaping @MainActor (LoginRequest) async -> Void = { _ in }
    ) -> (LoginViewModel, AuthService) {
        let auth = AuthService(backend: backend, storage: InMemorySessionStore(), now: { TestData.now })
        auth.requestLogin(purpose)
        let viewModel = LoginViewModel(request: auth.loginRequest!, auth: auth, kakao: kakao, onSignedIn: onSignedIn)
        return (viewModel, auth)
    }

    @Test func 제목은_진입에_따라_다르다() {
        #expect(make(purpose: .save).0.title == "로그인하면 저장할 수 있어요")
        #expect(make(purpose: .account).0.title == "로그인하고 저장한 볼거리를 모아 보세요")
    }

    @Test func 카카오_로그인은_해시_nonce를_카카오에_원문을_Supabase에() async throws {
        let kakao = FakeKakaoLogin(result: .success("kakao-id-token"))
        let backend = RecordingAuthBackend()
        var signedIn: LoginRequest?
        let (viewModel, auth) = make(kakao: kakao, backend: backend) { signedIn = $0 }

        await viewModel.loginWithKakao()

        let call = try #require(await backend.signIns.first)
        #expect(call.0 == .kakao)
        #expect(call.1 == "kakao-id-token")
        let raw = try #require(call.2)
        #expect(kakao.lastNonce == Nonce.sha256(raw))
        #expect(auth.isLoggedIn)
        #expect(auth.loginRequest == nil)  // 시트 닫힘
        #expect(signedIn?.id == viewModel.request.id)
        #expect(!viewModel.isBusy)
    }

    @Test func 취소하면_조용히_기본_상태() async {
        let (viewModel, auth) = make(kakao: FakeKakaoLogin(result: .failure(.cancelled)))
        await viewModel.loginWithKakao()
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isBusy)
        #expect(auth.loginRequest != nil)  // 시트 그대로
    }

    @Test func 실패하면_오류_줄_네트워크면_연결_확인() async {
        let backend = RecordingAuthBackend()
        await backend.fail(with: .unavailable)
        let (failed, _) = make(backend: backend)
        await failed.loginWithKakao()
        #expect(failed.errorMessage == "로그인하지 못했어요. 다시 시도해 주세요.")

        let (offline, _) = make(kakao: FakeKakaoLogin(result: .failure(.offline)))
        await offline.loginWithKakao()
        #expect(offline.errorMessage == "인터넷 연결을 확인하고 다시 시도해 주세요.")
    }

    @Test func Apple은_원문_nonce로_교환하고_진행_중_연타는_무시한다() async throws {
        let backend = RecordingAuthBackend()
        let (viewModel, auth) = make(backend: backend)

        let hashed = try #require(viewModel.beginApple())
        #expect(viewModel.inProgress == .apple)
        #expect(viewModel.beginApple() == nil)  // 진행 중 두 번째 탭

        await viewModel.completeApple(identityToken: Data("apple-jwt".utf8))

        let call = try #require(await backend.signIns.first)
        #expect(call.0 == .apple && call.1 == "apple-jwt")
        #expect(Nonce.sha256(try #require(call.2)) == hashed)
        #expect(auth.provider == .apple)
    }

    @Test func Apple_취소는_조용히_실패는_오류() {
        let (viewModel, _) = make()
        _ = viewModel.beginApple()
        viewModel.failApple(cancelled: true)
        #expect(viewModel.errorMessage == nil && !viewModel.isBusy)

        _ = viewModel.beginApple()
        viewModel.failApple(cancelled: false)
        #expect(viewModel.errorMessage == "로그인하지 못했어요. 다시 시도해 주세요.")
    }

    @Test func nonce_해시() {
        #expect(Nonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Nonce.random().count == 32)
    }
}
