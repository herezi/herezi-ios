import Domain
import Foundation
@preconcurrency import KakaoSDKAuth
@preconcurrency import KakaoSDKCommon
@preconcurrency import KakaoSDKUser

/// `KakaoLoginProviding` — 카카오 SDK(UserApi). 카카오 SDK를 import 하는 유일한 곳.
///
/// 카카오톡 앱으로 먼저 시도하고(유니버설 링크 → 커스텀 스킴), 카카오톡을 열 수 없으면(`NotSupported`)
/// 카카오 계정(웹, ASWebAuthenticationSession)으로 로그인한다. OIDC가 켜져 있어야 `OAuthToken.idToken`이 온다
/// (카카오 개발자 콘솔 > 카카오 로그인 > OpenID Connect 활성화 — herezi-api#57).
@MainActor
final class KakaoLoginProvider: KakaoLoginProviding {
    /// Info.plist `KakaoNativeAppKey`(project.yml ← Config/Secrets.xcconfig). 비어 있으면 로그인은 `notConfigured`.
    static var nativeAppKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String,
            !key.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return key
    }

    /// 앱 시작 때 한 번. 키가 없으면 초기화하지 않는다(빌드·테스트는 키 없이 된다).
    static func initializeSDK() {
        guard let key = nativeAppKey else { return }
        KakaoSDK.initSDK(appKey: key)
    }

    /// 카카오톡에서 돌아온 URL(`kakao{앱키}://oauth?...`)이면 SDK에 넘긴다.
    static func handle(_ url: URL) -> Bool {
        guard nativeAppKey != nil, AuthApi.isKakaoTalkLoginUrl(url) else { return false }
        return AuthController.handleOpenUrl(url: url)
    }

    func idToken(nonce: String) async throws -> String {
        guard Self.nativeAppKey != nil else { throw AuthError.notConfigured }
        do {
            return try await loginWithTalk(nonce: nonce)
        } catch let error as SdkError where Self.isTalkUnavailable(error) {
            return try await loginWithAccount(nonce: nonce)
        }
    }

    func logout() async {
        guard Self.nativeAppKey != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UserApi.shared.logout { @Sendable _ in continuation.resume() }
        }
    }

    func unlink() async {
        guard Self.nativeAppKey != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UserApi.shared.unlink { @Sendable _ in continuation.resume() }
        }
    }

    // MARK: 내부

    private func loginWithTalk(nonce: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            UserApi.shared.loginWithKakaoTalk(nonce: nonce) { @Sendable token, error in
                continuation.resume(with: Self.result(idToken: token?.idToken, error: error))
            }
        }
    }

    private func loginWithAccount(nonce: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            UserApi.shared.loginWithKakaoAccount(loginHint: nil, nonce: nonce) { @Sendable token, error in
                continuation.resume(with: Self.result(idToken: token?.idToken, error: error))
            }
        }
    }

    /// SDK 결과 → id_token 또는 도메인 오류. 카카오톡 불가(`NotSupported`)는 SdkError 그대로 던져 계정 로그인으로 넘긴다.
    private nonisolated static func result(idToken: String?, error: (any Error)?) -> Result<String, any Error> {
        if let error {
            if let sdk = error as? SdkError {
                if isTalkUnavailable(sdk) { return .failure(sdk) }
                if isCancelled(sdk) { return .failure(AuthError.cancelled) }
            }
            if (error as? URLError) != nil { return .failure(AuthError.offline) }
            return .failure(AuthError.failed)
        }
        // id_token이 없으면 콘솔에서 OIDC가 꺼진 것 — 로그인 실패로 본다.
        guard let idToken, !idToken.isEmpty else { return .failure(AuthError.failed) }
        return .success(idToken)
    }

    private nonisolated static func isTalkUnavailable(_ error: SdkError) -> Bool {
        guard case .ClientFailed(let reason, _) = error else { return false }
        return reason == .NotSupported
    }

    private nonisolated static func isCancelled(_ error: SdkError) -> Bool {
        switch error {
        case .ClientFailed(let reason, _): reason == .Cancelled
        // 카카오톡 동의 화면에서 취소하면 access_denied.
        case .AuthFailed(let reason, _): reason == .AccessDenied
        default: false
        }
    }
}
