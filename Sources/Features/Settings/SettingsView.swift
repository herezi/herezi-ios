import DesignSystem
import Domain
import SwiftUI
import UIKit

/// S6 설정 (herezi-api docs/design/screens/S6-settings.md). 하단 MY 탭의 루트 화면(DESIGN §6.12) — 큰 제목 "MY", 뒤로 없음.
/// 평평한 흰 목록, 행 높이 56, 구분선 없음. 하위 화면(정보 출처·라이선스·탈퇴 확인)은 MY 탭 스택 안에서 push.
public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showsSources = false
    @State private var showsLicenses = false
    @State private var browser: BrowserLink?
    @State private var confirmingLogout = false
    @State private var showsDeleteAccount = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let onAccountDeleted: () -> Void

    /// - Parameter onAccountDeleted: 탈퇴 완료 화면의 **확인** → 탭을 처음 상태로, 주변 탭 홈(S1)으로.
    public init(viewModel: SettingsViewModel, onAccountDeleted: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onAccountDeleted = onAccountDeleted
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.account != nil {
                    group("계정") { accountRows }
                }
                group("위치") {
                    SettingsRow(title: "위치 권한", value: viewModel.permissionText, chevron: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .accessibilityHint("설정 앱이 열려요")
                }
                group("정보") {
                    SettingsRow(title: "공지사항", chevron: true) { browser = BrowserLink(SettingsViewModel.noticesURL) }
                        .accessibilityHint("브라우저가 열려요")
                    SettingsRow(title: "정보 출처", chevron: true) { showsSources = true }
                    SettingsRow(title: "이용약관", chevron: true) { browser = BrowserLink(SettingsViewModel.termsURL) }
                        .accessibilityHint("브라우저가 열려요")
                    SettingsRow(title: "개인정보 처리방침", chevron: true) {
                        browser = BrowserLink(SettingsViewModel.privacyURL)
                    }
                    .accessibilityHint("브라우저가 열려요")
                    SettingsRow(title: "오픈소스 라이선스", chevron: true) { showsLicenses = true }
                }
                group("도움") {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsRow(title: "정보 오류 제보", chevron: true) {
                            openURL(viewModel.reportMailURL) { accepted in
                                if !accepted { viewModel.showMailUnavailable() }
                            }
                        }
                        .accessibilityHint("메일 앱이 열려요")
                        // 메일 앱이 없어도 주소를 복사할 수 있게 선택 가능한 글자로 보여준다.
                        Text(viewModel.supportEmail)
                            .font(Font.hz.caption)
                            .foregroundStyle(Color.hz.textSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, HZSpace.screen)
                            .padding(.bottom, HZSpace.s2)
                    }
                }
                SettingsRow(title: "앱 버전", value: viewModel.versionText)
                    .padding(.top, HZSpace.s6)
                Text("지금 내 주변, 히어지")
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HZSpace.s8)
            }
        }
        .background(Color.hz.bgPrimary)
        .navigationTitle("MY")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showsSources) { SourcesView() }
        .navigationDestination(isPresented: $showsLicenses) { LicensesView() }
        .sheet(item: $browser) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .navigationDestination(isPresented: $showsDeleteAccount) {
            if let account = viewModel.account {
                DeleteAccountView(viewModel: DeleteAccountViewModel(actions: account), onFinished: onAccountDeleted)
            }
        }
        .alert(SettingsViewModel.logoutTitle, isPresented: $confirmingLogout) {
            Button("로그아웃") { Task { await viewModel.logout() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text(SettingsViewModel.logoutMessage)
        }
        .hzToast(message: $viewModel.toastMessage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refresh() }
        }
    }

    /// 로그인 전: **로그인** 행 하나. 로그인 후: 계정 행(제공자 표시) · 로그아웃 · 회원 탈퇴 (DESIGN §6.19).
    @ViewBuilder private var accountRows: some View {
        if let provider = viewModel.provider, let title = viewModel.accountTitle {
            HStack(spacing: HZSpace.s3) {
                ProviderBadge(provider)
                Text(title)
                    .font(Font.hz.body)
                    .foregroundStyle(Color.hz.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HZSpace.screen)
            .frame(minHeight: 56)
            .accessibilityElement(children: .combine)
            SettingsRow(title: "로그아웃", chevron: true) { confirmingLogout = true }
            SettingsRow(title: "회원 탈퇴", chevron: true, secondary: true) { showsDeleteAccount = true }
        } else {
            SettingsRow(title: "로그인", chevron: true) { viewModel.login() }
                .accessibilityHint("로그인 창이 열려요")
        }
    }

    private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Font.hz.caption)
                .foregroundStyle(Color.hz.textSecondary)
                .padding(.horizontal, HZSpace.screen)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
        .padding(.top, HZSpace.s6)
    }
}

/// 설정 행: 높이 56, 좌우 20, 제목 body, 오른쪽 값(body secondary) + chevron.
struct SettingsRow: View {
    let title: String
    var value: String?
    var chevron = false
    /// 위계만 낮춘 글자(회원 탈퇴) — text.secondary.
    var secondary = false
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(RowButtonStyle())
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        HStack(spacing: HZSpace.s2) {
            Text(title)
                .font(Font.hz.body)
                .foregroundStyle(secondary ? Color.hz.textSecondary : Color.hz.textPrimary)
            Spacer(minLength: HZSpace.s3)
            if let value {
                Text(value)
                    .font(Font.hz.body)
                    .foregroundStyle(Color.hz.textSecondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hz.iconSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, HZSpace.screen)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// 누름 상태: 배경 bg.secondary.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.hz.bgSecondary : Color.clear)
    }
}

/// 정보 출처 목록. 각 행은 인앱 브라우저로 연다.
struct SourcesView: View {
    @State private var browser: BrowserLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SettingsViewModel.dataSources) { source in
                    Button {
                        browser = BrowserLink(source.url)
                    } label: {
                        HStack {
                            Text(source.name)
                                .font(Font.hz.body)
                                .foregroundStyle(Color.hz.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.hz.iconSecondary)
                        }
                        .padding(.horizontal, HZSpace.screen)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityHint("브라우저가 열려요")
                }
                Text(SettingsViewModel.aiNotice)
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textSecondary)
                    .padding(.horizontal, HZSpace.screen)
                    .padding(.top, HZSpace.s4)
            }
            .padding(.top, HZSpace.s2)
        }
        .background(Color.hz.bgPrimary)
        .navigationTitle("정보 출처")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browser) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }
}

/// 오픈소스 라이선스: 이름·라이선스 이름 + 번들에 든 라이선스 전문.
struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HZSpace.s6) {
                ForEach(SettingsViewModel.openSourceLicenses) { item in
                    VStack(alignment: .leading, spacing: HZSpace.s2) {
                        Text(item.name)
                            .hzText(.title3)
                            .foregroundStyle(Color.hz.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.license)
                            .font(Font.hz.caption)
                            .foregroundStyle(Color.hz.textSecondary)
                        Link(item.url.absoluteString, destination: item.url)
                            .font(Font.hz.caption)
                            .foregroundStyle(Color.hz.textSecondary)
                        if let text = Self.text(item.licenseFile) {
                            Text(text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.hz.textSecondary)
                                .textSelection(.enabled)
                                .padding(HZSpace.s3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
                        }
                    }
                }
            }
            .padding(.horizontal, HZSpace.screen)
            .padding(.vertical, HZSpace.s4)
        }
        .background(Color.hz.bgPrimary)
        .navigationTitle("오픈소스 라이선스")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func text(_ file: String) -> String? {
        guard let url = Bundle.main.resourceURL?.appending(path: file) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
