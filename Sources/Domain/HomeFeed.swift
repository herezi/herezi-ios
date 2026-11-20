import Foundation

/// 홈(S1) 피드. `GET /v1/spots?when=week&limit=100` 한 번의 응답을 규칙으로만 나눈다
/// (herezi-api docs/design/screens/S1-home.md "섹션 규칙"). 모든 시각 계산은 KST, 기준 시각 `now` 하나.
public struct HomeFeed: Equatable, Sendable {
    /// 섹션 0 — 히어로 카드 1장.
    public struct Hero: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// 진행 중 중 가장 가까운 것 — "지금 가장 가까운 곳"
            case nearestNow
            /// 진행 중이 없어 오늘 시작 예정 중 가장 가까운 것 — "오늘 가장 가까운 곳"
            case nearestToday
        }

        public let spot: Spot
        public let kind: Kind

        public var title: String { kind == .nearestNow ? "지금 가장 가까운 곳" : "오늘 가장 가까운 곳" }

        /// "전체 보기" → S1b 시작 필터.
        public var listFilter: HomeListFilter { HomeListFilter(when: kind == .nearestNow ? .now : .today) }
    }

    /// 섹션 1–4 (가로 카드 줄). 순서 고정, 숨김만 있다.
    public enum SectionKind: CaseIterable, Equatable, Sendable {
        case endingToday
        case weekend
        case free
        case seasonal

        public var title: String {
            switch self {
            case .endingToday: "오늘 끝나요"
            case .weekend: "이번 주말 놓치면 아쉬운"
            case .free: "무료로 즐기기"
            case .seasonal: "계절 한정"
            }
        }

        /// "전체 보기" → S1b 시작 필터.
        public var listFilter: HomeListFilter {
            switch self {
            case .endingToday: HomeListFilter(when: .today)
            case .weekend: HomeListFilter(when: .weekend)
            case .free: HomeListFilter(when: .week, freeOnly: true)
            case .seasonal: HomeListFilter(when: .week, categories: [.nature])
            }
        }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let kind: SectionKind
        public let items: [Spot]
        public var id: SectionKind { kind }
    }

    /// 가로 섹션 최소·최대 개수.
    public static let sectionMinimum = 3
    public static let sectionMaximum = 10

    public let hero: Hero?
    public let sections: [Section]
    /// 진행 중 항목 수 (헤드라인 N).
    public let ongoingCount: Int
    /// 받은 항목 수 (이번 주, 헤드라인 M).
    public let totalCount: Int
    /// `next_cursor`가 있었는지 — 헤드라인 "N개 이상".
    public let hasMore: Bool

    /// 이번 주 항목이 하나도 없으면 빈 상태.
    public var isEmpty: Bool { totalCount == 0 }

    /// 헤드라인 2줄. 위치 거부면 "서울시청 주변에".
    public func headline(usesFallbackLocation: Bool) -> (line1: String, line2: String) {
        let ongoing = ongoingCount > 0
        let count = ongoing ? ongoingCount : totalCount
        let line1 = usesFallbackLocation ? "서울시청 주변에" : (ongoing ? "지금 근처에" : "이번 주 근처에")
        return (line1, "볼거리 \(count)개\(hasMore ? " 이상" : "") 있어요")
    }

    // MARK: 만들기

    /// - Parameters:
    ///   - spots: 응답 항목(거리순).
    ///   - now: 응답을 받은 순간의 기기 시각. 모든 섹션에 같이 쓴다.
    ///   - hasMore: 응답에 `next_cursor`가 있었는지.
    public static func build(spots: [Spot], now: Date, hasMore: Bool = false) -> HomeFeed {
        let clock = HomeClock(now: now)
        let byDistance = spots.sorted(by: Self.nearerFirst)

        let ongoing = byDistance.filter { clock.isOngoing($0) }
        let hero: Hero? =
            if let first = ongoing.first {
                Hero(spot: first, kind: .nearestNow)
            } else if let first = byDistance.first(where: { clock.startsLaterToday($0) }) {
                Hero(spot: first, kind: .nearestToday)
            } else {
                nil
            }

        var shown = Set<String>()
        var sections: [Section] = []
        for kind in SectionKind.allCases {
            // 히어로 항목은 다른 섹션에 넣지 않는다. 최소 개수는 미루기 전 후보 수로 판단.
            let candidates = Self.candidates(for: kind, in: byDistance, clock: clock)
                .filter { $0.id != hero?.spot.id }
            guard candidates.count >= sectionMinimum else { continue }
            // 앞 섹션에 이미 나온 항목은 뒤로 미룬다.
            let fresh = candidates.filter { !shown.contains($0.id) }
            let repeated = candidates.filter { shown.contains($0.id) }
            let items = Array((fresh + repeated).prefix(sectionMaximum))
            shown.formUnion(items.map(\.id))
            sections.append(Section(kind: kind, items: items))
        }

        return HomeFeed(
            hero: hero, sections: sections, ongoingCount: ongoing.count, totalCount: spots.count, hasMore: hasMore)
    }

    private static func candidates(for kind: SectionKind, in spots: [Spot], clock: HomeClock) -> [Spot] {
        switch kind {
        case .endingToday:
            spots.filter { clock.endsToday($0) }
                .sorted {
                    ($0.endsAt ?? .distantFuture, $0.distanceMeters ?? .max) < (
                        $1.endsAt ?? .distantFuture, $1.distanceMeters ?? .max
                    )
                }
        case .weekend:
            spots.filter { clock.overlapsWeekend($0) }
        case .free:
            spots.filter { $0.isFree == true }
        case .seasonal:
            spots.filter { $0.category == .nature }
        }
    }

    static func nearerFirst(_ a: Spot, _ b: Spot) -> Bool {
        (a.distanceMeters ?? .max, a.title) < (b.distanceMeters ?? .max, b.title)
    }
}

/// S1b 전체 목록의 시작 필터 (홈의 카테고리·전체 보기에서 넘긴다).
public struct HomeListFilter: Hashable, Sendable {
    public var when: WhenFilter
    public var categories: Set<SpotCategory>
    public var freeOnly: Bool

    public init(when: WhenFilter = .now, categories: Set<SpotCategory> = [], freeOnly: Bool = false) {
        self.when = when
        self.categories = categories
        self.freeOnly = freeOnly
    }
}

/// 홈 섹션 규칙의 시각 정의 (KST).
public struct HomeClock: Sendable {
    public let now: Date
    let calendar: Calendar
    /// 오늘 23:59:59.
    public let endOfToday: Date
    /// 이번 주말 창 (서버 `weekend`와 같다).
    public let weekend: ClosedRange<Date>

    public init(now: Date) {
        self.now = now
        let calendar = SpotFormatting.seoulCalendar
        self.calendar = calendar
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        endOfToday = startOfTomorrow.addingTimeInterval(-1)

        // 일=1 … 토=7. 오늘이 토·일이면 이번 토 00:00–일 23:59:59, 아니면 다가오는 토·일.
        let weekday = calendar.component(.weekday, from: now)
        let daysToSaturday =
            switch weekday {
            case 7: 0
            case 1: -1
            default: 7 - weekday
            }
        let saturday = calendar.date(byAdding: .day, value: daysToSaturday, to: startOfToday)!
        let mondayStart = calendar.date(byAdding: .day, value: 2, to: saturday)!
        let windowStart = max(saturday, now)
        weekend = windowStart...mondayStart.addingTimeInterval(-1)
    }

    /// `starts_at ≤ now < end` (끝이 없으면 무한대).
    public func isOngoing(_ spot: Spot) -> Bool {
        spot.startsAt <= now && now < (spot.endsAt ?? .distantFuture)
    }

    /// `now < starts_at ≤ 오늘 23:59:59`.
    public func startsLaterToday(_ spot: Spot) -> Bool {
        now < spot.startsAt && spot.startsAt <= endOfToday
    }

    /// 진행 중이고 `end ≤ 오늘 23:59:59`.
    public func endsToday(_ spot: Spot) -> Bool {
        guard let end = spot.endsAt else { return false }
        return isOngoing(spot) && end <= endOfToday
    }

    /// 이번 주말 창과 겹치는지.
    public func overlapsWeekend(_ spot: Spot) -> Bool {
        spot.startsAt <= weekend.upperBound && (spot.endsAt ?? .distantFuture) >= weekend.lowerBound
    }

    // MARK: 카드 문구

    /// 히어로 상단 배지: "오늘 17:00 시작" / "오늘 22:00까지"(23:59 끝이면 "오늘까지") / "지금 진행 중".
    public func heroBadge(_ spot: Spot) -> String? {
        if startsLaterToday(spot) { return "오늘 \(SpotFormatting.time(spot.startsAt, calendar: calendar)) 시작" }
        if endsToday(spot), let end = spot.endsAt { return endsTodayText(end) }
        if isOngoing(spot) { return "지금 진행 중" }
        return nil
    }

    /// "오늘 18:00까지" (23:59 끝이면 "오늘까지").
    public func endsTodayText(_ end: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        if parts.hour == 23 && parts.minute == 59 { return "오늘까지" }
        return "오늘 \(SpotFormatting.time(end, calendar: calendar))까지"
    }

    /// 히어로 메타: "축제·행사 · 350m · 12.14(일)까지 · 무료".
    public func heroMeta(_ spot: Spot) -> String {
        var parts = [spot.category.displayName]
        if let distance = SpotFormatting.distance(meters: spot.distanceMeters) { parts.append(distance) }
        parts.append(heroPeriod(spot))
        if spot.isFree == true { parts.append("무료") }
        return parts.joined(separator: " · ")
    }

    /// 진행 중 여러 날이면 "12.14(일)까지", 아니면 카드 기간 규칙.
    func heroPeriod(_ spot: Spot) -> String {
        if isOngoing(spot), let end = spot.endsAt, !calendar.isDate(spot.startsAt, inSameDayAs: end),
            !calendar.isDate(end, inSameDayAs: now)
        {
            return "\(SpotFormatting.dayWithWeekday(end, calendar: calendar))까지"
        }
        return SpotFormatting.cardPeriod(start: spot.startsAt, end: spot.endsAt, now: now).text
    }
}
