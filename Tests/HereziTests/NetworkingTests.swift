import Domain
import Foundation
import Testing

@testable import Networking

struct SpotDecodingTests {
    @Test func 계약_픽스처를_도메인으로_변환한다() throws {
        let dto = try JSONDecoder.herezi.decode(SpotPageDTO.self, from: Fixture.data("spot_page"))
        let page = dto.toDomain()

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

        // 소수점 초가 있는 RFC 3339 날짜도 읽는다.
        let second = try #require(page.items.last)
        #expect(second.summary == nil)
        #expect(second.isFree == nil)
        #expect(abs(second.startsAt.timeIntervalSince1970 - 1_795_251_600.123) < 0.001)
    }

    @Test func 에러_본문을_읽는다() throws {
        let error = try JSONDecoder.herezi.decode(ErrorDTO.self, from: Fixture.data("error"))
        #expect(error.code == "invalid_param")
        #expect(error.message == "lat is required")
    }
}

struct LiveSpotsServiceQueryTests {
    private func dictionary(_ query: SpotQuery) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: LiveSpotsService.queryItems(for: query).map { ($0.name, $0.value ?? "") })
    }

    @Test func 기본_쿼리는_필수_파라미터만_보낸다() {
        let items = dictionary(SpotQuery(coordinate: .seoulCityHall))
        #expect(items["lat"] == "37.5665")
        #expect(items["lng"] == "126.978")
        #expect(items["radius_m"] == "3000")
        #expect(items["when"] == "now")
        #expect(items["limit"] == "30")
        #expect(items["category"] == nil)
        #expect(items["free"] == nil)
        #expect(items["cursor"] == nil)
    }

    @Test func 카테고리와_무료와_커서를_담는다() {
        let query = SpotQuery(
            coordinate: .seoulCityHall, categories: [.popup, .festival], when: .weekend, freeOnly: true,
            cursor: "abc")
        let items = dictionary(query)
        #expect(items["category"] == "festival,popup")
        #expect(items["free"] == "true")
        #expect(items["when"] == "weekend")
        #expect(items["cursor"] == "abc")
    }

    @Test func 기본_URL_뒤에_경로를_붙인다() throws {
        let client = APIClient(baseURL: try #require(URL(string: "https://api.example.com/")))
        let url = try client.makeURL(path: "/v1/spots", query: [URLQueryItem(name: "lat", value: "1")])
        #expect(url.absoluteString == "https://api.example.com/v1/spots?lat=1")
    }
}
