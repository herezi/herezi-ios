import Domain
import Foundation
import Testing

struct SpotClustererTests {
    /// 테스트용 투영: 경도·위도 0.001도 = 10pt (화면 y는 위도가 클수록 위).
    private func project(_ coordinate: Coordinate) -> ScreenPoint {
        ScreenPoint(x: coordinate.longitude * 10_000, y: -coordinate.latitude * 10_000)
    }

    private func spot(_ id: String, lat: Double, lng: Double) -> Spot {
        Spot(
            id: id, title: id, category: .festival, coordinate: Coordinate(latitude: lat, longitude: lng),
            startsAt: TestData.now, source: "test", fetchedAt: TestData.now)
    }

    @Test func 반경_48pt_안의_핀은_하나로_묶인다() {
        let spots = [
            spot("a", lat: 37.5, lng: 127.0),
            spot("b", lat: 37.5, lng: 127.004),  // 40pt
            spot("c", lat: 37.5, lng: 127.010),  // 100pt — 따로
        ]
        let clusters = SpotClusterer.cluster(spots, project: project)
        #expect(clusters.count == 2)
        #expect(clusters[0].spots.map(\.id) == ["a", "b"])
        #expect(clusters[1].isSingle && clusters[1].spots[0].id == "c")
    }

    @Test func 경계값_48pt는_묶고_넘으면_따로() {
        let joined = SpotClusterer.cluster(
            [spot("a", lat: 37.5, lng: 127.0), spot("b", lat: 37.5, lng: 127.0048)], project: project)
        #expect(joined.count == 1)
        let apart = SpotClusterer.cluster(
            [spot("a", lat: 37.5, lng: 127.0), spot("b", lat: 37.5, lng: 127.0049)], project: project)
        #expect(apart.count == 2)
    }

    @Test func 선택된_핀은_묶지_않는다() {
        let spots = [spot("a", lat: 37.5, lng: 127.0), spot("b", lat: 37.5, lng: 127.001)]
        let clusters = SpotClusterer.cluster(spots, excluding: ["b"], project: project)
        #expect(clusters.count == 2)
        #expect(clusters.allSatisfy { $0.isSingle })
    }

    @Test func 클러스터_중심_영역_크기_숫자() {
        let spots = (0..<120).map { spot("s\($0)", lat: 37.5 + Double($0) * 0.00001, lng: 127.0) }
        let clusters = SpotClusterer.cluster(spots, project: project)
        #expect(clusters.count == 1)
        let cluster = clusters[0]
        #expect(cluster.countLabel == "99+")
        #expect(cluster.diameter == 48)
        #expect(cluster.bounds.southWest.latitude == 37.5)
        #expect(abs(cluster.bounds.northEast.latitude - 37.50119) < 1e-9)
        #expect(cluster.bounds.contains(cluster.center))

        #expect(SpotCluster(spots: Array(spots.prefix(9))).diameter == 32)
        #expect(SpotCluster(spots: Array(spots.prefix(10))).diameter == 40)
        #expect(SpotCluster(spots: Array(spots.prefix(50))).diameter == 48)
        #expect(SpotCluster(spots: Array(spots.prefix(12))).countLabel == "12")
    }

    @Test func 결과는_입력_순서에_따라_결정적이다() {
        let spots = TestData.listedSpots
        let first = SpotClusterer.cluster(spots, radius: 30, project: project)
        let second = SpotClusterer.cluster(spots, radius: 30, project: project)
        #expect(first == second)
        #expect(first.flatMap(\.spots).count == spots.count)
    }

    @Test func 반경_영역() {
        let bounds = CoordinateBounds.around(.seoulCityHall, radiusMeters: 3_000)
        #expect(bounds.contains(.seoulCityHall))
        let north = Coordinate(latitude: bounds.northEast.latitude, longitude: Coordinate.seoulCityHall.longitude)
        #expect(abs(Coordinate.seoulCityHall.distance(to: north) - 3_000) < 30)
    }
}
