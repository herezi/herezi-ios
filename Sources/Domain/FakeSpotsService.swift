import Foundation

/// In-memory `SpotsService` for SwiftUI previews, tests and offline runs (Debug default, `HEREZI_FAKE_API`).
/// Applies the category and `free` filters like the server would, so UI behaves realistically.
public struct FakeSpotsService: SpotsService {
    public var allSpots: [Spot]
    public var failure: (any Error & Sendable)?

    public init(spots: [Spot] = SampleSpots.all, failure: (any Error & Sendable)? = nil) {
        self.allSpots = spots
        self.failure = failure
    }

    public func spots(_ query: SpotQuery) async throws -> SpotPage {
        if let failure { throw failure }
        let filtered = allSpots.filter {
            (query.categories.isEmpty || query.categories.contains($0.category))
                && (!query.freeOnly || $0.isFree == true)
        }
        return SpotPage(items: Array(filtered.prefix(query.limit)))
    }

    public func spot(id: String) async throws -> Spot {
        if let failure { throw failure }
        guard let spot = allSpots.first(where: { $0.id == id }) else { throw FakeError.notFound }
        return spot
    }

    public enum FakeError: Error, Sendable {
        case notFound
    }
}

/// Fixed sample data around 서울시청. Dates are relative to "now" so they never look stale.
public enum SampleSpots {
    public static var all: [Spot] { make(now: Date()) }

    public static func make(now: Date) -> [Spot] {
        let day: TimeInterval = 86_400
        return [
            Spot(
                id: "sample-1", title: "서울빛초롱축제", summary: "청계천을 따라 수백 개의 등이 불을 밝히는 겨울 축제.",
                category: .festival, coordinate: Coordinate(latitude: 37.5690, longitude: 126.9784),
                address: "서울 중구 청계천로 1", placeName: "청계광장",
                startsAt: now.addingTimeInterval(-2 * day), endsAt: now.addingTimeInterval(10 * day),
                isFree: true, source: "tourapi", distanceMeters: 280),
            Spot(
                id: "sample-2", title: "덕수궁 야간 개장", summary: "조명이 켜진 석조전과 돌담길 산책.",
                category: .nature, coordinate: Coordinate(latitude: 37.5658, longitude: 126.9751),
                placeName: "덕수궁", startsAt: now, endsAt: now, isFree: false, source: "seoul_culture",
                distanceMeters: 250),
            Spot(
                id: "sample-3", title: "현대미술 기획전 〈도시의 밤〉", category: .exhibition,
                coordinate: Coordinate(latitude: 37.5796, longitude: 126.9800), placeName: "국립현대미술관 서울",
                startsAt: now.addingTimeInterval(-30 * day), endsAt: now.addingTimeInterval(40 * day),
                source: "seoul_culture", distanceMeters: 1_460),
            Spot(
                id: "sample-4", title: "광화문 버스킹 페스타", category: .performance,
                coordinate: Coordinate(latitude: 37.5720, longitude: 126.9769), placeName: "광화문광장",
                startsAt: now.addingTimeInterval(day), endsAt: now.addingTimeInterval(2 * day), isFree: true,
                source: "kopis", distanceMeters: 620),
            Spot(
                id: "sample-5", title: "을지로 팝업스토어", category: .popup,
                coordinate: Coordinate(latitude: 37.5660, longitude: 126.9910), placeName: "을지로3가",
                startsAt: now.addingTimeInterval(-day), endsAt: now.addingTimeInterval(5 * day), source: "news",
                distanceMeters: 1_170),
        ]
    }
}
