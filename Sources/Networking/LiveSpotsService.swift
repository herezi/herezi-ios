import Domain
import Foundation

/// `SpotsService` backed by the real Herezi API (`GET /v1/spots`, `GET /v1/spots/map`, `GET /v1/spots/{id}`,
/// `GET /v1/geo/reverse`).
public struct LiveSpotsService: SpotsService {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func spots(_ query: SpotQuery) async throws -> SpotPage {
        try await client.get(SpotPageDTO.self, path: "/v1/spots", query: Self.queryItems(for: query)).toDomain()
    }

    public func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap {
        try await client.get(SpotMapDTO.self, path: "/v1/spots/map", query: Self.queryItems(for: query)).toDomain()
    }

    public func spot(id: String) async throws -> Spot {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let dto: SpotDTO
        do {
            dto = try await client.get(SpotDTO.self, path: "/v1/spots/\(escaped)")
        } catch APIError.server(status: 404, _, _) {
            throw SpotsServiceError.notFound
        }
        guard let spot = dto.toDomain() else {
            throw APIError.decoding("Unknown category \(dto.category)")
        }
        return spot
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> String {
        try await client.get(
            GeoReverseDTO.self, path: "/v1/geo/reverse",
            query: [
                URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                URLQueryItem(name: "lng", value: String(coordinate.longitude)),
            ]
        ).label
    }

    static func queryItems(for query: SpotQuery) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "lat", value: String(query.coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(query.coordinate.longitude)),
            URLQueryItem(name: "radius_m", value: String(query.radiusMeters)),
            URLQueryItem(name: "when", value: query.when.rawValue),
            URLQueryItem(name: "limit", value: String(query.limit)),
        ]
        if !query.categories.isEmpty {
            let joined = query.categories.map(\.rawValue).sorted().joined(separator: ",")
            items.append(URLQueryItem(name: "category", value: joined))
        }
        if query.freeOnly {
            items.append(URLQueryItem(name: "free", value: "true"))
        }
        if let keyword = query.normalizedKeyword {
            items.append(URLQueryItem(name: "q", value: keyword))
        }
        if let cursor = query.cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }

    static func queryItems(for query: SpotMapQuery) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "sw_lat", value: String(query.bounds.southWest.latitude)),
            URLQueryItem(name: "sw_lng", value: String(query.bounds.southWest.longitude)),
            URLQueryItem(name: "ne_lat", value: String(query.bounds.northEast.latitude)),
            URLQueryItem(name: "ne_lng", value: String(query.bounds.northEast.longitude)),
            URLQueryItem(name: "when", value: query.when.rawValue),
            URLQueryItem(name: "limit", value: String(query.limit)),
        ]
        if !query.categories.isEmpty {
            let joined = query.categories.map(\.rawValue).sorted().joined(separator: ",")
            items.append(URLQueryItem(name: "category", value: joined))
        }
        if query.freeOnly {
            items.append(URLQueryItem(name: "free", value: "true"))
        }
        return items
    }
}
