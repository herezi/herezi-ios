import Domain
import Foundation
import Testing

@testable import Networking

struct SpotDecodingTests {
    @Test func 계약_픽스처를_도메인으로_변환한다() throws {
        let dto = try JSONDecoder.herezi.decode(SpotPageDTO.self, from: Fixture.data("spot_page"))
        let page = SpotPage(items: dto.items.compactMap { $0.toDomain() }, nextCursor: dto.nextCursor)

        // 앱이 모르는 카테고리(some_future_category)는 버린다.
        #expect(page.items.map(\.id) == ["tourapi-2771234", "kopis-PF999"])
        #expect(page.nextCursor == "eyJvZmZzZXQiOjMwfQ")

        let first = try #require(page.items.first)
        #expect(first.category == .festival)
        #expect(first.isFree == true)
        #expect(first.placeName == "청계광장")
        #expect(first.distanceMeters == 280)
        #expect(first.coordinate == Coordinate(latitude: 37.5690, longitude: 126.9784))
        #expect(first.startsAt == Date(timeIntervalSince1970: 1_794_646_800))  // 2026-11-14T18:00+09:00
        #expect(first.fetchedAt == Date(timeIntervalSince1970: 1_795_134_600))  // 2026-11-20T09:30+09:00
        #expect(first.isEnded == false)

        // 소수점 초가 있는 RFC 3339 날짜도 읽는다.
        let second = try #require(page.items.last)
        #expect(second.summary == nil)
        #expect(second.isFree == nil)
        #expect(abs(second.startsAt.timeIntervalSince1970 - 1_795_251_600.123) < 0.001)
    }

    @Test func 끝난_항목의_상세를_읽는다() throws {
        let spot = try #require(
            try JSONDecoder.herezi.decode(SpotDTO.self, from: Fixture.data("spot_ended")).toDomain())

        #expect(spot.isEnded)
        #expect(spot.fetchedAt == Date(timeIntervalSince1970: 1_795_143_600))  // 2026-11-20T03:00Z
    }

    @Test func fetched_at이_없으면_계약_위반으로_실패한다() {
        let json = Data(
            """
            {"id": "x", "title": "t", "category": "nature", "lat": 1, "lng": 2,
             "starts_at": "2026-11-20T00:00:00Z", "source": "s", "is_ended": false}
            """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder.herezi.decode(SpotDTO.self, from: json) }
    }

    @Test func 에러_본문을_읽는다() throws {
        let error = try JSONDecoder.herezi.decode(ErrorDTO.self, from: Fixture.data("error"))
        #expect(error.code == "invalid_param")
        #expect(error.message == "lat is required")
    }
}

struct APIClientURLTests {
    @Test func 기본_URL_뒤에_경로를_붙인다() throws {
        let client = APIClient(baseURL: try #require(URL(string: "https://api.example.com/")))
        let url = try client.makeURL(path: "/v1/spots", query: [URLQueryItem(name: "lat", value: "1")])
        #expect(url.absoluteString == "https://api.example.com/v1/spots?lat=1")
    }
}

/// 요청 URL만 기록하고 404를 돌려주는 URLProtocol.
private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var urls: [URL] = []

    static var lastURL: URL? { lock.withLock { urls.last } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.lock.withLock { Self.urls.append(url) } }
        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// #25: 상세 요청의 스팟 ID는 정확히 한 번만 인코딩된다 (`%253A` 같은 이중 인코딩 금지).
@Suite(.serialized)
struct SpotDetailPathTests {
    private func requestedURL(id: String, base: String = "http://localhost:8080") async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let client = APIClient(
            baseURL: try #require(URL(string: base)), session: URLSession(configuration: configuration))
        await #expect(throws: SpotsServiceError.notFound) {
            _ = try await LiveSpotDetailService(client: client).spot(id: id)
        }
        return try #require(RecordingURLProtocol.lastURL)
    }

    @Test func 콜론이_있는_ID를_한_번만_인코딩한다() async throws {
        let url = try await requestedURL(id: "seoul_culture:159334")
        let path = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath)
        #expect(path == "/v1/spots/seoul_culture:159334" || path == "/v1/spots/seoul_culture%3A159334")
        #expect(!url.absoluteString.contains("%25"))
    }

    @Test func 슬래시와_퍼센트는_세그먼트_안으로_인코딩한다() async throws {
        let url = try await requestedURL(id: "a/b%c 한", base: "https://api.example.com/base/")
        #expect(url.absoluteString == "https://api.example.com/base/v1/spots/a%2Fb%25c%20%ED%95%9C")
    }
}
