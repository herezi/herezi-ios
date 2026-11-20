import Domain
import Foundation
import Testing

/// 홈 섹션 규칙 (S1-home.md). 기준: 2026-11-20(금) 12:00 KST.
struct HomeFeedTests {
    private let now = kst(2026, 11, 20, 12)

    private func spot(
        _ id: String, _ category: SpotCategory = .exhibition, start: Date, end: Date?, free: Bool? = nil,
        distance: Int
    ) -> Spot {
        Spot(
            id: id, title: id, category: category, coordinate: .seoulCityHall, startsAt: start, endsAt: end,
            isFree: free, source: "test", fetchedAt: now, distanceMeters: distance)
    }

    /// 진행 중, 다음 주까지.
    private func ongoing(_ id: String, _ category: SpotCategory = .exhibition, free: Bool? = nil, distance: Int)
        -> Spot
    {
        spot(id, category, start: kst(2026, 11, 1), end: kst(2026, 11, 30), free: free, distance: distance)
    }

    @Test func 히어로는_진행_중_가장_가까운_것() {
        let feed = HomeFeed.build(
            spots: [ongoing("far", distance: 900), ongoing("near", distance: 100)], now: now)
        #expect(feed.hero?.spot.id == "near")
        #expect(feed.hero?.title == "지금 가장 가까운 곳")
        #expect(feed.hero?.listFilter == HomeListFilter(when: .now))
        #expect(feed.ongoingCount == 2)
    }

    @Test func 진행_중이_없으면_오늘_시작_예정_중_가장_가까운_것() {
        let laterToday = spot("tonight", start: kst(2026, 11, 20, 18), end: kst(2026, 11, 20, 22), distance: 500)
        let tomorrow = spot("tomorrow", start: kst(2026, 11, 21, 10), end: kst(2026, 11, 21, 18), distance: 50)
        let feed = HomeFeed.build(spots: [tomorrow, laterToday], now: now)
        #expect(feed.hero?.spot.id == "tonight")
        #expect(feed.hero?.title == "오늘 가장 가까운 곳")
        #expect(feed.hero?.listFilter == HomeListFilter(when: .today))
        #expect(feed.headline(usesFallbackLocation: false) == ("이번 주 근처에", "볼거리 2개 있어요"))
    }

    @Test func 오늘_끝남은_오늘_23시59분까지_끝나는_진행_중_항목만_빨리_끝나는_순() {
        let spots = [
            ongoing("hero", distance: 1),
            spot("e22", start: kst(2026, 11, 19), end: kst(2026, 11, 20, 22), distance: 300),
            spot("e18", start: kst(2026, 11, 19), end: kst(2026, 11, 20, 18), distance: 900),
            spot("e2359", start: kst(2026, 11, 19), end: kst(2026, 11, 20, 23, 59), distance: 100),
            // 경계: 내일 00:00에 끝나면 오늘 끝남이 아니다.
            spot("midnight", start: kst(2026, 11, 19), end: kst(2026, 11, 21), distance: 50),
            // 이미 끝난 것(now 이전)은 진행 중이 아니다.
            spot("past", start: kst(2026, 11, 19), end: kst(2026, 11, 20, 11), distance: 10),
        ]
        let feed = HomeFeed.build(spots: spots, now: now)
        let section = feed.sections.first { $0.kind == .endingToday }
        #expect(section?.items.map(\.id) == ["e18", "e22", "e2359"])
        #expect(HomeClock(now: now).endsTodayText(kst(2026, 11, 20, 23, 59)) == "오늘까지")
        #expect(HomeClock(now: now).endsTodayText(kst(2026, 11, 20, 18)) == "오늘 18:00까지")
    }

    @Test func 최소_3개_미만이면_섹션을_숨긴다() {
        let spots = [
            ongoing("hero", distance: 1),
            ongoing("f1", free: true, distance: 10),
            ongoing("f2", free: true, distance: 20),
        ]
        let feed = HomeFeed.build(spots: spots, now: now)
        #expect(!feed.sections.contains { $0.kind == .free })
    }

    @Test func 히어로는_다른_섹션에_넣지_않는다() {
        let spots = [
            ongoing("hero", .nature, free: true, distance: 1),
            ongoing("n1", .nature, distance: 10), ongoing("n2", .nature, distance: 20),
            ongoing("n3", .nature, distance: 30),
        ]
        let feed = HomeFeed.build(spots: spots, now: now)
        #expect(feed.hero?.spot.id == "hero")
        let seasonal = feed.sections.first { $0.kind == .seasonal }
        #expect(seasonal?.items.map(\.id) == ["n1", "n2", "n3"])
        #expect(seasonal?.kind.listFilter == HomeListFilter(when: .week, categories: [.nature]))
    }

    @Test func 앞_섹션에_나온_항목은_뒤로_미루고_최대_10개() {
        // 무료 자연 3개 + 무료만 2개 + 자연만 2개(다음 주 월–수, 주말과 안 겹침) + 주말 항목 12개.
        // 무료 섹션 다음 계절 섹션은 안 나온 자연을 앞에, 이미 나온 것을 뒤에.
        func nextWeek(_ id: String, _ category: SpotCategory, free: Bool?, distance: Int) -> Spot {
            spot(id, category, start: kst(2026, 11, 23), end: kst(2026, 11, 25), free: free, distance: distance)
        }
        var spots = [ongoing("hero", distance: 1)]
        spots += (1...3).map { nextWeek("fn\($0)", .nature, free: true, distance: $0 * 10) }
        spots += (1...2).map { nextWeek("f\($0)", .exhibition, free: true, distance: 100 + $0) }
        spots += (1...2).map { nextWeek("n\($0)", .nature, free: nil, distance: 200 + $0) }
        spots += (1...12).map { ongoing("w\($0)", distance: 300 + $0) }
        let feed = HomeFeed.build(spots: spots, now: now)

        let free = feed.sections.first { $0.kind == .free }
        #expect(free?.items.map(\.id) == ["fn1", "fn2", "fn3", "f1", "f2"])
        let seasonal = feed.sections.first { $0.kind == .seasonal }
        #expect(seasonal?.items.map(\.id) == ["n1", "n2", "fn1", "fn2", "fn3"])
        // 주말 섹션(모두 주말과 겹침)은 최대 10개.
        let weekend = feed.sections.first { $0.kind == .weekend }
        #expect(weekend?.items.count == 10)
        // 섹션 순서는 고정.
        #expect(feed.sections.map(\.kind) == [.weekend, .free, .seasonal])
    }

    @Test func 주말_창은_다가오는_토일과_겹치는_항목() {
        let clock = HomeClock(now: now)
        #expect(clock.weekend.lowerBound == kst(2026, 11, 21))
        #expect(clock.weekend.upperBound == kst(2026, 11, 22, 23, 59, 59))
        let fridayOnly = spot("fri", start: kst(2026, 11, 20, 13), end: kst(2026, 11, 20, 23), distance: 1)
        let sundayOnly = spot("sun", start: kst(2026, 11, 22, 10), end: kst(2026, 11, 22, 12), distance: 1)
        let nextMonday = spot("mon", start: kst(2026, 11, 23), end: kst(2026, 11, 24), distance: 1)
        let noEnd = spot("open", start: kst(2026, 11, 1), end: nil, distance: 1)
        #expect(!clock.overlapsWeekend(fridayOnly))
        #expect(clock.overlapsWeekend(sundayOnly))
        #expect(!clock.overlapsWeekend(nextMonday))
        #expect(clock.overlapsWeekend(noEnd))
    }

    @Test func 토요일이면_주말_창은_지금부터_일요일까지() {
        let saturdayNoon = kst(2026, 11, 21, 12)
        let clock = HomeClock(now: saturdayNoon)
        #expect(clock.weekend.lowerBound == saturdayNoon)
        #expect(clock.weekend.upperBound == kst(2026, 11, 22, 23, 59, 59))
        let sunday = HomeClock(now: kst(2026, 11, 22, 9))
        #expect(sunday.weekend.upperBound == kst(2026, 11, 22, 23, 59, 59))
    }

    @Test func 헤드라인은_진행_중_개수와_이상과_서울시청() {
        let feed = HomeFeed.build(
            spots: [ongoing("a", distance: 1), ongoing("b", distance: 2)], now: now, hasMore: true)
        #expect(feed.headline(usesFallbackLocation: false) == ("지금 근처에", "볼거리 2개 이상 있어요"))
        #expect(feed.headline(usesFallbackLocation: true) == ("서울시청 주변에", "볼거리 2개 이상 있어요"))
        #expect(HomeFeed.build(spots: [], now: now).isEmpty)
    }

    @Test func 히어로_배지와_메타() {
        let clock = HomeClock(now: now)
        let later = spot("l", start: kst(2026, 11, 20, 17), end: kst(2026, 11, 20, 22), distance: 350)
        #expect(clock.heroBadge(later) == "오늘 17:00 시작")
        let multi = spot("m", .festival, start: kst(2026, 11, 18), end: kst(2026, 12, 14), free: true, distance: 350)
        #expect(clock.heroBadge(multi) == "지금 진행 중")
        #expect(clock.heroMeta(multi) == "축제·행사 · 350m · 12.14(월)까지 · 무료")
    }
}
