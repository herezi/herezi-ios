import SwiftUI

// DESIGN §6의 공통 컴포넌트: 배지, 버튼, 상태 화면, 스켈레톤, 토스트.

// MARK: - 배지 (DESIGN §6.9)

public struct HZBadge: View {
    public enum Kind: Sendable {
        case free, ended
    }

    let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        Text(kind == .free ? "무료" : "종료됨")
            .font(Font.hz.micro)
            .foregroundStyle(kind == .free ? Color.hz.badgeFreeFg : Color.hz.badgeEndedFg)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                kind == .free ? Color.hz.badgeFreeBg : Color.hz.badgeEndedBg,
                in: RoundedRectangle(cornerRadius: HZRadius.xs))
    }
}

// MARK: - 버튼 (DESIGN §6.10)

/// 주 버튼: 높이 56, 잉크 배경, 흰 title3, radius.lg, 가로로 꽉 채움.
public struct HZPrimaryButtonStyle: ButtonStyle {
    let height: CGFloat
    let radius: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    public init(height: CGFloat = HZSize.buttonLarge, radius: CGFloat = HZRadius.lg) {
        self.height = height
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(height >= HZSize.buttonLarge ? Font.hz.title3 : Font.hz.bodyStrong)
            .foregroundStyle(isEnabled ? Color.hz.textInverse : Color.hz.disabledFg)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                isEnabled ? Color.hz.bgInverse : Color.hz.disabledBg, in: RoundedRectangle(cornerRadius: radius)
            )
            .pressEffect(configuration.isPressed)
    }
}

/// 보조 버튼: 높이 56, bg.secondary 배경, 잉크 글자.
public struct HZSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.hz.title3)
            .foregroundStyle(Color.hz.textPrimary)
            .frame(maxWidth: .infinity, minHeight: HZSize.buttonLarge)
            .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.lg))
            .pressEffect(configuration.isPressed)
    }
}

/// 글자 버튼: 높이 44, 글자만.
public struct HZTextButtonStyle: ButtonStyle {
    let style: HZTextStyle
    let color: Color

    public init(_ style: HZTextStyle = .body, color: Color = Color.hz.textSecondary) {
        self.style = style
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(style.font)
            .foregroundStyle(color)
            .frame(minHeight: HZSize.touch)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// 눌림: 불투명도 85% + 0.98 축소 (motion.fast).
    fileprivate func pressEffect(_ pressed: Bool) -> some View {
        opacity(pressed ? 0.85 : 1)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(HZMotion.fast, value: pressed)
    }
}

// MARK: - 상태 화면 (DESIGN §6.7)

/// 빈 상태·오류 공통: 가운데 정렬, 위 여백 space.10, 아이콘 48, 제목 title2, 설명 body secondary, 버튼(선택).
public struct HZStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String?
    let iconColor: Color
    let actions: Actions

    public init(
        symbol: String, title: String, message: String? = nil, iconColor: Color = Color.hz.iconSecondary,
        @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.iconColor = iconColor
        self.actions = actions()
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: HZSpace.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 48))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                    .padding(.bottom, HZSpace.s1)
                Text(title)
                    .hzText(.title2)
                    .foregroundStyle(Color.hz.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .hzText(.body)
                        .foregroundStyle(Color.hz.textSecondary)
                }
                actions
                    .padding(.top, HZSpace.s3)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, HZSpace.screen)
            .padding(.top, HZSpace.s10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension HZStateView where Actions == EmptyView {
    public init(symbol: String, title: String, message: String? = nil, iconColor: Color = Color.hz.iconSecondary) {
        self.init(symbol: symbol, title: title, message: message, iconColor: iconColor) { EmptyView() }
    }
}

/// 상태 화면의 버튼(높이 44, 잉크 배경, radius.sm, 좌우 20).
public struct HZStateButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title).padding(.horizontal, HZSpace.s5)
        }
        .buttonStyle(HZPrimaryButtonStyle(height: HZSize.buttonMedium, radius: HZRadius.sm))
        .fixedSize()
    }
}

// MARK: - 스켈레톤 (DESIGN §6.7)

/// 카드 자리 스켈레톤: 썸네일 72 + 글줄 3개(40%·80%·55%). 1.2초 주기로 깜빡임(동작 줄이기 시 정지).
public struct HZSkeletonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: HZSpace.s3) {
            RoundedRectangle(cornerRadius: HZRadius.md)
                .fill(Color.hz.bgSecondary)
                .frame(width: HZSize.thumb, height: HZSize.thumb)
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: HZSpace.s3) {
                    bar(width: proxy.size.width * 0.4)
                    bar(width: proxy.size.width * 0.8)
                    bar(width: proxy.size.width * 0.55)
                }
                .padding(.top, HZSpace.s1)
            }
            .frame(height: HZSize.thumb)
        }
        .padding(.horizontal, HZSpace.screen)
        .padding(.vertical, HZSpace.s4)
        .opacity(dimmed ? 0.6 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: HZRadius.xs)
            .fill(Color.hz.bgSecondary)
            .frame(width: width, height: 12)
    }
}

/// 스켈레톤 카드 n장 (기본 5장).
public struct HZSkeletonList: View {
    let count: Int

    public init(count: Int = 5) {
        self.count = count
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in HZSkeletonCard() }
            Spacer(minLength: 0)
        }
        .accessibilityElement()
        .accessibilityLabel("불러오는 중")
    }
}

// MARK: - 토스트 (DESIGN §6.11)

/// 화면 아래 잠깐 뜨는 알림. `action`이 있으면 오른쪽에 글자 버튼(예: "되돌리기").
public struct HZToast: Equatable, Sendable {
    public let id = UUID()
    public let message: String
    public let actionTitle: String?
    public let duration: Duration

    public init(_ message: String, actionTitle: String? = nil, duration: Duration = .seconds(2.5)) {
        self.message = message
        self.actionTitle = actionTitle
        self.duration = duration
    }
}

extension View {
    /// `toast`가 생기면 아래에 띄우고 `duration` 뒤 nil로 되돌린다.
    public func hzToast(_ toast: Binding<HZToast?>, action: (@MainActor () -> Void)? = nil) -> some View {
        modifier(ToastModifier(toast: toast, action: action))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: HZToast?
    let action: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let current = toast {
                HStack(spacing: HZSpace.s3) {
                    Text(current.message)
                        .font(Font.hz.caption)
                        .foregroundStyle(Color.hz.textInverse)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let title = current.actionTitle, let action {
                        Button(title) {
                            action()
                            toast = nil
                        }
                        .font(HZTextStyle.caption.font(weight: .bold))
                        .foregroundStyle(Color.hz.textInverse)
                    }
                }
                .padding(.horizontal, HZSpace.s4)
                .padding(.vertical, HZSpace.s3)
                .background(Color.hz.bgInverse, in: RoundedRectangle(cornerRadius: HZRadius.sm))
                .padding(.horizontal, HZSpace.screen)
                .padding(.bottom, HZSpace.s4)
                .transition(.opacity)
                .task(id: current.id) {
                    try? await Task.sleep(for: current.duration)
                    if toast?.id == current.id { toast = nil }
                }
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear { AccessibilityNotification.Announcement(current.message).post() }
            }
        }
        .animation(HZMotion.base, value: toast)
    }
}

extension View {
    /// 뷰모델의 `toastMessage: String?`를 토스트로 띄운다. 띄우면 바로 nil로 되돌린다.
    public func hzToast(message: Binding<String?>) -> some View {
        modifier(MessageToastModifier(message: message))
    }
}

private struct MessageToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var toast: HZToast?

    func body(content: Content) -> some View {
        content
            .hzToast($toast)
            .onChange(of: message, initial: true) { _, newValue in
                guard let newValue else { return }
                toast = HZToast(newValue)
                message = nil
            }
    }
}
