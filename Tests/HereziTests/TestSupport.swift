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

/// 권한 상태를 정해 두고, 요청하면 `answer`로 바뀌는 `LocationPermissionProviding`.
@MainActor
final class FakeLocationPermissions: LocationPermissionProviding {
    var permission: LocationPermission
    let answer: LocationPermission
    private(set) var requestCount = 0

    init(_ permission: LocationPermission, answer: LocationPermission = .authorized) {
        self.permission = permission
        self.answer = answer
    }

    func requestWhenInUse() async -> LocationPermission {
        requestCount += 1
        if permission == .notDetermined { permission = answer }
        return permission
    }
}

/// 테스트마다 비어 있는 UserDefaults.
func freshDefaults() -> UserDefaults {
    let name = "herezi.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// 상세 조회 결과를 id별로 정해 두는 서비스 (저장 목록 갱신 테스트용).
struct ScriptedDetailService: SpotsService {
    enum Outcome: Sendable {
        case spot(Spot)
        case notFound
        case failure
    }

    struct Offline: Error {}

    let outcomes: [String: Outcome]

    func spots(_ query: SpotQuery) async throws -> SpotPage { SpotPage(items: []) }
    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap { SpotMap(items: [], truncated: false) }
    func spot(id: String) async throws -> Spot {
        switch outcomes[id] {
        case .spot(let spot): return spot
        case .notFound: throw SpotsServiceError.notFound
        case .failure, nil: throw Offline()
        }
    }
}

/// 정해진 위치명을 돌려주는 `PlaceNaming`.
struct FixedPlaceNaming: PlaceNaming {
    let name: String?

    func placeName(for coordinate: Coordinate) async -> String? { name }
}

/// 중간에 실패하도록 바꿀 수 있는 서비스.
actor ToggleFailingService: SpotsService {
    struct Offline: Error {}

    private let base: FakeSpotsService
    private var failing = false

    init(base: FakeSpotsService) {
        self.base = base
    }

    func setFailing(_ value: Bool) { failing = value }

    func spots(_ query: SpotQuery) async throws -> SpotPage {
        if failing { throw Offline() }
        return try await base.spots(query)
    }

    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap { try await base.spotsInBounds(query) }
    func spot(id: String) async throws -> Spot { try await base.spot(id: id) }
}

/// 커서마다 정해진 페이지를 돌려주는 서비스.
actor PagedService: SpotsService {
    private let pages: [SpotPage]
    private(set) var cursors: [String?] = []

    init(pages: [SpotPage]) {
        self.pages = pages
    }

    func spots(_ query: SpotQuery) async throws -> SpotPage {
        cursors.append(query.cursor)
        return query.cursor == nil ? pages[0] : pages[1]
    }

    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap { SpotMap(items: [], truncated: false) }
    func spot(id: String) async throws -> Spot { throw SpotsServiceError.notFound }
}
