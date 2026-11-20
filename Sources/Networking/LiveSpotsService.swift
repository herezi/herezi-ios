import Domain
import Foundation

/// `SpotsService` backed by the real Herezi API (`GET /v1/spots`, `GET /v1/spots/{id}`).
public struct LiveSpotsService: SpotsService {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func spots(_ query: SpotQuery) async throws -> SpotPage {
        try await client.get(SpotPageDTO.self, path: "/v1/spots", query: Self.queryItems(for: query)).toDomain()
    }

    public func spot(id: String) async throws -> Spot {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let dto = try await client.get(SpotDTO.self, path: "/v1/spots/\(escaped)")
        guard let spot = dto.toDomain() else {
            throw APIError.decoding("Unknown category \(dto.category)")
        }
        return spot
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
        if let cursor = query.cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }
}
