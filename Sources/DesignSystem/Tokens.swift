import SwiftUI
import UIKit

// herezi-api docs/design/DESIGN.md의 토큰을 코드로 옮긴 것. 값을 바꾸려면 DESIGN.md를 먼저 고친다.
// 화면 코드는 원색값(팔레트) 대신 의미 토큰(`Color.hz.textPrimary` 등)만 쓴다.

// MARK: - 색 (DESIGN §2)

extension Color {
    /// 의미 토큰. 예: `Color.hz.textPrimary`, `Color.hz.bgInverse`.
    public static let hz = HZColors()

    /// `0xRRGGBB` → sRGB 색.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// 팔레트 원색값 (DESIGN §2.1). 화면 코드는 `HZColors`의 의미 토큰을 쓴다.
public enum HZPalette {
    public static let ink = Color(hex: 0x191F28)
    public static let gray700 = Color(hex: 0x4E5968)
    public static let gray500 = Color(hex: 0x8B95A1)
    public static let gray200 = Color(hex: 0xE5E8EB)
    public static let gray100 = Color(hex: 0xF2F4F6)
    public static let white = Color(hex: 0xFFFFFF)
    public static let red = Color(hex: 0xF04452)
    public static let green700 = Color(hex: 0x08734F)
    public static let green50 = Color(hex: 0xE6F6EF)
}

/// 의미 토큰 (DESIGN §2.2). M1은 라이트 모드만 — 다크 모드는 이 값만 바꿔 대응한다.
public struct HZColors: Sendable {
    public let ink = HZPalette.ink
    public let bgPrimary = HZPalette.white
    public let bgSecondary = HZPalette.gray100
    public let bgInverse = HZPalette.ink
    public let textPrimary = HZPalette.ink
    public let textSecondary = HZPalette.gray700
    /// 입력 힌트·비활성 글자. 18pt 미만 본문에는 쓰지 않는다(대비 3.0).
    public let textTertiary = HZPalette.gray500
    public let textInverse = HZPalette.white
    public let border = HZPalette.gray200
    public let iconPrimary = HZPalette.ink
    public let iconSecondary = HZPalette.gray500
    public let statusError = HZPalette.red
    public let badgeFreeFg = HZPalette.green700
    public let badgeFreeBg = HZPalette.green50
    public let badgeEndedFg = HZPalette.gray700
    public let badgeEndedBg = HZPalette.gray100
    public let scrim = HZPalette.ink.opacity(0.4)
    /// 버튼 비활성 배경·글자 (DESIGN §6.10).
    public let disabledBg = HZPalette.gray200
    public let disabledFg = HZPalette.gray500
}

// MARK: - 글자 (DESIGN §3)

/// 글자 스타일. 크기·줄높이·굵기는 DESIGN §3 표와 같고, 다이나믹 타입은 `relativeTo` 기준으로 커진다.
public enum HZTextStyle: CaseIterable, Sendable {
    case display, title1, title2, title3, body, bodyStrong, caption, micro

    public var size: CGFloat {
        switch self {
        case .display: 26
        case .title1: 22
        case .title2: 19
        case .title3: 17
        case .body, .bodyStrong: 15
        case .caption: 13
        case .micro: 11
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .display: 36
        case .title1: 30
        case .title2: 26
        case .title3: 24
        case .body, .bodyStrong: 22
        case .caption: 18
        case .micro: 14
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .title1, .title2: .bold
        case .title3, .bodyStrong, .micro: .semibold
        case .body: .regular
        case .caption: .medium
        }
    }

    public var relativeTo: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .title1: .title2
        case .title2: .title3
        case .title3: .headline
        case .body, .bodyStrong: .body
        case .caption: .footnote
        case .micro: .caption2
        }
    }

    var uiTextStyle: UIFont.TextStyle {
        switch relativeTo {
        case .largeTitle: .largeTitle
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .footnote: .footnote
        case .caption2: .caption2
        default: .body
        }
    }

    /// 현재 다이나믹 타입에 맞춘 크기 (relativeTo 기준 비율).
    public var scaledSize: CGFloat {
        UIFontMetrics(forTextStyle: uiTextStyle).scaledValue(for: size)
    }

    /// Pretendard는 아직 번들하지 않았다(DESIGN §3) — 시스템 글꼴로 크기·굵기만 맞춘다.
    /// 화면이 다시 그려질 때 다이나믹 타입 크기를 다시 읽는다. 바로 반영돼야 하는 곳은 `.hzText(_:)`를 쓴다.
    public var font: Font {
        .system(size: scaledSize, weight: weight)
    }
}

extension Font {
    /// 예: `Font.hz.title2`.
    public static let hz = HZFonts()
}

public struct HZFonts: Sendable {
    public var display: Font { HZTextStyle.display.font }
    public var title1: Font { HZTextStyle.title1.font }
    public var title2: Font { HZTextStyle.title2.font }
    public var title3: Font { HZTextStyle.title3.font }
    public var body: Font { HZTextStyle.body.font }
    public var bodyStrong: Font { HZTextStyle.bodyStrong.font }
    public var caption: Font { HZTextStyle.caption.font }
    public var micro: Font { HZTextStyle.micro.font }
}

extension View {
    /// 글꼴(다이나믹 타입 즉시 반영) + 줄높이(줄 간격으로 근사)를 함께 적용한다. 예: `.hzText(.title2)`.
    public func hzText(_ style: HZTextStyle) -> some View {
        modifier(HZTextModifier(style: style))
    }
}

private struct HZTextModifier: ViewModifier {
    let style: HZTextStyle
    @ScaledMetric private var size: CGFloat

    init(style: HZTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight))
            .lineSpacing(max(0, (style.lineHeight - style.size * 1.2) * size / style.size))
    }
}

// MARK: - 간격 · 크기 (DESIGN §4)

/// 4pt 격자. 화면 좌우 여백은 `HZSpace.screen`(= s5, 20).
public enum HZSpace {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 20
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    public static let s10: CGFloat = 40
    /// 화면 좌우 여백.
    public static let screen: CGFloat = s5
}

public enum HZSize {
    public static let touch: CGFloat = 44
    public static let chip: CGFloat = 36
    public static let buttonLarge: CGFloat = 56
    public static let buttonMedium: CGFloat = 44
    public static let thumb: CGFloat = 72
    public static let pin: CGFloat = 36
}

// MARK: - 모서리 · 그림자 · 모션 (DESIGN §5)

public enum HZRadius {
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let full: CGFloat = 999
}

/// 그림자는 지도 위에 뜨는 것에만 쓴다. 목록 화면은 `level0`(그림자 없음).
public enum HZElevation: Sendable {
    case level0, level1, level2
}

extension View {
    public func hzElevation(_ level: HZElevation) -> some View {
        switch level {
        case .level0: shadow(color: .clear, radius: 0)
        case .level1: shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        case .level2: shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -4)
        }
    }
}

public enum HZMotion {
    /// 150ms ease-out — 칩·토글 선택, 저장 아이콘.
    public static let fast = Animation.easeOut(duration: 0.15)
    /// 250ms ease-in-out — 목록↔지도 전환, 배너 등장.
    public static let base = Animation.easeInOut(duration: 0.25)
    /// 350ms spring(감쇠 0.85) — 시트, 선택 핀 확대.
    public static let slow = Animation.spring(duration: 0.35, bounce: 0.15)

    /// "동작 줄이기"가 켜져 있으면 이동·확대 대신 짧은 페이드만.
    public static func adjusted(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}
