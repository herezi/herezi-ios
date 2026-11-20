import Domain
import Foundation

// Wire types for api/openapi.yaml `components.schemas`.
// CodingKeys are spelled out on purpose: scripts/check-api-drift.sh compares them
// against the Spot schema properties. Keep one `case x = "json_name"` per line.

/// `components.schemas.Spot`
struct SpotDTO: Decodable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let category: String
    let lat: Double
    let lng: Double
    let address: String?
    let placeName: String?
    let startsAt: Date
    let endsAt: Date?
    let isFree: Bool?
    let imageURL: URL?
    let source: String
    let sourceURL: URL?
    let fetchedAt: Date
    let distanceMeters: Int?
    let isEnded: Bool

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case title = "title"
        case summary = "summary"
        case category = "category"
        case lat = "lat"
        case lng = "lng"
        case address = "address"
        case placeName = "place_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case isFree = "is_free"
        case imageURL = "image_url"
        case source = "source"
        case sourceURL = "source_url"
        case fetchedAt = "fetched_at"
        case distanceMeters = "distance_m"
        case isEnded = "is_ended"
    }

    /// Returns nil for categories this app version does not know yet (forward compatible).
    func toDomain() -> Spot? {
        guard let category = SpotCategory(rawValue: category) else { return nil }
        return Spot(
            id: id, title: title, summary: summary, category: category,
            coordinate: Coordinate(latitude: lat, longitude: lng), address: address, placeName: placeName,
            startsAt: startsAt, endsAt: endsAt, isFree: isFree, imageURL: imageURL, source: source,
            sourceURL: sourceURL, fetchedAt: fetchedAt, distanceMeters: distanceMeters, isEnded: isEnded)
    }
}

/// `components.schemas.SpotPage`
struct SpotPageDTO: Decodable, Sendable {
    let items: [SpotDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items = "items"
        case nextCursor = "next_cursor"
    }

    func toDomain() -> SpotPage {
        SpotPage(items: items.compactMap { $0.toDomain() }, nextCursor: nextCursor)
    }
}

/// `components.schemas.SpotMap`
struct SpotMapDTO: Decodable, Sendable {
    let items: [SpotDTO]
    let truncated: Bool

    enum CodingKeys: String, CodingKey {
        case items = "items"
        case truncated = "truncated"
    }

    func toDomain() -> SpotMap {
        SpotMap(items: items.compactMap { $0.toDomain() }, truncated: truncated)
    }
}

/// `components.schemas.Error`
struct ErrorDTO: Decodable, Sendable {
    let code: String
    let message: String
}
