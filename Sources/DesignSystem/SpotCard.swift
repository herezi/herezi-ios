import Domain
import SwiftUI

/// 스팟 카드 (DESIGN §6.1). 목록·검색·저장·지도 시트에서 같은 카드를 쓴다.
///
/// 썸네일 72 + [카테고리 점 · 카테고리 · 거리] / 제목(2줄) / 기간 / 배지 줄.
/// 다이나믹 타입이 접근성 크기면 썸네일을 위로 올린 세로 배치로 바뀐다.
public struct SpotCard: View {
    let spot: Spot
    let distanceMeters: Int?
    let showsEnded: Bool
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - distanceMeters: 기본은 서버가 준 `spot.distanceMeters`. 저장 목록처럼 앱이 계산할 때 넘긴다.
    ///   - showsEnded: 저장 목록에서만 true. 끝난 항목이면 40% 흐리게 + `종료됨` 배지.
    public init(spot: Spot, distanceMeters: Int?? = nil, showsEnded: Bool = false, now: Date = Date()) {
        self.spot = spot
        self.distanceMeters = distanceMeters ?? spot.distanceMeters
        self.showsEnded = showsEnded
        self.now = now
    }

    private var isEnded: Bool { showsEnded && spot.isEnded }
    private var dimmed: Double { isEnded ? 0.4 : 1 }

    public var body: some View {
        layout {
            thumbnail
                .opacity(dimmed)
            VStack(alignment: .leading, spacing: HZSpace.s1) {
                meta.opacity(dimmed)
                Text(spot.title)
                    .hzText(.title3)
                    .foregroundStyle(Color.hz.textPrimary)
                    .lineLimit(2)
                    .opacity(dimmed)
                period.opacity(dimmed)
                if isEnded || spot.isFree == true {
                    HStack(spacing: HZSpace.s2) {
                        if isEnded { HZBadge(.ended) }
                        if spot.isFree == true { HZBadge(.free).opacity(dimmed) }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HZSpace.screen)
        .padding(.vertical, HZSpace.s4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private func layout(@ViewBuilder content: () -> some View) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: HZSpace.s3) { content() }
        } else {
            HStack(alignment: .top, spacing: HZSpace.s3) { content() }
        }
    }

    private var thumbnail: some View {
        SpotImage(spot: spot, iconSize: 28)
            .frame(width: HZSize.thumb, height: HZSize.thumb)
            .clipShape(RoundedRectangle(cornerRadius: HZRadius.md))
    }

    private var metaText: String {
        if let distance = SpotFormatting.distance(meters: distanceMeters) {
            return "\(spot.category.displayName) · \(distance)"
        }
        if let place = spot.placeName {
            return "\(spot.category.displayName) · \(place)"
        }
        return spot.category.displayName
    }

    private var meta: some View {
        HStack(spacing: 6) {
            CategoryDot(spot.category)
            Text(metaText)
                .font(Font.hz.caption.monospacedDigit())
                .foregroundStyle(Color.hz.textSecondary)
                .lineLimit(1)
        }
    }

    private var period: some View {
        let period = SpotFormatting.cardPeriod(start: spot.startsAt, end: spot.endsAt, now: now)
        return Text(period.text)
            .font(period.emphasized ? Font.hz.caption.weight(.semibold) : Font.hz.caption.monospacedDigit())
            .foregroundStyle(period.emphasized ? Color.hz.textPrimary : Color.hz.textSecondary)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if isEnded { parts.append("종료됨") }
        parts.append(spot.title)
        parts.append(spot.category.displayName)
        if let distance = SpotFormatting.spokenDistance(meters: distanceMeters) {
            parts.append(distance)
        } else if let place = spot.placeName {
            parts.append(place)
        }
        parts.append(SpotFormatting.spokenPeriod(start: spot.startsAt, end: spot.endsAt))
        if spot.isFree == true { parts.append("무료") }
        return parts.joined(separator: ", ")
    }
}

/// 대표 이미지. `imageURL`이 없거나 실패하면 카테고리 색 배경 + 아이콘.
public struct SpotImage: View {
    let spot: Spot
    let iconSize: CGFloat

    public init(spot: Spot, iconSize: CGFloat) {
        self.spot = spot
        self.iconSize = iconSize
    }

    public var body: some View {
        if let url = spot.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    CategoryPlaceholder(spot.category, iconSize: iconSize)
                default:
                    Color.hz.bgSecondary
                }
            }
            .accessibilityLabel("\(spot.title) 사진")
        } else {
            CategoryPlaceholder(spot.category, iconSize: iconSize)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(SampleSpots.all) { spot in
            SpotCard(spot: spot, showsEnded: true)
        }
    }
}

/// List 행에서 `Spot`을 push 하는 링크. 시스템 disclosure 화살표(›) 없이 카드만 보이게 한다.
public struct SpotRowLink<Content: View>: View {
    let spot: Spot
    let content: Content

    public init(spot: Spot, @ViewBuilder content: () -> Content) {
        self.spot = spot
        self.content = content()
    }

    public var body: some View {
        ZStack {
            NavigationLink(value: spot) { EmptyView() }
                .opacity(0)
            content
        }
    }
}
