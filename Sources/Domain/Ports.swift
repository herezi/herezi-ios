import Foundation

/// Parameters for `GET /v1/spots`.
public struct SpotQuery: Hashable, Sendable {
    public var coordinate: Coordinate
    public var radiusMeters: Int
    /// Empty set means "all categories".
    public var categories: Set<SpotCategory>
    public var when: WhenFilter
    /// `free=true` — 무료 항목만. false면 파라미터를 보내지 않는다.
    public var freeOnly: Bool
    public var cursor: String?
    public var limit: Int

    public init(
        coordinate: Coordinate,
        radiusMeters: Int = 3000,
        categories: Set<SpotCategory> = [],
        when: WhenFilter = .now,
        freeOnly: Bool = false,
        cursor: String? = nil,
        limit: Int = 30
    ) {
        self.coordinate = coordinate
        self.radiusMeters = radiusMeters
        self.categories = categories
        self.when = when
        self.freeOnly = freeOnly
        self.cursor = cursor
        self.limit = limit
    }
}

/// Parameters for `GET /v1/spots/map` (지도 영역 조회). 클러스터링은 앱에서 한다.
public struct SpotMapQuery: Hashable, Sendable {
    public var bounds: CoordinateBounds
    /// Empty set means "all categories".
    public var categories: Set<SpotCategory>
    public var when: WhenFilter
    /// `free=true` — 무료 항목만. false면 파라미터를 보내지 않는다.
    public var freeOnly: Bool
    /// 1...500, 서버 기본 200.
    public var limit: Int

    public init(
        bounds: CoordinateBounds,
        categories: Set<SpotCategory> = [],
        when: WhenFilter = .now,
        freeOnly: Bool = false,
        limit: Int = 200
    ) {
        self.bounds = bounds
        self.categories = categories
        self.when = when
        self.freeOnly = freeOnly
        self.limit = limit
    }
}

/// Port: where spots come from. Implemented by `Networking.LiveSpotsService` (HTTP)
/// and `FakeSpotsService` (previews/tests). Features depend on this protocol only.
public protocol SpotsService: Sendable {
    func spots(_ query: SpotQuery) async throws -> SpotPage
    /// 지도 영역(bbox) 안의 항목. 영역 중심에서 가까운 순, 끝난 항목은 없다.
    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap
    /// 상세. 끝난 항목도 반환한다(`isEnded == true`).
    func spot(id: String) async throws -> Spot
}

/// Port: the user's current location. Implemented in the App layer with CoreLocation.
@MainActor
public protocol LocationProviding {
    func currentCoordinate() async throws -> Coordinate
}
