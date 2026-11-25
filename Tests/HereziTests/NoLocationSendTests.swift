import Domain
import FeatureHome
import FeatureNearby
import FeatureSearch
import FeatureSpotDetail
import Foundation
import Testing

@testable import Networking

/// 앱이 서버로 보낸 요청 하나 (URLProtocol이 본 그대로).
struct CapturedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?
}

/// 실서버 대신 계약 모양의 응답을 주고, 나간 요청을 모두 기록하는 URLProtocol.
/// 지역 파일은 ETag `"v1"` — 같은 `If-None-Match`면 304.
final class ContractStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [CapturedRequest] = []

    static func reset() { lock.withLock { captured = [] } }
    static var requests: [CapturedRequest] { lock.withLock { captured } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.lock.withLock {
            Self.captured.append(CapturedRequest(method: method, url: url, headers: headers, body: body))
        }
        let (status, responseHeaders, data) = Self.respond(method: method, path: url.path, headers: headers)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: responseHeaders)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func respond(method: String, path: String, headers: [String: String])
        -> (Int, [String: String], Data)
    {
        let json = ["Content-Type": "application/json"]
        func fixture(_ name: String) -> Data { (try? Fixture.data(name)) ?? Data() }
        switch (method, path) {
        case ("GET", "/v1/regions/seoul/spots"):
            if headers["If-None-Match"] == "\"v1\"" { return (304, ["ETag": "\"v1\""], Data()) }
            return (200, json.merging(["ETag": "\"v1\""]) { $1 }, fixture("region_spots"))
        case ("GET", let p) where p.hasPrefix("/v1/spots/"):
            return (200, json, fixture("spot_ended"))
        case ("GET", "/v1/me/saved"):
            return (200, json, Data(#"{"items":[]}"#.utf8))
        case ("PUT", let p) where p.hasPrefix("/v1/me/saved/"), ("DELETE", let p) where p.hasPrefix("/v1/me/saved/"):
            return (204, [:], Data())
        case ("POST", "/v1/me/saved:import"):
            return (200, json, Data(#"{"imported":1,"skipped_unknown":0}"#.utf8))
        default:
            return (404, json, Data(#"{"code":"not_found","message":"no route"}"#.utf8))
        }
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// 이슈 #37 완료 기준: 앱의 주요 흐름(홈·전체 목록·지도·검색·상세·저장)을 실제 HTTP 어댑터로 돌려도
/// 서버로 나가는 요청에 사용자 좌표가 하나도 담기지 않는다(herezi-api ADR 0004).
@Suite(.serialized)
@MainActor
struct NoLocationSendTests {
    /// 기기 위치. 다른 숫자와 헷갈리지 않게 끝자리를 일부러 특이하게 둔다.
    static let device = Coordinate(latitude: 37.5687123, longitude: 126.9812345)
    static let forbiddenNames: Set<String> = [
        "lat", "lng", "lon", "long", "latitude", "longitude", "radius_m", "sw_lat", "sw_lng", "ne_lat", "ne_lng",
        "coords", "coord", "coordinate", "coordinates", "location", "bbox",
    ]
    static let forbiddenPaths: Set<String> = ["/v1/spots", "/v1/spots/map", "/v1/geo/reverse"]
    /// 기기 위치·지도 영역에서 나올 수 있는 숫자 조각.
    static let forbiddenFragments = ["37.5687", "126.9812", "37.568", "126.981"]

    @Test func 주요_흐름에서_좌표를_서버로_보내지_않는다() async throws {
        ContractStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContractStubURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "https://api.example.com")!, session: URLSession(configuration: configuration))
        let now = kst(2026, 11, 25, 10)
        let repository = RegionSpotsRepository(
            fetcher: LiveRegionSpotsSource(client: client), cache: tempRegionCache(), now: { now })
        let service = LocalSpotsService(
            repository: repository, detail: LiveSpotDetailService(client: client), now: { now })
        let location = FixedLocationProvider(Self.device)
        let library = makeLibrary(
            account: LiveAccountService(client: client, now: { now }),
            legacy: [TestData.spots[0]], now: { now })

        // 홈(S1): 첫 진입 → 당겨서 새로고침 → 포그라운드 복귀.
        let home = HomeViewModel(
            service: service, location: location, naming: FixedPlaceNaming(name: "중구 태평로1가"), saved: library,
            now: { now })
        await home.start()
        #expect(home.state == .loaded)
        #expect(home.feed?.isEmpty == false)
        await home.reload()
        await home.reloadIfStale()

        // 전체 목록(S1b): 필터·페이지·새로고침.
        let list = NearbyViewModel(service: service, location: location)
        await list.reload()
        #expect(!list.spots.isEmpty)
        await list.setWhen(.week)
        await list.toggle(.festival)
        await list.setFreeOnly(true)
        await list.loadMore()
        await list.refresh()

        // 지도(S2): 첫 진입 → 다른 영역 다시 찾기 → 내 위치 → 포그라운드.
        let map = MapViewModel(service: service, location: location, naming: FixedPlaceNaming(name: "중구"))
        await map.start()
        #expect(map.state == .loaded)
        let elsewhere = CoordinateBounds.around(
            Coordinate(latitude: 37.5801234, longitude: 126.9901234), radiusMeters: 2_000)
        map.cameraDidBecomeIdle(bounds: elsewhere, byUser: true)
        await map.searchThisArea()
        await map.moveToMyLocation()
        await map.refreshOnForeground()

        // 검색(S5).
        let search = SearchViewModel(
            service: service, recents: RecentSearchesStore(defaults: freshDefaults()), origin: Self.device)
        search.text = "빛초롱"
        await search.submit()
        if case .results(let items) = search.phase {
            #expect(items.map(\.id) == ["tourapi:2771234"])
        } else {
            Issue.record("검색 결과가 없다: \(search.phase)")
        }

        // 상세(S3): 기기 데이터에 있는 항목(요청 없음) / 없는 항목(GET /v1/spots/{id}).
        let local = SpotDetailViewModel(id: "seoul_culture:1", service: service, saved: library, now: { now })
        await local.load()
        #expect(local.isEnded)
        let remote = SpotDetailViewModel(id: "gone:1", service: service, saved: library, now: { now })
        await remote.load()

        // 저장(S4): 기기 저장 옮기기·목록·저장·취소.
        _ = await library.migrateLegacy()
        try await library.refresh()
        let lantern = try await service.spot(id: "tourapi:2771234")
        #expect(await library.toggle(lantern) == "저장했어요")
        #expect(await library.toggle(lantern) == "저장을 취소했어요")

        // --- 검사 ---------------------------------------------------------------
        let requests = ContractStubURLProtocol.requests
        let paths = requests.map { "\($0.method) \($0.url.path)" }
        // 흐름이 실제로 서버를 거쳤는지(검사가 헛돌지 않게).
        #expect(paths.contains("GET /v1/regions/seoul/spots"))
        #expect(paths.contains("GET /v1/spots/gone:1"))
        #expect(paths.contains("PUT /v1/me/saved/tourapi:2771234"))
        #expect(paths.contains("POST /v1/me/saved:import"))
        // 지역 파일은 처음 받은 뒤 ETag로만 확인한다.
        let regionRequests = requests.filter { $0.url.path == "/v1/regions/seoul/spots" }
        #expect(regionRequests.first?.headers["If-None-Match"] == nil)
        #expect(regionRequests.dropFirst().allSatisfy { $0.headers["If-None-Match"] == "\"v1\"" })

        for request in requests {
            let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
            let names = Set((components?.queryItems ?? []).map { $0.name.lowercased() })
            #expect(names.isDisjoint(with: Self.forbiddenNames), "좌표 파라미터: \(request.url)")
            #expect(!Self.forbiddenPaths.contains(request.url.path), "폐기 예고 경로: \(request.url)")
            let headerText = request.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            let bodyText = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
            for fragment in Self.forbiddenFragments {
                #expect(!request.url.absoluteString.contains(fragment), "URL에 좌표: \(request.url)")
                #expect(!headerText.contains(fragment), "헤더에 좌표: \(request.url)")
                #expect(!bodyText.contains(fragment), "본문에 좌표: \(request.url)")
            }
            if let body = request.body, let json = try? JSONSerialization.jsonObject(with: body) {
                #expect(Self.keys(in: json).isDisjoint(with: Self.forbiddenNames), "본문 좌표 키: \(request.url)")
            }
        }
    }

    /// JSON 안의 모든 키(소문자).
    static func keys(in json: Any) -> Set<String> {
        switch json {
        case let object as [String: Any]:
            return object.reduce(into: Set(object.keys.map { $0.lowercased() })) { $0.formUnion(keys(in: $1.value)) }
        case let array as [Any]:
            return array.reduce(into: Set<String>()) { $0.formUnion(keys(in: $1)) }
        default:
            return []
        }
    }
}
