import DesignSystem
import Domain
import SwiftUI

/// S0 위치 권한 안내 (herezi-api docs/design/screens/S0-onboarding.md).
public struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LogoMark()
                        .padding(.top, HZSpace.s10)
                    Text("지금 내 주변에 뭐가 있는지\n바로 보여드릴게요")
                        .hzText(.display)
                        .foregroundStyle(Color.hz.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, HZSpace.s6)
                        .accessibilityLabel("지금 내 주변에 뭐가 있는지 바로 보여드릴게요")
                        .accessibilityAddTraits(.isHeader)
                    Text("축제, 공연, 전시, 팝업, 벚꽃 명소까지 — 위치만 허용하면 가입 없이 바로 볼 수 있어요.")
                        .hzText(.body)
                        .foregroundStyle(Color.hz.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, HZSpace.s3)
                    if !dynamicTypeSize.isAccessibilitySize {
                        CategoryGrid()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HZSpace.s10)
                    }
                }
                .padding(.horizontal, HZSpace.screen)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: HZSpace.s2) {
                Button("위치 허용하기") { Task { await viewModel.allow() } }
                    .buttonStyle(HZPrimaryButtonStyle())
                    .disabled(viewModel.isRequesting)
                Button("나중에 할게요") { viewModel.later() }
                    .buttonStyle(HZTextButtonStyle())
                Text("위치는 주변 볼거리를 찾는 데만 써요.")
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, HZSpace.screen)
            .padding(.bottom, HZSpace.s4)
        }
        .background(Color.hz.bgPrimary)
    }
}

/// 로고 자리 (56). TODO(design): 로고 에셋(두리번)이 나오면 이미지로 바꾼다.
struct LogoMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: HZRadius.lg)
            .fill(Color.hz.bgInverse)
            .frame(width: 56, height: 56)
            .overlay {
                HStack(spacing: 6) {
                    eye
                    eye
                }
            }
            .accessibilityHidden(true)
    }

    private var eye: some View {
        Ellipse()
            .fill(Color.white)
            .frame(width: 14, height: 18)
            .overlay(alignment: .trailing) {
                Circle().fill(Color.hz.ink).frame(width: 7, height: 7).padding(.trailing, 2)
            }
    }
}

/// 카테고리 아이콘 3×3 (장식, 스크린리더에서 숨김).
struct CategoryGrid: View {
    var body: some View {
        Grid(horizontalSpacing: HZSpace.s5, verticalSpacing: HZSpace.s5) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let category = SpotCategory.allCases[row * 3 + column]
                        CategoryPlaceholder(category, iconSize: 24)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
