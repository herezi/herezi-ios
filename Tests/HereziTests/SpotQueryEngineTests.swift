import Domain
import Foundation
import Testing

private func spot(
    _ id: String, at coordinate: Coordinate = .seoulCityHall, category: SpotCategory = .festival,
    starts: Date, ends: Date?, free: Bool? = nil, title: String? = nil, place: String? = nil, address: String? = nil,
    serverEnded: Bool = false
) -> Spot {
    Spot(
        id: id, title: title ?? id, category: category, coordinate: coordinate, address: address, placeName: place,
        startsAt: starts, endsAt: ends, isFree: free, source: "test", fetchedAt: starts, isEnded: serverEnded)
}

/// herezi-api `internal/domain/when.go` + `domain_test.go`(TestWhenWindow)와 같은 경계를 검사한다.
struct WhenWindowTests {
    // 2026-11-18 수요일 15:00 KST (서버 테스트와 같은 기준).
    let wednesday = kst(2026, 11, 18, 15)

    @Test func now는_한_순간이다() {
        let window = WhenFilter.now.window(now: wednesday)
        #expect(window.from == wednesday && window.to == wednesday)
    }

    @Test func today는_지금부터_오늘_23시59분59초_KST까지() {
        let window = WhenFilter.today.window(now: wednesday)
        #expect(window.from == wednesday)
        #expect(window.to == kst(2026, 11, 18, 23, 59, 59))
    }

    @Test func today는_UTC가_아니라_KST_날짜로_자른다() {
        // KST 00:30 = UTC 전날 15:30. 오늘은 KST 19일.
        let earlyMorning = kst(2026, 11, 19, 0, 30)
        #expect(WhenFilter.today.window(now: earlyMorning).to == kst(2026, 11, 19, 23, 59, 59))
    }

    @Test func 평일의_weekend는_토요일_0시부터_일요일_끝까지() {
        let window = WhenFilter.weekend.window(now: wednesday)
        #expect(window.from == kst(2026, 11, 21))
        #expect(window.to == kst(2026, 11, 22, 23, 59, 59))
    }

    @Test func 토요일의_weekend는_지금부터_일요일_끝까지() {
        let saturday = kst(2026, 11, 21, 10)
        let window = WhenFilter.weekend.window(now: saturday)
        #expect(window.from == saturday)
        #expect(window.to == kst(2026, 11, 22, 23, 59, 59))
    }

    @Test func 일요일의_weekend는_지금부터_오늘_밤까지() {
        // 서버 테스트: "Sunday: weekend starts now, ends tonight."
        let sunday = kst(2026, 11, 22, 10)
        let window = WhenFilter.weekend.window(now: sunday)
        #expect(window.from == sunday)
        #expect(window.to == kst(2026, 11, 22, 23, 59, 59))
    }

    @Test func 금요일_밤_KST는_UTC로는_금요일이어도_다음날이_토요일() {
        let fridayNight = kst(2026, 11, 20, 23, 30)  // = 2026-11-20 14:30 UTC
        let window = WhenFilter.weekend.window(now: fridayNight)
        #expect(window.from == kst(2026, 11, 21))
        #expect(window.to == kst(2026, 11, 22, 23, 59, 59))
    }

    @Test func 토요일_새벽_KST는_UTC로는_금요일이어도_토요일로_본다() {
        let saturdayDawn = kst(2026, 11, 21, 1)  // = 2026-11-20 16:00 UTC (금요일)
        let window = WhenFilter.weekend.window(now: saturdayDawn)
        #expect(window.from == saturdayDawn)
        #expect(window.to == kst(2026, 11, 22, 23, 59, 59))
    }

    @Test func week는_지금부터_7일_뒤까지() {
        let window = WhenFilter.week.window(now: wednesday)
        #expect(window.from == wednesday)
        #expect(window.to == kst(2026, 11, 25, 15))
    }
}

/// 서버 `Spot.Overlaps`·`Spot.Ended`·`Spot.MatchesKeyword`(domain_test.go)와 같은 의미.
struct SpotRuleTests {
    let now = kst(2026, 11, 18, 15)

    @Test func 끝난_항목은_now와_겹치지_않고_진행_중은_겹친다() {
        let finished = spot("a", starts: now.addingTimeInterval(-7_200), ends: now.addingTimeInterval(-3_600))
        let ongoing = spot("b", starts: now.addingTimeInterval(-3_600), ends: now.addingTimeInterval(3_600))
        let window = WhenFilter.now.window(now: now)
        #expect(!finished.overlaps(from: window.from, to: window.to))
        #expect(ongoing.overlaps(from: window.from, to: window.to))
    }

    @Test func 종료가_없으면_시작_한_순간짜리로_본다() {
        let past = spot("a", starts: now.addingTimeInterval(-60), ends: nil)
        let inWeek = spot("b", starts: now.addingTimeInterval(86_400), ends: nil)
        let window = WhenFilter.week.window(now: now)
        #expect(!past.overlaps(from: window.from, to: window.to))
        #expect(inWeek.overlaps(from: window.from, to: window.to))
    }

    @Test func 경계는_포함한다() {
        let window = WhenFilter.today.window(now: now)
        let startsAtEnd = spot("a", starts: window.to, ends: window.to.addingTimeInterval(3_600))
        let endsAtStart = spot("b", starts: now.addingTimeInterval(-3_600), ends: window.from)
        let startsAfter = spot("c", starts: window.to.addingTimeInterval(1), ends: nil)
        #expect(startsAtEnd.overlaps(from: window.from, to: window.to))
        #expect(endsAtStart.overlaps(from: window.from, to: window.to))
        #expect(!startsAfter.overlaps(from: window.from, to: window.to))
    }

    @Test func 끝남은_ends_at이_now보다_앞설_때만() {
        #expect(spot("a", starts: now, ends: now.addingTimeInterval(-1)).hasEnded(at: now))
        #expect(!spot("b", starts: now, ends: now.addingTimeInterval(1)).hasEnded(at: now))
        #expect(!spot("c", starts: now, ends: now).hasEnded(at: now))
        #expect(!spot("d", starts: now, ends: nil).hasEnded(at: now))
    }

    @Test func 키워드는_제목_장소_주소에_대소문자_무시_부분_일치() {
        let item = spot(
            "x", starts: now, ends: nil, title: "Seoul Lantern 빛초롱", place: "청계천", address: "서울 중구 50%_로")
        let cases: [(String, Bool)] = [
            ("", true), ("lantern", true), ("LANTERN", true), ("빛초롱", true), ("청계", true), ("중구", true),
            ("%_", true), ("성수", false), ("lanterns", false),
        ]
        for (keyword, want) in cases {
            #expect(item.matchesKeyword(keyword) == want, "\(keyword)")
        }
    }

    @Test func 하버사인_거리는_시청에서_광화문_약_1km() {
        let gwanghwamun = Coordinate(latitude: 37.5759, longitude: 126.9768)
        let distance = SpotQueryEngine.distanceMeters(.seoulCityHall, gwanghwamun)
        #expect(abs(distance - 1_070) < 200)
        #expect(SpotQueryEngine.distanceMeters(.seoulCityHall, .seoulCityHall) == 0)
    }
}

struct SpotQueryEngineTests {
    let now = kst(2026, 11, 18, 15)
    let hour: TimeInterval = 3_600

    /// 시청 기준 북쪽으로 대략 `meters`만큼 떨어진 좌표.
    func north(_ meters: Double) -> Coordinate {
        Coordinate(latitude: Coordinate.seoulCityHall.latitude + meters / 111_195, longitude: 126.9779)
    }

    var data: [Spot] {
        [
            spot("near", at: north(100), starts: now - hour, ends: now + hour, free: true),
            spot("mid", at: north(1_000), category: .exhibition, starts: now - hour, ends: now + 30 * hour),
            spot("far", at: north(5_000), starts: now - hour, ends: now + hour),
            spot("ended", at: north(50), starts: now - 3 * hour, ends: now - hour, free: true),
            // 서버 generated_at 기준으로는 끝났다고 왔지만 기기 시각으로는 진행 중.
            spot("stale-flag", at: north(300), starts: now - hour, ends: now + hour, serverEnded: true),
            spot("tomorrow", at: north(200), starts: now + 20 * hour, ends: now + 22 * hour, free: false),
            spot("tie-b", at: north(500), starts: now - hour, ends: now + hour, title: "빛초롱 B"),
            spot("tie-a", at: north(500), starts: now - hour, ends: now + hour, place: "청계광장 빛초롱"),
        ]
    }

    @Test func 근처는_반경_안_끝나지_않은_것을_거리순_같으면_id순으로() {
        let page = SpotQueryEngine.nearby(data, query: SpotQuery(coordinate: .seoulCityHall), now: now)
        #expect(page.items.map(\.id) == ["near", "stale-flag", "tie-a", "tie-b", "mid"])
        #expect(page.items.allSatisfy { !$0.isEnded })
        #expect(page.items.first?.distanceMeters == 100)
        #expect(page.nextCursor == nil)
    }

    @Test func 근처는_기간_카테고리_무료로_거른다() {
        let week = SpotQueryEngine.nearby(data, query: SpotQuery(coordinate: .seoulCityHall, when: .week), now: now)
        #expect(week.items.map(\.id).contains("tomorrow"))
        let exhibitions = SpotQueryEngine.nearby(
            data, query: SpotQuery(coordinate: .seoulCityHall, categories: [.exhibition]), now: now)
        #expect(exhibitions.items.map(\.id) == ["mid"])
        let free = SpotQueryEngine.nearby(
            data, query: SpotQuery(coordinate: .seoulCityHall, when: .week, freeOnly: true), now: now)
        #expect(free.items.map(\.id) == ["near"])  // 무료 모름(nil)·false는 빠진다, 끝난 무료 항목도 빠진다
    }

    @Test func 근처는_반경을_넓히면_먼_항목도_넣는다() {
        let page = SpotQueryEngine.nearby(
            data, query: SpotQuery(coordinate: .seoulCityHall, radiusMeters: 20_000), now: now)
        #expect(page.items.last?.id == "far")
    }

    @Test func 키워드는_공백을_자르고_대소문자를_무시한다() {
        let page = SpotQueryEngine.nearby(
            data, query: SpotQuery(coordinate: .seoulCityHall, keyword: "  빛초롱 "), now: now)
        #expect(page.items.map(\.id) == ["tie-a", "tie-b"])
        let blank = SpotQueryEngine.nearby(data, query: SpotQuery(coordinate: .seoulCityHall, keyword: "  "), now: now)
        #expect(blank.items.count == 5)
    }

    @Test func 커서로_다음_페이지를_이어_받는다() {
        let first = SpotQueryEngine.nearby(data, query: SpotQuery(coordinate: .seoulCityHall, limit: 2), now: now)
        #expect(first.items.map(\.id) == ["near", "stale-flag"])
        #expect(first.nextCursor == "2")
        let second = SpotQueryEngine.nearby(
            data, query: SpotQuery(coordinate: .seoulCityHall, cursor: first.nextCursor, limit: 2), now: now)
        #expect(second.items.map(\.id) == ["tie-a", "tie-b"])
        let third = SpotQueryEngine.nearby(
            data, query: SpotQuery(coordinate: .seoulCityHall, cursor: second.nextCursor, limit: 2), now: now)
        #expect(third.items.map(\.id) == ["mid"])
        #expect(third.nextCursor == nil)
    }

    @Test func 지도는_영역_안을_중심에서_가까운_순으로_최대_limit개() {
        let bounds = CoordinateBounds.around(.seoulCityHall, radiusMeters: 1_200)
        let map = SpotQueryEngine.inBounds(data, query: SpotMapQuery(bounds: bounds), now: now)
        #expect(map.items.map(\.id) == ["near", "stale-flag", "tie-a", "tie-b", "mid"])
        #expect(!map.truncated)
        #expect(map.items.allSatisfy { $0.distanceMeters == nil && !$0.isEnded })
        let limited = SpotQueryEngine.inBounds(data, query: SpotMapQuery(bounds: bounds, limit: 2), now: now)
        #expect(limited.items.map(\.id) == ["near", "stale-flag"])
        #expect(limited.truncated)
    }

    @Test func 지도_영역_모서리는_포함한다() {
        let corner = north(100).latitude
        let bounds = CoordinateBounds(
            southWest: Coordinate(latitude: corner, longitude: 126.9779),
            northEast: Coordinate(latitude: corner + 0.01, longitude: 126.98))
        let map = SpotQueryEngine.inBounds(data, query: SpotMapQuery(bounds: bounds), now: now)
        #expect(map.items.map(\.id).contains("near"))
    }

    /// 실데이터 규모(서울 약 2,700건)에서 기기 계산이 충분히 빠른지. 숫자는 `make test` 로그에 남긴다.
    @Test func 실데이터_규모에서_조회가_빠르다() {
        var many: [Spot] = []
        for index in 0..<2_700 {
            let lat = 37.42 + Double(index % 60) * 0.005
            let lng = 126.74 + Double(index / 60) * 0.011
            many.append(
                spot(
                    "s\(index)", at: Coordinate(latitude: lat, longitude: lng),
                    category: SpotCategory.allCases[index % SpotCategory.allCases.count],
                    starts: now - Double(index % 48) * hour, ends: now + Double(index % 300) * hour - 24 * hour,
                    free: index.isMultiple(of: 3), title: "볼거리 \(index) Festival", place: "장소 \(index)",
                    address: "서울 어딘가로 \(index)"))
        }
        let clock = ContinuousClock()
        var home = SpotPage(items: [])
        let homeTime = clock.measure {
            home = SpotQueryEngine.nearby(
                many, query: SpotQuery(coordinate: .seoulCityHall, when: .week, limit: 100), now: now)
        }
        let searchTime = clock.measure {
            _ = SpotQueryEngine.nearby(
                many, query: SpotQuery(coordinate: .seoulCityHall, radiusMeters: 20_000, keyword: "festival"),
                now: now)
        }
        let mapTime = clock.measure {
            _ = SpotQueryEngine.inBounds(
                many, query: SpotMapQuery(bounds: .around(.seoulCityHall, radiusMeters: 3_000), when: .week),
                now: now)
        }
        print("perf: 2,700건 홈 \(homeTime), 검색 \(searchTime), 지도 \(mapTime)")
        #expect(!home.items.isEmpty)
        #expect(homeTime < .milliseconds(500) && searchTime < .milliseconds(500) && mapTime < .milliseconds(500))
    }
}
