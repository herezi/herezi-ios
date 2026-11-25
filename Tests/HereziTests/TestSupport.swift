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

    func reverseGeocode(_ coordinate: Coordinate) async throws -> String {
        try await base.reverseGeocode(coordinate)
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
    func reverseGeocode(_ coordinate: Coordinate) async throws -> String { throw Offline() }
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
    func reverseGeocode(_ coordinate: Coordinate) async throws -> String {
        if failing { throw Offline() }
        return try await base.reverseGeocode(coordinate)
    }
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
    func reverseGeocode(_ coordinate: Coordinate) async throws -> String { "" }
}

// MARK: - 계정·로그인

/// 테스트용 저장 목록. `provider`가 있으면 로그인 상태(가짜 세션)로 시작한다.
@MainActor
func makeLibrary(
    provider: AuthProvider? = .kakao, account: (any AccountService)? = nil, legacy: [Spot] = [],
    defaults: UserDefaults = freshDefaults(), now: @escaping @Sendable () -> Date = { TestData.now }
) -> SavedLibrary {
    let auth = AuthService(
        backend: FakeAuthBackend(now: now),
        storage: InMemorySessionStore(provider.map { FakeAuthBackend.session(provider: $0, now: now()) }), now: now)
    let store = SavedSpotsStore(defaults: defaults, key: "legacy")
    for (offset, spot) in legacy.enumerated() { store.save(spot, at: now().addingTimeInterval(Double(-offset) * 60)) }
    return SavedLibrary(
        auth: auth, account: account ?? FakeAccountService(spots: TestData.spots, now: now), legacy: store,
        cache: defaults, now: now)
}

/// 정해 둔 오류를 던지거나 기록하는 계정 API (FakeAccountService에 위임).
actor ScriptedAccountService: AccountService {
    private let base: FakeAccountService
    var saveError: (any Error)?
    var unsaveError: (any Error)?
    var listError: (any Error)?
    var deleteError: (any Error)?
    private(set) var importCalls: [[String]] = []
    private(set) var deleteCalls = 0

    init(base: FakeAccountService = FakeAccountService(spots: TestData.spots, now: { TestData.now })) {
        self.base = base
    }

    func set(save: (any Error)? = nil, unsave: (any Error)? = nil, list: (any Error)? = nil, delete: (any Error)? = nil)
    {
        saveError = save
        unsaveError = unsave
        listError = list
        deleteError = delete
    }

    func savedPage(cursor: String?, accessToken: String) async throws -> SavedPage {
        if let listError { throw listError }
        return try await base.savedPage(cursor: cursor, accessToken: accessToken)
    }

    func save(spotID: String, accessToken: String) async throws {
        if let saveError { throw saveError }
        try await base.save(spotID: spotID, accessToken: accessToken)
    }

    func unsave(spotID: String, accessToken: String) async throws {
        if let unsaveError { throw unsaveError }
        try await base.unsave(spotID: spotID, accessToken: accessToken)
    }

    func importSaved(spotIDs: [String], accessToken: String) async throws -> SavedImportResult {
        importCalls.append(spotIDs)
        return try await base.importSaved(spotIDs: spotIDs, accessToken: accessToken)
    }

    func deleteAccount(accessToken: String) async throws {
        deleteCalls += 1
        if let deleteError { throw deleteError }
        try await base.deleteAccount(accessToken: accessToken)
    }
}

/// 요청별로 응답을 정해 두는 URLProtocol. 세션마다 `X-Stub-ID` 헤더로 핸들러를 나눠 병렬 테스트에서도 섞이지 않는다.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    /// `handler`를 쓰는 URLSession을 만든다.
    static func session(_ handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Stub-ID": id]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub-ID") ?? ""
        let handler = Self.lock.withLock { Self.handlers[id] }
        var request = self.request
        // URLSession은 httpBody를 스트림으로 바꾼다 — 테스트가 본문을 읽을 수 있게 되돌린다.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Data(reading: stream)
        }
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

/// 요청을 순서대로 기록하는 상자 (URLProtocol 핸들러가 Sendable이어야 해서).
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { stored } }

    func append(_ request: URLRequest) { lock.withLock { stored.append(request) } }

    func json(_ index: Int) -> [String: Any]? {
        guard let body = requests[index].httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}
