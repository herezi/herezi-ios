import AuthenticationServices
import DesignSystem
import Domain
import SwiftUI

/// S7 로그인 시트 (herezi-api docs/design/screens/S7-login.md, DESIGN §6.17).
/// App이 `.sheet(item: $auth.loginRequest)`로 띄운다. 앱 어디서 열려도 같은 시트 — 제목과 대기 동작만 다르다.
public struct LoginSheet: View {
    @State private var viewModel: LoginViewModel
    @State private var contentHeight: CGFloat = 380
    @State private var browser: BrowserLink?
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: LoginViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.hz.bgPrimary)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(HZRadius.xl)
        .interactiveDismissDisabled(viewModel.isBusy)
        .accessibilityAddTraits(.isModal)
        .sheet(item: $browser) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .onAppear { titleFocused = true }
        .onChange(of: viewModel.errorMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.title)
                .hzText(.title2)
                .foregroundStyle(Color.hz.textPrimary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .padding(.trailing, HZSize.touch)
            Text(LoginViewModel.reason)
                .hzText(.body)
                .foregroundStyle(Color.hz.textSecondary)
                .padding(.top, HZSpace.s2)
            if let error = viewModel.errorMessage {
                HStack(spacing: HZSpace.s2) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.hz.statusError)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(Font.hz.caption)
                        .foregroundStyle(Color.hz.textPrimary)
                }
                .padding(.top, HZSpace.s4)
            }
            VStack(spacing: HZSpace.s3) {
                KakaoLoginButton(isLoading: viewModel.inProgress == .kakao) {
                    Task { await viewModel.loginWithKakao() }
                }
                .disabled(viewModel.isBusy)
                appleButton
            }
            .padding(.top, HZSpace.s6)
            termsLine
                .padding(.top, HZSpace.s5)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, HZSpace.screen)
        .padding(.top, HZSpace.s8 + HZSpace.s4)
        .padding(.bottom, HZSpace.s3)
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.hz.iconPrimary)
                .frame(width: HZSize.touch, height: HZSize.touch)
                .contentShape(Rectangle())
        }
        .disabled(viewModel.isBusy)
        .opacity(viewModel.isBusy ? 0.4 : 1)
        .accessibilityLabel("닫기")
        .accessibilitySortPriority(-1)
        .padding(.trailing, HZSpace.s2)
        .padding(.top, HZSpace.s3)
    }

    /// 시스템 버튼 — 로고·글자("Apple로 계속하기")는 시스템이 넣는다. 카카오 버튼과 같은 크기·모서리.
    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []  // 이메일·이름은 받지 않는다(S6, TECH-PLAN §4.1 개인정보).
            request.nonce = viewModel.beginApple()
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential
                Task { await viewModel.completeApple(identityToken: credential?.identityToken) }
            case .failure(let error):
                let code = (error as? ASAuthorizationError)?.code
                viewModel.failApple(cancelled: code == .canceled)
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: HZSize.buttonLarge)
        .clipShape(RoundedRectangle(cornerRadius: HZRadius.md))
        .overlay {
            if viewModel.inProgress == .apple {
                RoundedRectangle(cornerRadius: HZRadius.md)
                    .fill(Color.black)
                    .overlay { ProgressView().tint(.white) }
                    .accessibilityElement()
                    .accessibilityLabel("로그인 중")
            }
        }
        .disabled(viewModel.isBusy)
        .opacity(viewModel.isBusy && viewModel.inProgress != .apple ? 0.4 : 1)
    }

    /// "계속하면 만 14세 이상이며 [이용약관]과 [개인정보 처리방침]에 동의하는 것으로 봐요." — 링크는 시트를 닫지 않고 인앱 브라우저.
    private var termsLine: some View {
        Text(Self.termsText)
            .font(Font.hz.caption)
            .foregroundStyle(Color.hz.textSecondary)
            .multilineTextAlignment(.center)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    browser = BrowserLink(url)
                    return .handled
                })
    }

    static var termsText: AttributedString {
        var text = AttributedString("계속하면 만 14세 이상이며 ")
        text += link("이용약관", SpotLinks.termsURL)
        text += AttributedString("과 ")
        text += link("개인정보 처리방침", SpotLinks.privacyURL)
        text += AttributedString("에 동의하는 것으로 봐요.")
        return text
    }

    private static func link(_ title: String, _ url: URL) -> AttributedString {
        var part = AttributedString(title)
        part.link = url
        part.foregroundColor = Color.hz.textPrimary
        part.font = HZTextStyle.caption.font(weight: .semibold)
        part.underlineStyle = .single
        return part
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) {
        LoginSheet(
            viewModel: LoginViewModel(
                request: LoginRequest(purpose: .save),
                auth: AuthService(backend: FakeAuthBackend(), storage: InMemorySessionStore()),
                kakao: FakeKakaoLogin()))
    }
}
