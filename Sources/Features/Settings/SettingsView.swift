import DesignSystem
import Domain
import SwiftUI
import UIKit

/// S6 설정 (herezi-api docs/design/screens/S6-settings.md). 평평한 흰 목록, 행 높이 56, 구분선 없음.
public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showsSources = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                group("위치") {
                    SettingsRow(title: "위치 권한", value: viewModel.permissionText, chevron: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .accessibilityHint("설정 앱이 열려요")
                }
                group("정보") {
                    SettingsRow(title: "정보 출처", chevron: true) { showsSources = true }
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
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showsSources) { SourcesView() }
        .hzToast(message: $viewModel.toastMessage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refresh() }
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
                .foregroundStyle(Color.hz.textPrimary)
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
