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
    /// 원본 소스에서 마지막으로 가져온 시각 (상세의 "갱신 시각").
    public let fetchedAt: Date
    /// Distance from the requested location, in meters (server-computed, `/v1/spots` only).
    public let distanceMeters: Int?
    /// 응답 시각 기준으로 끝났는지. 목록·지도에는 끝난 항목이 오지 않으므로 상세에서만 true일 수 있다.
    public let isEnded: Bool

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
        fetchedAt: Date,
        distanceMeters: Int? = nil,
        isEnded: Bool = false
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
        self.fetchedAt = fetchedAt
        self.distanceMeters = distanceMeters
        self.isEnded = isEnded
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

/// Result of `GET /v1/spots/map` (bbox). `truncated`면 영역 안에 `limit`보다 많은 항목이 있다.
public struct SpotMap: Hashable, Sendable {
    public let items: [Spot]
    public let truncated: Bool

    public init(items: [Spot], truncated: Bool) {
        self.items = items
        self.truncated = truncated
    }
}

/// 지도 영역. 남서(sw)·북동(ne) 꼭짓점. 날짜변경선을 넘는 영역은 계약상 지원하지 않는다.
public struct CoordinateBounds: Hashable, Sendable {
    public let southWest: Coordinate
    public let northEast: Coordinate

    public init(southWest: Coordinate, northEast: Coordinate) {
        self.southWest = southWest
        self.northEast = northEast
    }

    public var center: Coordinate {
        Coordinate(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2)
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        (southWest.latitude...northEast.latitude).contains(coordinate.latitude)
            && (southWest.longitude...northEast.longitude).contains(coordinate.longitude)
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

    /// 위치 권한이 없을 때의 기준점 서울시청 (계약 `GET /v1/spots` 설명, S0 스펙과 같은 값).
    public static let seoulCityHall = Coordinate(latitude: 37.5663, longitude: 126.9779)
}
