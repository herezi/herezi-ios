import Foundation

/// In-memory `SpotsService` for SwiftUI previews, tests and offline runs (Debug default, `HEREZI_FAKE_API`).
/// Applies the category and `free` filters like the server would, so UI behaves realistically.
/// 서버처럼 목록·지도에는 끝난 항목(`isEnded`)을 빼고, 상세(`spot(id:)`)에서만 돌려준다.
public struct FakeSpotsService: SpotsService {
    public var allSpots: [Spot]
    public var failure: (any Error & Sendable)?

    public init(spots: [Spot] = SampleSpots.all, failure: (any Error & Sendable)? = nil) {
        self.allSpots = spots
        self.failure = failure
    }

    public func spots(_ query: SpotQuery) async throws -> SpotPage {
        if let failure { throw failure }
        let keyword = query.normalizedKeyword
        let filtered = allSpots.filter {
            Self.matches($0, categories: query.categories, freeOnly: query.freeOnly)
                && Self.matches($0, keyword: keyword)
        }
        return SpotPage(items: Array(filtered.prefix(query.limit)))
    }

    public func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap {
        if let failure { throw failure }
        let center = query.bounds.center
        let inside =
            allSpots
            .filter {
                query.bounds.contains($0.coordinate)
                    && Self.matches($0, categories: query.categories, freeOnly: query.freeOnly)
            }
            .sorted { Self.squaredDegrees($0.coordinate, center) < Self.squaredDegrees($1.coordinate, center) }
        return SpotMap(items: Array(inside.prefix(query.limit)), truncated: inside.count > query.limit)
    }

    public func spot(id: String) async throws -> Spot {
        if let failure { throw failure }
        guard let spot = allSpots.first(where: { $0.id == id }) else { throw FakeError.notFound }
        return spot
    }

    private static func matches(_ spot: Spot, categories: Set<SpotCategory>, freeOnly: Bool) -> Bool {
        !spot.isEnded && (categories.isEmpty || categories.contains(spot.category))
            && (!freeOnly || spot.isFree == true)
    }

    /// 서버처럼 제목·장소명·주소 중 하나에 대소문자 무시 부분 일치.
    private static func matches(_ spot: Spot, keyword: String?) -> Bool {
        guard let keyword else { return true }
        return [spot.title, spot.placeName, spot.address].compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(keyword) }
    }

    /// 정렬용 근사 거리(위경도 차의 제곱합). 서울 범위의 작은 영역에서는 순서만 맞으면 된다.
    private static func squaredDegrees(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = a.latitude - b.latitude
        let dLng = a.longitude - b.longitude
        return dLat * dLat + dLng * dLng
    }

    public enum FakeError: Error, Sendable {
        case notFound
    }
}

/// Fixed sample data around 서울시청. Dates are relative to "now" so they never look stale.
public enum SampleSpots {
    public static var all: [Spot] { make(now: Date()) }

    /// 끝난 샘플 항목의 id. 목록·지도에는 나오지 않고 상세(`spot(id:)`)로만 열린다.
    public static let endedID = "sample-ended"

    public static func make(now: Date) -> [Spot] {
        let day: TimeInterval = 86_400
        return [
            Spot(
                id: "sample-1", title: "서울빛초롱축제", summary: "청계천을 따라 수백 개의 등이 불을 밝히는 겨울 축제.",
                category: .festival, coordinate: Coordinate(latitude: 37.5690, longitude: 126.9784),
                address: "서울 중구 청계천로 1", placeName: "청계광장",
                startsAt: now.addingTimeInterval(-2 * day), endsAt: now.addingTimeInterval(10 * day),
                isFree: true, source: "tourapi", fetchedAt: now.addingTimeInterval(-20 * 60), distanceMeters: 280),
            Spot(
                id: "sample-2", title: "덕수궁 야간 개장", summary: "조명이 켜진 석조전과 돌담길 산책.",
                category: .nature, coordinate: Coordinate(latitude: 37.5658, longitude: 126.9751),
                placeName: "덕수궁", startsAt: now, endsAt: now, isFree: false, source: "seoul_culture",
                fetchedAt: now.addingTimeInterval(-3 * 3600), distanceMeters: 250),
            Spot(
                id: "sample-3", title: "현대미술 기획전 〈도시의 밤〉", category: .exhibition,
                coordinate: Coordinate(latitude: 37.5796, longitude: 126.9800), placeName: "국립현대미술관 서울",
                startsAt: now.addingTimeInterval(-30 * day), endsAt: now.addingTimeInterval(40 * day),
                source: "seoul_culture", fetchedAt: now.addingTimeInterval(-day), distanceMeters: 1_460),
            Spot(
                id: "sample-4", title: "광화문 버스킹 페스타", category: .performance,
                coordinate: Coordinate(latitude: 37.5720, longitude: 126.9769), placeName: "광화문광장",
                startsAt: now.addingTimeInterval(day), endsAt: now.addingTimeInterval(2 * day), isFree: true,
                source: "kopis", fetchedAt: now.addingTimeInterval(-90), distanceMeters: 620),
            Spot(
                id: "sample-5", title: "을지로 팝업스토어", category: .popup,
                coordinate: Coordinate(latitude: 37.5660, longitude: 126.9910), placeName: "을지로3가",
                startsAt: now.addingTimeInterval(-day), endsAt: now.addingTimeInterval(5 * day), source: "news",
                fetchedAt: now.addingTimeInterval(-2 * 3600), distanceMeters: 1_170),
            Spot(
                id: endedID, title: "가을 국화 전시회", summary: "지난달 서울광장에서 열린 국화 전시.",
                category: .nature, coordinate: Coordinate(latitude: 37.5663, longitude: 126.9779),
                placeName: "서울광장", startsAt: now.addingTimeInterval(-40 * day),
                endsAt: now.addingTimeInterval(-10 * day), isFree: true, source: "seoul_culture",
                fetchedAt: now.addingTimeInterval(-5 * 3600), isEnded: true),
        ]
    }
}
