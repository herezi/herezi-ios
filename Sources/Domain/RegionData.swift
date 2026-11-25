import Foundation

// 지역 데이터 파일 동기화 (herezi-api ADR 0004, TECH-PLAN §4, 이슈 #37).
// `GET /v1/regions/{region}/spots`를 ETag로 받아 기기(Caches)에 두고, 근처·지도·검색은 이 데이터로 기기에서 계산한다.

/// 지역 데이터 한 벌. 항목은 서버 응답 그대로(`isEnded`는 서버 `generated_at` 기준이라 화면에서는 다시 계산한다).
public struct RegionSnapshot: Sendable {
    public let region: String
    public let generatedAt: Date
    public let spots: [Spot]
    private let indexByID: [String: Int]

    public init(region: String, generatedAt: Date, spots: [Spot]) {
        self.region = region
        self.generatedAt = generatedAt
        self.spots = spots
        var index: [String: Int] = [:]
        index.reserveCapacity(spots.count)
        for (offset, spot) in spots.enumerated() { index[spot.id] = offset }
        self.indexByID = index
    }

    public func spot(id: String) -> Spot? {
        indexByID[id].map { spots[$0] }
    }
}

/// 조건부 요청 결과.
public enum RegionFetchResult: Sendable, Equatable {
    /// 304 — 가진 데이터가 최신.
    case notModified
    /// 200 — 새 본문(원본 JSON, 디스크에 그대로 저장)과 `ETag`.
    case updated(data: Data, etag: String?)
}

/// Port: 지역 데이터 파일을 받아 오고 해석한다. Networking(`LiveRegionSpotsSource`)이 구현한다. 좌표를 보내지 않는다.
public protocol RegionSpotsFetching: Sendable {
    /// `GET /v1/regions/{region}/spots` (`If-None-Match: etag`).
    func fetchRegion(_ region: String, ifNoneMatch etag: String?) async throws -> RegionFetchResult
    /// 응답 본문(또는 디스크에 둔 본문)을 해석한다.
    func decodeRegion(_ data: Data) throws -> RegionSnapshot
}

/// Port: 지역 데이터에 없는 항목의 상세 (`GET /v1/spots/{id}` — 좌표 없음).
public protocol SpotDetailFetching: Sendable {
    func spot(id: String) async throws -> Spot
}

public enum RegionDataError: Error, Sendable, Equatable {
    /// 기기에 데이터가 없고 받지도 못했다(첫 실행 + 오프라인 등).
    case unavailable
}

/// 지역 데이터 디스크 캐시. 본문 원본(`<region>.json`)과 메타(`<region>.meta.json`: ETag·저장 시각).
public struct RegionDiskCache: Sendable {
    public struct Entry: Sendable {
        public let data: Data
        public let etag: String?
        public let savedAt: Date
    }

    private struct Meta: Codable {
        let etag: String?
        let savedAt: Date
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 앱 Caches 폴더 아래 `herezi-region/`.
    public static func appCaches() -> RegionDiskCache {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return RegionDiskCache(directory: base.appendingPathComponent("herezi-region", isDirectory: true))
    }

    private func bodyURL(_ region: String) -> URL { directory.appendingPathComponent("\(region).json") }
    private func metaURL(_ region: String) -> URL { directory.appendingPathComponent("\(region).meta.json") }

    public func load(_ region: String) -> Entry? {
        guard let data = try? Data(contentsOf: bodyURL(region)) else { return nil }
        let meta = (try? Data(contentsOf: metaURL(region))).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
        return Entry(data: data, etag: meta?.etag, savedAt: meta?.savedAt ?? .distantPast)
    }

    public func save(_ region: String, data: Data, etag: String?, at date: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: bodyURL(region), options: .atomic)
        try JSONEncoder().encode(Meta(etag: etag, savedAt: date)).write(to: metaURL(region), options: .atomic)
    }

    public func remove(_ region: String) {
        try? FileManager.default.removeItem(at: bodyURL(region))
        try? FileManager.default.removeItem(at: metaURL(region))
    }
}

/// 지역 데이터 저장소. 메모리 → 디스크 → 네트워크 순으로 데이터를 찾고, ETag로 갱신한다.
///
/// - 앱 실행 후 첫 `refresh(force: false)`는 항상 서버에 확인한다(대부분 304). 이후에는 마지막 확인이 `maxAge`(서버
///   `max-age=3600`)보다 오래됐을 때만 확인한다(포그라운드 복귀). 당겨서 새로고침은 `force: true`.
/// - 받지 못해도 마지막 데이터로 계속 동작한다(오프라인). 데이터가 하나도 없을 때만 `RegionDataError.unavailable`.
/// - 동시에 들어온 갱신은 한 번의 요청으로 합친다.
public actor RegionSpotsRepository {
    public static let defaultMaxAge: TimeInterval = 3_600

    public let region: String
    private let fetcher: any RegionSpotsFetching
    private let cache: RegionDiskCache?
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date

    private var snapshot: RegionSnapshot?
    private var etag: String?
    private var lastCheckedAt: Date?
    private var didLoadDisk = false
    private var inFlight: Task<Bool, any Error>?

    public init(
        region: String = "seoul", fetcher: any RegionSpotsFetching, cache: RegionDiskCache?,
        maxAge: TimeInterval = RegionSpotsRepository.defaultMaxAge,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.region = region
        self.fetcher = fetcher
        self.cache = cache
        self.maxAge = maxAge
        self.now = now
    }

    /// 지금 쓸 데이터. 메모리·디스크에 없으면 서버에서 받는다. 아무 데이터도 없으면 던진다.
    public func current() async throws -> RegionSnapshot {
        loadDiskIfNeeded()
        if let snapshot { return snapshot }
        _ = try await refresh(force: true)
        guard let snapshot else { throw RegionDataError.unavailable }
        return snapshot
    }

    /// 데이터가 이미 있으면(메모리·디스크) 받지 않고 돌려준다. 없으면 nil.
    public func cached() -> RegionSnapshot? {
        loadDiskIfNeeded()
        return snapshot
    }

    /// 서버에 바뀌었는지 확인하고(`If-None-Match`), 새 데이터를 받았으면 true.
    /// `force == false`면 마지막 확인이 `maxAge` 안일 때 요청하지 않는다.
    @discardableResult
    public func refresh(force: Bool) async throws -> Bool {
        loadDiskIfNeeded()
        if let inFlight { return try await inFlight.value }
        if !force, let lastCheckedAt, now().timeIntervalSince(lastCheckedAt) < maxAge { return false }
        let task = Task { try await self.performRefresh() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// 마지막으로 서버에 확인한 시각(이번 실행 안). 테스트·디버그용.
    public var lastChecked: Date? { lastCheckedAt }

    private func performRefresh() async throws -> Bool {
        let result = try await fetcher.fetchRegion(region, ifNoneMatch: snapshot == nil ? nil : etag)
        switch result {
        case .notModified:
            lastCheckedAt = now()
            if snapshot == nil { throw RegionDataError.unavailable }
            return false
        case .updated(let data, let newETag):
            let decoded = try fetcher.decodeRegion(data)
            snapshot = decoded
            etag = newETag
            lastCheckedAt = now()
            try? cache?.save(region, data: data, etag: newETag, at: now())
            return true
        }
    }

    private func loadDiskIfNeeded() {
        guard !didLoadDisk else { return }
        didLoadDisk = true
        guard snapshot == nil, let cache, let entry = cache.load(region) else { return }
        guard let decoded = try? fetcher.decodeRegion(entry.data) else {
            cache.remove(region)  // 깨진 파일은 지우고 다시 받는다.
            return
        }
        snapshot = decoded
        etag = entry.etag
    }
}

/// `SpotsService`를 지역 데이터 + 기기 계산으로 구현한다. 서버에는 지역 파일 요청과 상세(id)만 간다 — 좌표는 보내지 않는다.
public struct LocalSpotsService: SpotsService {
    private let repository: RegionSpotsRepository
    private let detail: (any SpotDetailFetching)?
    private let now: @Sendable () -> Date

    public init(
        repository: RegionSpotsRepository, detail: (any SpotDetailFetching)?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.detail = detail
        self.now = now
    }

    public func spots(_ query: SpotQuery) async throws -> SpotPage {
        let snapshot = try await repository.current()
        return SpotQueryEngine.nearby(snapshot.spots, query: query, now: now())
    }

    public func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap {
        let snapshot = try await repository.current()
        return SpotQueryEngine.inBounds(snapshot.spots, query: query, now: now())
    }

    /// 지역 데이터에 있으면 그것(끝남은 기기 시각으로 다시 계산), 없으면 `GET /v1/spots/{id}`.
    public func spot(id: String) async throws -> Spot {
        if let local = await repository.cached()?.spot(id: id) {
            return local.copy(isEnded: local.hasEnded(at: now()))
        }
        guard let detail else { throw SpotsServiceError.notFound }
        return try await detail.spot(id: id)
    }

    public func refreshData(force: Bool) async throws -> Bool {
        try await repository.refresh(force: force)
    }
}
