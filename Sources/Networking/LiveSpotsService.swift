import Domain
import Foundation

// 서버에서 볼거리를 받아 오는 어댑터. 사용자 좌표를 담는 요청은 없다(herezi-api ADR 0004, 이슈 #37):
// 근처·지도·검색은 지역 데이터 파일로 기기에서 계산하고(`LocalSpotsService`), 위치명은 기기 지오코더로 만든다.
// 폐기 예고된 `/v1/spots`(근처)·`/v1/spots/map`·`/v1/geo/reverse`는 부르지 않는다 — scripts/check-api-drift.sh가 검사한다.

/// `GET /v1/regions/{region}/spots` — 지역 데이터 파일(ETag·304, gzip).
public struct LiveRegionSpotsSource: RegionSpotsFetching {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchRegion(_ region: String, ifNoneMatch etag: String?) async throws -> RegionFetchResult {
        let segment = APIClient.pathSegment(region)
        let (data, response) = try await client.conditionalGet(
            path: "/v1/regions/\(segment)/spots", ifNoneMatch: etag)
        if response.statusCode == 304 { return .notModified }
        return .updated(data: data, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    public func decodeRegion(_ data: Data) throws -> RegionSnapshot {
        do {
            return try JSONDecoder.herezi.decode(RegionSpotsDTO.self, from: data).toDomain()
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

/// `GET /v1/spots/{id}` — 상세(좌표를 보내지 않음). 지역 데이터에 없는 항목(저장했지만 오래 지난 항목 등)에 쓴다.
public struct LiveSpotDetailService: SpotDetailFetching {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func spot(id: String) async throws -> Spot {
        // ID는 여기서 한 번만 인코딩한다. APIClient는 path를 다시 인코딩하지 않는다(#25).
        let segment = APIClient.pathSegment(id)
        let dto: SpotDTO
        do {
            dto = try await client.get(SpotDTO.self, path: "/v1/spots/\(segment)")
        } catch APIError.server(status: 404, _, _) {
            throw SpotsServiceError.notFound
        }
        guard let spot = dto.toDomain() else {
            throw APIError.decoding("Unknown category \(dto.category)")
        }
        return spot
    }
}
