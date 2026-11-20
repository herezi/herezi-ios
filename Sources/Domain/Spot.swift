import Foundation

/// A thing worth seeing near the user right now (festival, exhibition, blossom spot, ...).
///
/// Mirrors `components.schemas.Spot` in `api/openapi.yaml`, but uses Swift-native types.
public struct Spot: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String?
    public let category: SpotCategory
    public let coordinate: Coordinate
    public let address: String?
    public let placeName: String?
    public let startsAt: Date
    public let endsAt: Date?
    public let isFree: Bool?
    public let imageURL: URL?
    public let source: String
    public let sourceURL: URL?
    /// Distance from the requested location, in meters (server-computed).
    public let distanceMeters: Int?

    public init(
        id: String,
        title: String,
        summary: String? = nil,
        category: SpotCategory,
        coordinate: Coordinate,
        address: String? = nil,
        placeName: String? = nil,
        startsAt: Date,
        endsAt: Date? = nil,
        isFree: Bool? = nil,
        imageURL: URL? = nil,
        source: String,
        sourceURL: URL? = nil,
        distanceMeters: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.coordinate = coordinate
        self.address = address
        self.placeName = placeName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isFree = isFree
        self.imageURL = imageURL
        self.source = source
        self.sourceURL = sourceURL
        self.distanceMeters = distanceMeters
    }
}

/// One page of `GET /v1/spots`.
public struct SpotPage: Hashable, Sendable {
    public let items: [Spot]
    public let nextCursor: String?

    public init(items: [Spot], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// WGS84 coordinate. Deliberately not `CLLocationCoordinate2D` so Domain stays framework-free.
public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Fallback when location permission is denied (M1 is Seoul-only).
    public static let seoulCityHall = Coordinate(latitude: 37.5665, longitude: 126.9780)
}
