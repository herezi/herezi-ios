import Domain
import SwiftUI

// 홈(S1)·전체 목록(S1b) 공통 컴포넌트: 알약 칩, 섹션 제목, 히어로 카드, 가로 카드, 위치 꺼짐 배너.

// MARK: - 알약 (DESIGN §6.2) — 홈 카테고리 줄과 S1b 칩이 같이 쓴다

/// 글자 알약. 선택 = 잉크 배경·흰 글자, 비선택 = bg.secondary·잉크 글자.
/// `dot`이 있으면 라벨 앞에 8pt 카테고리 색 원, `leadingSymbol`이 있으면 아이콘(무료만 체크).
public struct HZPill: View {
    let title: String
    let dot: Color?
    let leadingSymbol: String?
    let selected: Bool

    public init(_ title: String, dot: Color? = nil, leadingSymbol: String? = nil, selected: Bool) {
        self.title = title
        self.dot = dot
        self.leadingSymbol = leadingSymbol
        self.selected = selected
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 12, weight: .bold))
            }
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(title)
                .font(selected ? HZTextStyle.caption.font(weight: .semibold) : Font.hz.caption)
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.hz.textInverse : Color.hz.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: HZSize.chip)
        .background(selected ? Color.hz.bgInverse : Color.hz.bgSecondary, in: Capsule())
        .frame(minHeight: HZSize.touch)
        .contentShape(Rectangle())
        .animation(HZMotion.fast, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 섹션 제목 (DESIGN §6.16)

public struct HZSectionHeader: View {
    let title: String
    let onSeeAll: (() -> Void)?

    public init(_ title: String, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.onSeeAll = onSeeAll
    }

    public var body: some View {
        HStack {
            Text(title)
                .hzText(.title2)
                .foregroundStyle(Color.hz.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: HZSpace.s2)
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 2) {
                        Text("전체 보기")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(HZTextButtonStyle(.caption))
                .accessibilityLabel("\(title), 전체 보기")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, HZSpace.screen)
    }
}

// MARK: - 히어로 카드 (DESIGN §6.13)

/// 홈 '지금 가장 가까운 곳' 1장. 사진(없으면 타이포 포스터) + 아래 어두운 그라데이션 위 흰 제목·메타.
public struct HeroCard: View {
    let spot: Spot
    let badge: String?
    let meta: String
    let isSaved: Bool
    let onToggleSave: () -> Void
    /// 테스트에서 사진(불러오기 성공 상태)을 직접 넣을 때만 쓴다. nil이면 `SpotImage`.
    let mediaOverride: AnyView?

    public init(spot: Spot, badge: String?, meta: String, isSaved: Bool, onToggleSave: @escaping () -> Void) {
        self.init(spot: spot, badge: badge, meta: meta, isSaved: isSaved, onToggleSave: onToggleSave, media: nil)
    }

    init(
        spot: Spot, badge: String?, meta: String, isSaved: Bool, onToggleSave: @escaping () -> Void,
        media: AnyView?
    ) {
        self.spot = spot
        self.badge = badge
        self.meta = meta
        self.isSaved = isSaved
        self.onToggleSave = onToggleSave
        self.mediaOverride = media
    }

    @ViewBuilder private var media: some View {
        if let mediaOverride {
            mediaOverride
        } else {
            SpotImage(spot: spot, fallback: .poster(.init(showsTitle: false, showsLabel: false, topInset: 44)))
        }
    }

    public var body: some View {
        // 카드 크기는 7:4 틀(Color.clear)이 정하고, 사진은 background로 깐다.
        // scaledToFill 사진을 ZStack에 직접 넣으면 사진 크기만큼 ZStack이 커져서
        // 아래쪽 그라데이션·제목·메타가 잘린 영역 밖으로 밀려난다(#23).
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 200)
            .aspectRatio(7 / 4, contentMode: .fit)
            .background { media }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.hz.ink.opacity(0), location: 0.3),
                        .init(color: Color.hz.ink.opacity(0.6), location: 0.6),
                        .init(color: Color.hz.ink.opacity(0.85), location: 1),
                    ], startPoint: .top, endPoint: .bottom
                )
                .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: HZSpace.s1) {
                    Text(spot.title)
                        .hzText(.title1)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(meta)
                        .font(Font.hz.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                }
                .padding(HZSpace.s4)
            }
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(HZTextStyle.caption.font(weight: .bold))
                        .foregroundStyle(Color.hz.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.white, in: Capsule())
                        .padding(HZSpace.s3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: HZRadius.lg))
            .contentShape(RoundedRectangle(cornerRadius: HZRadius.lg))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([spot.title, badge, meta].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            // 저장 버튼은 카드 탭과 겹치지 않게 따로 (터치 44).
            .overlay(alignment: .topTrailing) {
                Button(action: onToggleSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.hz.iconPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.9)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isSaved)
                .accessibilityLabel(isSaved ? "저장 취소" : "저장")
                .padding(HZSpace.s1)
            }
    }
}

// MARK: - 가로 카드 (DESIGN §6.14)

public struct SpotTile: View {
    let spot: Spot
    let badge: Badge?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 이미지 위 작은 배지 하나.
    public enum Badge: Sendable {
        case free
        /// "오늘 18:00까지" (흰 배경·잉크 글자)
        case text(String)
    }

    public init(spot: Spot, badge: Badge?) {
        self.spot = spot
        self.badge = badge
    }

    private var width: CGFloat { dynamicTypeSize.isAccessibilitySize ? 200 : 148 }

    public var body: some View {
        VStack(alignment: .leading, spacing: HZSpace.s2) {
            // 배지가 있으면 포스터의 카테고리 라벨 자리(왼쪽 위)를 배지가 쓴다.
            SpotImage(spot: spot, fallback: .poster(.init(showsLabel: badge == nil)))
                .frame(width: width, height: width * 112 / 148)
                .clipShape(RoundedRectangle(cornerRadius: HZRadius.md))
                .overlay(alignment: .topLeading) { badgeView.padding(HZSpace.s2) }
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.title)
                    .hzText(.bodyStrong)
                    .foregroundStyle(Color.hz.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    CategoryDot(spot.category)
                    Text(metaText)
                        .font(Font.hz.caption.monospacedDigit())
                        .foregroundStyle(Color.hz.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var metaText: String {
        if let distance = SpotFormatting.distance(meters: spot.distanceMeters) {
            return "\(spot.category.displayName) · \(distance)"
        }
        return spot.category.displayName
    }

    private var accessibilityText: String {
        var parts = [spot.title, spot.category.displayName]
        if let distance = SpotFormatting.spokenDistance(meters: spot.distanceMeters) { parts.append(distance) }
        parts.append(SpotFormatting.spokenPeriod(start: spot.startsAt, end: spot.endsAt))
        switch badge {
        case .free: parts.append("무료")
        case .text(let text): parts.append(text)
        case nil: break
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var badgeView: some View {
        switch badge {
        case .free:
            HZBadge(.free)
        case .text(let text):
            Text(text)
                .font(Font.hz.micro)
                .foregroundStyle(Color.hz.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white, in: RoundedRectangle(cornerRadius: HZRadius.xs))
        case nil:
            EmptyView()
        }
    }
}

// MARK: - 위치 꺼짐 배너 (DESIGN §6.8)

/// 배너 버튼 설정 (App이 권한 상태에 맞춰 넘긴다).
public struct LocationBannerConfig {
    public let actionTitle: String
    public let action: () -> Void

    public init(actionTitle: String, action: @escaping () -> Void) {
        self.actionTitle = actionTitle
        self.action = action
    }
}

public struct LocationBanner: View {
    let actionTitle: String
    let action: () -> Void

    /// - Parameter actionTitle: 권한을 한 번도 묻지 않았으면 "허용하기", 아니면 "설정".
    public init(actionTitle: String, action: @escaping () -> Void) {
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: HZSpace.s2) {
            Image(systemName: "location.slash")
                .font(.system(size: 16))
                .foregroundStyle(Color.hz.textSecondary)
                .accessibilityHidden(true)
            Text("위치를 확인할 수 없어 서울시청 기준으로 보여드려요")
                .font(Font.hz.caption)
                .foregroundStyle(Color.hz.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .font(HZTextStyle.caption.font(weight: .bold))
                .foregroundStyle(Color.hz.textPrimary)
                .frame(minHeight: HZSize.touch)
        }
        .padding(.horizontal, HZSpace.s4)
        .padding(.vertical, 2)
        .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
        .padding(.horizontal, HZSpace.screen)
    }
}
