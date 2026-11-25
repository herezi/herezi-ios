import Domain
import SwiftUI

// MARK: - 카카오 브랜드 (DESIGN §2.5, §6.18)

/// 카카오 브랜드 노랑. 카카오 로그인 버튼과 S6 제공자 표시에만 쓴다(DESIGN §2.5 예외).
public enum HZBrand {
    public static let kakaoYellow = Color(hex: 0xFEE500)
    /// 카카오 버튼 글자: 검정 85%.
    public static let kakaoLabel = Color.black.opacity(0.85)
}

/// 카카오 말풍선 심볼 (24 기준 경로 — herezi-api docs/design/mockups/login-sheet.svg `i-kakao`).
/// TODO: 카카오 디자인 가이드 배포 리소스로 교체(가이드는 배포 리소스를 그대로 쓰라고 한다).
public struct KakaoSymbol: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(12, 3.6))
        path.addCurve(to: point(2.8, 10.85), control1: point(6.9, 3.6), control2: point(2.8, 6.85))
        path.addCurve(to: point(7.1, 17), control1: point(2.8, 13.45), control2: point(4.52, 15.72))
        path.addLine(to: point(6, 21.02))
        path.addCurve(to: point(6.61, 21.46), control1: point(5.9, 21.38), control2: point(6.3, 21.67))
        path.addLine(to: point(11.36, 18.31))
        path.addCurve(to: point(12, 18.34), control1: point(11.57, 18.33), control2: point(11.78, 18.34))
        path.addCurve(to: point(21.2, 11.09), control1: point(17.1, 18.34), control2: point(21.2, 15.09))
        path.addCurve(to: point(12, 3.6), control1: point(21.2, 7.09), control2: point(17.1, 3.6))
        path.closeSubpath()
        return path
    }
}

/// 카카오 로그인 버튼 (DESIGN §6.18): 높이 56(다이나믹 타입에 따라 늘어남), 모서리 12, 심볼 24 왼쪽 20, 글자 가운데 title3.
/// 진행 중이면 글자 자리에 작은 진행 표시(검정 85%). 눌림은 불투명도 85%만(축소 없음).
public struct KakaoLoginButton: View {
    let isLoading: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(isLoading: Bool = false, action: @escaping () -> Void) {
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(HZBrand.kakaoLabel)
                        .frame(width: 20, height: 20)
                        .accessibilityLabel("로그인 중")
                } else {
                    Text("카카오로 계속하기")
                        .font(Font.hz.title3)
                        .foregroundStyle(HZBrand.kakaoLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 52)
                        .padding(.vertical, HZSpace.s3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: HZSize.buttonLarge)
            .overlay(alignment: .leading) {
                KakaoSymbol()
                    .fill(Color.black)
                    .frame(width: 24, height: 24)
                    .padding(.leading, HZSpace.s5)
                    .accessibilityHidden(true)
            }
            .background(HZBrand.kakaoYellow, in: RoundedRectangle(cornerRadius: HZRadius.md))
            .contentShape(RoundedRectangle(cornerRadius: HZRadius.md))
        }
        .buttonStyle(BrandPressStyle())
        .opacity(isEnabled || isLoading ? 1 : 0.4)
        .accessibilityLabel(isLoading ? "로그인 중" : "카카오로 계속하기")
    }
}

/// 브랜드 버튼 눌림: 불투명도 85%(모양은 바꾸지 않는다).
struct BrandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - 계정 행 (DESIGN §6.19)

/// 제공자 표시 28 원: 카카오 = 노랑 + 검정 심볼 18, Apple = 검정 + 흰 로고 16. 장식(스크린리더 숨김).
public struct ProviderBadge: View {
    let provider: AuthProvider

    public init(_ provider: AuthProvider) {
        self.provider = provider
    }

    public var body: some View {
        ZStack {
            switch provider {
            case .kakao:
                Circle().fill(HZBrand.kakaoYellow)
                KakaoSymbol().fill(Color.black).frame(width: 18, height: 18)
            case .apple:
                Circle().fill(Color.black)
                Image(systemName: "apple.logo")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
