import Domain
import Foundation
import Testing

struct DistanceFormattingTests {
    static let cases: [(Int, String)] = [
        (0, "0m"), (344, "340m"), (346, "350m"), (994, "990m"), (996, "1.0km"), (1_234, "1.2km"),
        (9_940, "9.9km"), (9_960, "10km"), (12_345, "12km"),
    ]

    @Test(arguments: cases)
    func 거리는_10m_단위와_km로_보여준다(meters: Int, expected: String) {
        #expect(SpotFormatting.distance(meters: meters) == expected)
    }

    @Test func 거리를_읽어준다() {
        #expect(SpotFormatting.spokenDistance(meters: 350) == "350미터")
        #expect(SpotFormatting.spokenDistance(meters: 1_200) == "1.2킬로미터")
        #expect(SpotFormatting.spokenDistance(meters: nil) == nil)
    }
}

struct CardPeriodTests {
    /// 2026-11-20 12:00 KST (금)
    private let now = kst(2026, 11, 20, 12)

    @Test func 여러_날은_월일과_요일로() {
        let period = SpotFormatting.cardPeriod(start: kst(2026, 11, 20), end: kst(2026, 12, 14), now: now)
        #expect(period.text == "11.20(금) – 12.14(월)")
        #expect(period.emphasized == false)
    }

    @Test func 진행_중이고_오늘_끝나면_오늘까지() {
        let period = SpotFormatting.cardPeriod(start: kst(2026, 11, 10), end: kst(2026, 11, 20, 22), now: now)
        #expect(period.text == "오늘까지")
        #expect(period.emphasized)
    }

    @Test func 오늘_하루면_시각을_보여준다() {
        let period = SpotFormatting.cardPeriod(start: kst(2026, 11, 20, 18), end: kst(2026, 11, 20, 22), now: now)
        #expect(period.text == "오늘 18:00 – 22:00")
    }

    @Test func 끝이_없으면_부터() {
        #expect(SpotFormatting.cardPeriod(start: kst(2026, 11, 20), end: nil, now: now).text == "11.20(금)부터")
    }

    @Test func 해가_다르면_연도까지() {
        let period = SpotFormatting.cardPeriod(start: kst(2026, 12, 20), end: kst(2027, 1, 4), now: now)
        #expect(period.text == "2026.12.20 – 2027.01.04")
    }

    @Test func 기간을_읽어준다() {
        #expect(
            SpotFormatting.spokenPeriod(start: kst(2026, 11, 20), end: kst(2026, 12, 14)) == "11월 20일부터 12월 14일까지")
    }
}

/// 서울 시각으로 날짜를 만든다.
func kst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}
