import CryptoKit
import Domain
import Foundation
import Observation
import Security

/// S7 로그인 시트의 상태·로직 (herezi-api docs/design/screens/S7-login.md).
///
/// 카카오/Apple → id_token(+nonce) → Supabase 세션(`AuthService.signIn`) → 시트 닫기 → `onSignedIn`(옮기기·대기 동작·토스트).
@MainActor
@Observable
public final class LoginViewModel {
    public let request: LoginRequest
    /// 진행 중인 제공자. 이 동안 다른 버튼·닫기·끌어내리기를 막는다.
    public private(set) var inProgress: AuthProvider?
    /// 오류 줄 문구. 버튼을 다시 누르면 사라진다.
    public private(set) var errorMessage: String?

    private let auth: AuthService
    private let kakao: any KakaoLoginProviding
    private let onSignedIn: @MainActor (LoginRequest) async -> Void
    /// Apple 요청에 넣은 nonce의 원문. Supabase에는 원문, Apple에는 SHA-256 해시를 보낸다.
    @ObservationIgnored private var appleRawNonce: String?

    public init(
        request: LoginRequest, auth: AuthService, kakao: any KakaoLoginProviding,
        onSignedIn: @escaping @MainActor (LoginRequest) async -> Void = { _ in }
    ) {
        self.request = request
        self.auth = auth
        self.kakao = kakao
        self.onSignedIn = onSignedIn
    }

    public var title: String { request.purpose.title }
    public static let reason = "저장한 볼거리를 어느 기기에서든 다시 볼 수 있어요."
    public var isBusy: Bool { inProgress != nil }

    // MARK: 카카오

    public func loginWithKakao() async {
        guard begin(.kakao) else { return }
        let nonce = Nonce.random()
        do {
            let idToken = try await kakao.idToken(nonce: Nonce.sha256(nonce))
            try await finish(provider: .kakao, idToken: idToken, nonce: nonce)
        } catch {
            fail(error)
        }
    }

    // MARK: Apple (SignInWithAppleButton이 시스템 시트를 띄운다)

    /// `onRequest`: 진행 상태로 바꾸고 Apple 요청에 넣을 해시 nonce를 돌려준다. 이미 진행 중이면 nil(요청 무시).
    public func beginApple() -> String? {
        guard begin(.apple) else { return nil }
        let raw = Nonce.random()
        appleRawNonce = raw
        return Nonce.sha256(raw)
    }

    /// `onCompletion` 성공: Apple identityToken(UTF-8 JWT).
    public func completeApple(identityToken: Data?) async {
        guard inProgress == .apple, let raw = appleRawNonce else { return }
        appleRawNonce = nil
        guard let identityToken, let idToken = String(data: identityToken, encoding: .utf8) else {
            fail(AuthError.failed)
            return
        }
        do {
            try await finish(provider: .apple, idToken: idToken, nonce: raw)
        } catch {
            fail(error)
        }
    }

    /// `onCompletion` 실패. 사용자가 취소했으면 `cancelled: true` → 조용히 기본 상태.
    public func failApple(cancelled: Bool) {
        appleRawNonce = nil
        fail(cancelled ? AuthError.cancelled : AuthError.failed)
    }

    // MARK: 공통

    private func begin(_ provider: AuthProvider) -> Bool {
        guard inProgress == nil else { return false }  // 연타 무시
        inProgress = provider
        errorMessage = nil
        return true
    }

    private func finish(provider: AuthProvider, idToken: String, nonce: String) async throws {
        try await auth.signIn(provider: provider, idToken: idToken, nonce: nonce)
        inProgress = nil
        // 시트를 닫고 나서 "로그인 후 할 일"을 한다.
        if auth.loginRequest?.id == request.id { auth.loginRequest = nil }
        await onSignedIn(request)
    }

    private func fail(_ error: any Error) {
        inProgress = nil
        switch error {
        case AuthError.cancelled: errorMessage = nil
        case AuthError.offline: errorMessage = "인터넷 연결을 확인하고 다시 시도해 주세요."
        default: errorMessage = "로그인하지 못했어요. 다시 시도해 주세요."
        }
    }
}

/// OIDC nonce: 원문은 Supabase에, SHA-256(hex)은 카카오·Apple 요청에 넣는다(id_token `nonce` 클레임 = 해시).
public enum Nonce {
    public static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
