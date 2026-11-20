import Domain
import Foundation

/// 테스트 번들 안의 `Fixtures/` 폴더에서 JSON을 읽는다.
enum Fixture {
    private final class BundleToken {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

/// 받은 쿼리를 기록하고 `FakeSpotsService`에 위임하는 스파이.
actor RecordingSpotsService: SpotsService {
    private let base: FakeSpotsService
    private(set) var queries: [SpotQuery] = []
    private(set) var mapQueries: [SpotMapQuery] = []

    init(base: FakeSpotsService = FakeSpotsService()) {
        self.base = base
    }

    func spots(_ query: SpotQuery) async throws -> SpotPage {
        queries.append(query)
        return try await base.spots(query)
    }

    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap {
        mapQueries.append(query)
        return try await base.spotsInBounds(query)
    }

    func spot(id: String) async throws -> Spot {
        try await base.spot(id: id)
    }
}

/// 위치 권한 거부를 흉내 내는 `LocationProviding`.
struct DeniedLocationProvider: LocationProviding {
    struct Denied: Error {}

    func currentCoordinate() async throws -> Coordinate {
        throw Denied()
    }
}

/// 고정 시각 기준 샘플 데이터 (테스트가 시계에 의존하지 않도록).
enum TestData {
    static let now = Date(timeIntervalSince1970: 1_795_000_000)
    static var spots: [Spot] { SampleSpots.make(now: now) }
    /// 목록·지도에 나오는 항목(끝난 항목 제외).
    static var listedSpots: [Spot] { spots.filter { !$0.isEnded } }
}
