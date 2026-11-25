import AuthenticationServices
import Domain
import UIKit

/// `AppleReauthorizing` — 탈퇴 직전 Sign in with Apple 재인증(herezi-api#72).
///
/// 이름·이메일 scope 없이 요청해 새 `authorizationCode`만 받는다. 서버가 이 코드를 앱 번들 ID(client_id)로 토큰과 바꿔
/// Apple 토큰을 철회한다. 코드는 5분 동안 한 번만 쓸 수 있으므로 받은 즉시 `DELETE /v1/me`에 보낸다.
@MainActor
public final class AppleReauthorizer: NSObject, AppleReauthorizing {
    private var continuation: CheckedContinuation<String, any Error>?
    private var controller: ASAuthorizationController?

    override public init() {}

    public func authorizationCode() async throws -> String {
        guard continuation == nil else { throw AuthError.failed }  // 이미 시트가 떠 있음
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        let continuation = self.continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }
}

extension AppleReauthorizer: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        if let data = credential?.authorizationCode, let code = String(data: data, encoding: .utf8), !code.isEmpty {
            finish(.success(code))
        } else {
            finish(.failure(AuthError.failed))
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        finish(.failure(cancelled ? AuthError.cancelled : AuthError.failed))
    }
}

extension AppleReauthorizer: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first { return window }
        return scenes.first.map { UIWindow(windowScene: $0) } ?? ASPresentationAnchor()
    }
}
