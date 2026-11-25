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
    /// 저장 시각 (`/v1/me/saved`에서만).
    let savedAt: Date?
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
        case savedAt = "saved_at"
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
}

extension SpotPageDTO {
    /// `GET /v1/me/saved` 응답(같은 `SpotPage` 스키마 + 항목별 `saved_at`). `saved_at`이 없으면 `fallbackDate`.
    func toSavedPage(fallbackDate: Date) -> SavedPage {
        SavedPage(
            items: items.compactMap { dto in
                dto.toDomain().map { SavedSpot(spot: $0, savedAt: dto.savedAt ?? fallbackDate) }
            },
            nextCursor: nextCursor)
    }
}

/// `components.schemas.RegionSpot` — 지역 데이터 파일의 항목(`Spot`에서 `distance_m`·`saved_at`만 없음).
struct RegionSpotDTO: Decodable, Sendable {
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
    /// 서버 `generated_at` 기준. 앱은 기기 시각으로 다시 계산한다(`Spot.hasEnded(at:)`).
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
        case isEnded = "is_ended"
    }

    /// 모르는 카테고리는 nil (앞으로 늘어나도 앱이 깨지지 않게).
    func toDomain() -> Spot? {
        guard let category = SpotCategory(rawValue: category) else { return nil }
        return Spot(
            id: id, title: title, summary: summary, category: category,
            coordinate: Coordinate(latitude: lat, longitude: lng), address: address, placeName: placeName,
            startsAt: startsAt, endsAt: endsAt, isFree: isFree, imageURL: imageURL, source: source,
            sourceURL: sourceURL, fetchedAt: fetchedAt, isEnded: isEnded)
    }
}

/// `components.schemas.RegionSpots` — `GET /v1/regions/{region}/spots` 본문.
struct RegionSpotsDTO: Decodable, Sendable {
    let region: String
    let generatedAt: Date
    let count: Int
    let items: [RegionSpotDTO]

    enum CodingKeys: String, CodingKey {
        case region = "region"
        case generatedAt = "generated_at"
        case count = "count"
        case items = "items"
    }

    func toDomain() -> RegionSnapshot {
        RegionSnapshot(region: region, generatedAt: generatedAt, spots: items.compactMap { $0.toDomain() })
    }
}

/// `components.schemas.Error`
struct ErrorDTO: Decodable, Sendable {
    let code: String
    let message: String
}

/// `components.schemas.SavedImportRequest`
struct SavedImportRequestDTO: Encodable, Sendable {
    let spotIDs: [String]

    enum CodingKeys: String, CodingKey {
        case spotIDs = "spot_ids"
    }
}

/// `components.schemas.DeleteMeRequest` — Apple 사용자 탈퇴 때 재인증 코드(herezi-api#72).
struct DeleteMeRequestDTO: Encodable, Sendable {
    let appleAuthorizationCode: String

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

/// `components.schemas.SavedImportResult`
struct SavedImportResultDTO: Decodable, Sendable {
    let imported: Int
    let skippedUnknown: Int

    enum CodingKeys: String, CodingKey {
        case imported = "imported"
        case skippedUnknown = "skipped_unknown"
    }
}
