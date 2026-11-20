import Foundation

/// 화면 좌표(pt). 지도 SDK의 투영 결과를 Domain으로 옮길 때 쓴다.
public struct ScreenPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distanceSquared(to other: ScreenPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

/// 지도에 그릴 묶음 하나. 항목이 1개면 핀, 2개 이상이면 클러스터 (DESIGN §6.6).
public struct SpotCluster: Hashable, Sendable, Identifiable {
    public let spots: [Spot]
    /// 묶인 항목 좌표의 평균 — 클러스터 마커 위치.
    public let center: Coordinate
    /// 묶인 항목을 모두 포함하는 영역 — 클러스터를 탭하면 여기로 확대한다.
    public let bounds: CoordinateBounds

    public var id: String { spots.map(\.id).joined(separator: "|") }
    public var isSingle: Bool { spots.count == 1 }

    /// 클러스터 숫자: 99개 넘으면 "99+".
    public var countLabel: String { spots.count > 99 ? "99+" : String(spots.count) }

    /// 지름: 2–9개 32, 10–49개 40, 50개 이상 48.
    public var diameter: Double {
        switch spots.count {
        case ..<10: 32
        case ..<50: 40
        default: 48
        }
    }

    public init(spots: [Spot]) {
        precondition(!spots.isEmpty, "SpotCluster needs at least one spot")
        self.spots = spots
        let lats = spots.map(\.coordinate.latitude)
        let lngs = spots.map(\.coordinate.longitude)
        center = Coordinate(
            latitude: lats.reduce(0, +) / Double(lats.count), longitude: lngs.reduce(0, +) / Double(lngs.count))
        bounds = CoordinateBounds(
            southWest: Coordinate(latitude: lats.min()!, longitude: lngs.min()!),
            northEast: Coordinate(latitude: lats.max()!, longitude: lngs.max()!))
    }
}

/// 앱 쪽 클러스터링 (서버는 bbox 항목만 준다). 같은 화면에서 반경 `radius`pt 안의 핀을 묶는다.
///
/// 탐욕적 거리 기반: 입력 순서(서버가 준 "영역 중심에서 가까운 순")대로 아직 안 묶인 항목을 씨앗으로 삼고,
/// 씨앗에서 반경 안에 있는 나머지 안 묶인 항목을 모두 붙인다. 같은 입력이면 항상 같은 결과다.
/// `excluding`에 든 id(선택된 핀)는 묶지 않고 항상 단독 핀으로 둔다.
public enum SpotClusterer {
    public static let defaultRadius: Double = 48

    public static func cluster(
        _ spots: [Spot], radius: Double = defaultRadius, excluding pinned: Set<String> = [],
        project: (Coordinate) -> ScreenPoint
    ) -> [SpotCluster] {
        let points = spots.map { project($0.coordinate) }
        let radiusSquared = radius * radius
        var used = [Bool](repeating: false, count: spots.count)
        var result: [SpotCluster] = []
        for (index, spot) in spots.enumerated() where pinned.contains(spot.id) {
            used[index] = true
            result.append(SpotCluster(spots: [spot]))
        }
        for seed in spots.indices where !used[seed] {
            used[seed] = true
            var members = [spots[seed]]
            for other in spots.indices where !used[other] {
                if points[seed].distanceSquared(to: points[other]) <= radiusSquared {
                    used[other] = true
                    members.append(spots[other])
                }
            }
            result.append(SpotCluster(spots: members))
        }
        return result
    }
}

extension CoordinateBounds {
    /// 중심에서 반경(미터)만큼의 사각 영역. 지도가 아직 영역을 알려주지 않았을 때 첫 조회에 쓴다.
    public static func around(_ center: Coordinate, radiusMeters: Double) -> CoordinateBounds {
        let dLat = radiusMeters / 111_320
        let dLng = radiusMeters / (111_320 * max(0.01, cos(center.latitude * .pi / 180)))
        return CoordinateBounds(
            southWest: Coordinate(latitude: center.latitude - dLat, longitude: center.longitude - dLng),
            northEast: Coordinate(latitude: center.latitude + dLat, longitude: center.longitude + dLng))
    }
}

/// 화면이 지도에 요청하는 카메라 이동. `id`가 바뀔 때만 지도가 움직인다(같은 위치로 다시 이동도 가능).
public struct MapCameraTarget: Hashable, Sendable {
    public let id: UUID
    public let center: Coordinate
    public let zoom: Double

    /// 첫 진입 줌: 반경 3km 정도가 보이는 14 (S2 스펙).
    public static let defaultZoom: Double = 14

    public init(center: Coordinate, zoom: Double = defaultZoom, id: UUID = UUID()) {
        self.id = id
        self.center = center
        self.zoom = zoom
    }
}
