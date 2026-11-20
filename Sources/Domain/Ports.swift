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

/// Port: where spots come from. Implemented by `Networking.LiveSpotsService` (HTTP)
/// and `FakeSpotsService` (previews/tests). Features depend on this protocol only.
public protocol SpotsService: Sendable {
    func spots(_ query: SpotQuery) async throws -> SpotPage
    func spot(id: String) async throws -> Spot
}

/// Port: the user's current location. Implemented in the App layer with CoreLocation.
@MainActor
public protocol LocationProviding {
    func currentCoordinate() async throws -> Coordinate
}
