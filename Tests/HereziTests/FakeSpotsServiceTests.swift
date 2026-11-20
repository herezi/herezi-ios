import Domain
import Foundation
import Testing

struct FakeSpotsServiceTests {
    private let service = FakeSpotsService(spots: TestData.spots)
    /// 서울시청 주변 샘플이 모두 들어가는 영역.
    private let downtown = CoordinateBounds(
        southWest: Coordinate(latitude: 37.55, longitude: 126.96),
        northEast: Coordinate(latitude: 37.59, longitude: 127.0))

    @Test func 끝난_항목은_목록에_나오지_않는다() async throws {
        let page = try await service.spots(SpotQuery(coordinate: .seoulCityHall))
        #expect(!page.items.contains { $0.id == SampleSpots.endedID })
        #expect(page.items.allSatisfy { !$0.isEnded })
    }

    @Test func 끝난_항목은_상세로만_열린다() async throws {
        let spot = try await service.spot(id: SampleSpots.endedID)
        #expect(spot.isEnded)
        let map = try await service.spotsInBounds(SpotMapQuery(bounds: downtown))
        #expect(!map.items.contains { $0.id == SampleSpots.endedID })
    }

    @Test func 지도는_영역_안의_항목만_중심에서_가까운_순으로_준다() async throws {
        let map = try await service.spotsInBounds(SpotMapQuery(bounds: downtown))
        #expect(Set(map.items.map(\.id)) == Set(TestData.listedSpots.map(\.id)))
        #expect(map.truncated == false)

        // 을지로(126.991)를 빼는 좁은 영역
        let west = CoordinateBounds(
            southWest: Coordinate(latitude: 37.56, longitude: 126.97),
            northEast: Coordinate(latitude: 37.575, longitude: 126.985))
        let narrowed = try await service.spotsInBounds(SpotMapQuery(bounds: west))
        #expect(narrowed.items.map(\.id) == ["sample-1", "sample-2", "sample-4"])
    }

    @Test func 지도는_limit을_넘으면_truncated를_켠다() async throws {
        let map = try await service.spotsInBounds(SpotMapQuery(bounds: downtown, limit: 2))
        #expect(map.items.count == 2)
        #expect(map.truncated)
    }

    @Test func 지도도_카테고리와_무료_필터를_적용한다() async throws {
        let map = try await service.spotsInBounds(SpotMapQuery(bounds: downtown, freeOnly: true))
        #expect(Set(map.items.map(\.id)) == ["sample-1", "sample-4"])
        let festivals = try await service.spotsInBounds(SpotMapQuery(bounds: downtown, categories: [.festival]))
        #expect(festivals.items.map(\.id) == ["sample-1"])
    }
}

struct RelativeTimeTests {
    private let now = TestData.now

    static let cases: [(TimeInterval, String)] = [
        (0, "방금"), (59, "방금"), (60, "1분 전"), (59 * 60, "59분 전"), (3_600, "1시간 전"),
        (23 * 3_600, "23시간 전"), (86_400, "1일 전"), (29 * 86_400, "29일 전"), (-120, "방금"),
    ]

    @Test(arguments: cases)
    func 갱신_시각을_상대_시간으로_보여준다(secondsAgo: Double, expected: String) {
        #expect(SpotFormatting.relativeTime(now.addingTimeInterval(-secondsAgo), now: now) == expected)
    }

    @Test func 한_달이_넘으면_날짜로_보여준다() {
        // TestData.now = 2026-11-18T11:06:40Z → 40일 전 = 2026-10-09 (서울)
        #expect(SpotFormatting.relativeTime(now.addingTimeInterval(-40 * 86_400), now: now) == "10.09")
    }
}
