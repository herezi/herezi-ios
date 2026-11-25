import Domain
import Foundation
import Testing

@testable import Networking

/// 지역 파일 해석기(실제 `LiveRegionSpotsSource.decodeRegion`) — 네트워크는 쓰지 않는다.
let regionDecoder = LiveRegionSpotsSource(client: APIClient(baseURL: URL(string: "http://localhost")!))

/// 정해 둔 응답을 차례대로 돌려주고, 받은 `If-None-Match`를 기록하는 지역 파일 소스.
actor ScriptedRegionFetcher: RegionSpotsFetching {
    enum Step: Sendable {
        case body(Data, etag: String)
        case notModified
        case offline
    }

    struct Offline: Error {}

    private var steps: [Step]
    private let delay: Duration
    private(set) var sentETags: [String?] = []

    init(_ steps: [Step], delay: Duration = .zero) {
        self.steps = steps
        self.delay = delay
    }

    var callCount: Int { sentETags.count }

    func setSteps(_ steps: [Step]) { self.steps = steps }

    func fetchRegion(_ region: String, ifNoneMatch etag: String?) async throws -> RegionFetchResult {
        sentETags.append(etag)
        if delay > .zero { try await Task.sleep(for: delay) }
        let step = steps.isEmpty ? .offline : steps.removeFirst()
        switch step {
        case .body(let data, let etag): return .updated(data: data, etag: etag)
        case .notModified: return .notModified
        case .offline: throw Offline()
        }
    }

    nonisolated func decodeRegion(_ data: Data) throws -> RegionSnapshot {
        try regionDecoder.decodeRegion(data)
    }
}

/// 테스트마다 새 임시 캐시 폴더.
func tempRegionCache() -> RegionDiskCache {
    RegionDiskCache(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("herezi-region-\(UUID().uuidString)"))
}

/// 움직일 수 있는 시계.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) { value = start }

    var now: Date { lock.withLock { value } }

    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

struct RegionDecodingTests {
    @Test func 지역_파일을_도메인으로_변환한다() throws {
        let snapshot = try regionDecoder.decodeRegion(Fixture.data("region_spots"))

        #expect(snapshot.region == "seoul")
        // 나노초(9자리) 소수점이 있는 generated_at도 읽는다.
        #expect(abs(snapshot.generatedAt.timeIntervalSince1970 - 1_795_568_443.722) < 0.001)
        // 앱이 모르는 카테고리는 버린다.
        #expect(snapshot.spots.map(\.id) == ["cultureinfo:204025", "tourapi:2771234", "seoul_culture:1"])
        let lantern = try #require(snapshot.spot(id: "tourapi:2771234"))
        #expect(lantern.category == .festival)
        #expect(lantern.isFree == true)
        #expect(lantern.coordinate == Coordinate(latitude: 37.5690, longitude: 126.9784))
        #expect(lantern.distanceMeters == nil)
        #expect(snapshot.spot(id: "seoul_culture:1")?.isEnded == true)
        #expect(snapshot.spot(id: "nope") == nil)
    }

    @Test func 깨진_본문은_디코딩_오류() {
        #expect(throws: APIError.self) { try regionDecoder.decodeRegion(Data("{}".utf8)) }
    }

    /// 실데이터 규모(약 2,700건, 1.7MB)의 해석 시간. 숫자는 `make test` 로그에 남긴다.
    @Test func 실데이터_규모_해석이_빠르다() throws {
        let one = """
            {"id":"cultureinfo:%d","title":"늘근도둑이야기 %d","summary":"아트포레스트 1관에서 연극을 관람할 수 있어요. 두 줄짜리 요약이 들어갑니다.",\
            "category":"performance","lat":37.58248538026813,"lng":127.00309074973019,"address":"서울특별시 종로구 대학로 어딘가 %d",\
            "place_name":"아트포레스트 1관","starts_at":"2022-03-04T15:00:00Z","ends_at":"2026-12-31T14:59:59Z",\
            "image_url":"https://www.culture.go.kr/upload/rdf/25/09/show_2025092617561683206.jpg","source":"cultureinfo",\
            "source_url":"https://www.culture.go.kr/x","fetched_at":"2026-11-24T20:03:05.897526Z","is_ended":false}
            """
        let items = (0..<2_700).map { one.replacingOccurrences(of: "%d", with: "\($0)") }.joined(separator: ",")
        let body =
            Data(
                #"{"region":"seoul","generated_at":"2026-11-25T01:00:43.722049638Z","count":2700,"items":["#
                    .utf8) + Data(items.utf8) + Data("]}".utf8)
        let clock = ContinuousClock()
        var snapshot: RegionSnapshot?
        let elapsed = try clock.measure { snapshot = try regionDecoder.decodeRegion(body) }
        print("perf: 지역 파일 해석 \(body.count) B, 2,700건 \(elapsed)")
        #expect(snapshot?.spots.count == 2_700)
        #expect(elapsed < .seconds(3))
    }
}

@Suite struct RegionSpotsRepositoryTests {
    let start = kst(2026, 11, 25, 10)

    func fixture() throws -> Data { try Fixture.data("region_spots") }

    @Test func 첫_실행은_받아서_디스크에_저장하고_다음_실행은_디스크로_바로_그린다() async throws {
        let cache = tempRegionCache()
        let fetcher = ScriptedRegionFetcher([.body(try fixture(), etag: "\"v1\"")])
        let first = RegionSpotsRepository(fetcher: fetcher, cache: cache)
        #expect(await first.cached() == nil)
        #expect(try await first.current().spots.count == 3)
        #expect(await fetcher.sentETags == [nil])

        // 다시 실행(새 저장소): 네트워크 없이 디스크에서.
        let offline = ScriptedRegionFetcher([.offline])
        let second = RegionSpotsRepository(fetcher: offline, cache: cache)
        #expect(await second.cached()?.spots.count == 3)
        #expect(try await second.current().spots.count == 3)
        #expect(await offline.callCount == 0)
    }

    @Test func 갱신은_저장한_ETag로_확인하고_304면_그대로() async throws {
        let cache = tempRegionCache()
        try cache.save("seoul", data: try fixture(), etag: "\"v1\"", at: start)
        let fetcher = ScriptedRegionFetcher([.notModified])
        let repository = RegionSpotsRepository(fetcher: fetcher, cache: cache)

        #expect(try await repository.refresh(force: false) == false)
        #expect(await fetcher.sentETags == ["\"v1\""])
        #expect(await repository.cached()?.spots.count == 3)
    }

    @Test func 실행_후_첫_확인은_항상_하고_이후는_1시간이_지나야_한다() async throws {
        let clock = TestClock(start)
        let cache = tempRegionCache()
        try cache.save("seoul", data: try fixture(), etag: "\"v1\"", at: start.addingTimeInterval(-60))
        let fetcher = ScriptedRegionFetcher([.notModified, .notModified, .notModified])
        let repository = RegionSpotsRepository(fetcher: fetcher, cache: cache, now: { clock.now })

        _ = try await repository.refresh(force: false)  // 실행 직후: 확인
        #expect(await fetcher.callCount == 1)
        clock.advance(30 * 60)
        _ = try await repository.refresh(force: false)  // 30분 뒤 포그라운드: 건너뜀
        #expect(await fetcher.callCount == 1)
        _ = try await repository.refresh(force: true)  // 당겨서 새로고침: 확인
        #expect(await fetcher.callCount == 2)
        clock.advance(61 * 60)
        _ = try await repository.refresh(force: false)  // 1시간 넘음: 확인
        #expect(await fetcher.callCount == 3)
    }

    @Test func 새_데이터를_받으면_true를_주고_디스크도_바꾼다() async throws {
        let cache = tempRegionCache()
        try cache.save("seoul", data: try fixture(), etag: "\"v1\"", at: start)
        let smaller = Data(
            #"{"region":"seoul","generated_at":"2026-11-25T02:00:00Z","count":0,"items":[]}"#.utf8)
        let repository = RegionSpotsRepository(
            fetcher: ScriptedRegionFetcher([.body(smaller, etag: "\"v2\"")]), cache: cache)

        #expect(try await repository.refresh(force: true))
        #expect(await repository.cached()?.spots.isEmpty == true)
        #expect(cache.load("seoul")?.etag == "\"v2\"")
    }

    @Test func 오프라인이어도_마지막_데이터로_동작한다() async throws {
        let cache = tempRegionCache()
        try cache.save("seoul", data: try fixture(), etag: "\"v1\"", at: start)
        let repository = RegionSpotsRepository(fetcher: ScriptedRegionFetcher([.offline]), cache: cache)

        await #expect(throws: ScriptedRegionFetcher.Offline.self) { try await repository.refresh(force: true) }
        #expect(try await repository.current().spots.count == 3)
    }

    @Test func 데이터가_없고_받지도_못하면_던진다() async throws {
        let repository = RegionSpotsRepository(
            fetcher: ScriptedRegionFetcher([.offline]), cache: tempRegionCache())
        await #expect(throws: (any Error).self) { try await repository.current() }
    }

    @Test func 깨진_디스크_파일은_지우고_다시_받는다() async throws {
        let cache = tempRegionCache()
        try cache.save("seoul", data: Data("not json".utf8), etag: "\"bad\"", at: start)
        let fetcher = ScriptedRegionFetcher([.body(try fixture(), etag: "\"v1\"")])
        let repository = RegionSpotsRepository(fetcher: fetcher, cache: cache)

        #expect(try await repository.current().spots.count == 3)
        #expect(await fetcher.sentETags == [nil])  // 깨진 파일의 ETag는 보내지 않는다
    }

    @Test func 동시에_들어온_갱신은_요청_한_번으로_합친다() async throws {
        let fetcher = ScriptedRegionFetcher([.body(try fixture(), etag: "\"v1\"")], delay: .milliseconds(50))
        let repository = RegionSpotsRepository(fetcher: fetcher, cache: nil)

        async let a = repository.current()
        async let b = repository.current()
        async let c = repository.refresh(force: false)
        let results = try await (a.spots.count, b.spots.count, c)
        #expect(results.0 == 3 && results.1 == 3)
        #expect(await fetcher.callCount == 1)
    }
}

/// 상세 요청을 기록하는 원격 상세.
actor RecordingDetail: SpotDetailFetching {
    private(set) var ids: [String] = []
    let result: Spot?

    init(result: Spot?) { self.result = result }

    func spot(id: String) async throws -> Spot {
        ids.append(id)
        guard let result else { throw SpotsServiceError.notFound }
        return result
    }
}

struct LocalSpotsServiceTests {
    let now = kst(2026, 11, 25, 10)

    func service(detail: RecordingDetail? = nil, now: Date? = nil) throws -> LocalSpotsService {
        let cache = tempRegionCache()
        try cache.save("seoul", data: try Fixture.data("region_spots"), etag: "\"v1\"", at: self.now)
        let repository = RegionSpotsRepository(fetcher: ScriptedRegionFetcher([.offline]), cache: cache)
        let fixed = now ?? self.now
        return LocalSpotsService(repository: repository, detail: detail, now: { fixed })
    }

    @Test func 목록과_지도는_기기_데이터로_계산한다() async throws {
        let local = try service()
        let page = try await local.spots(SpotQuery(coordinate: .seoulCityHall, radiusMeters: 20_000))
        #expect(page.items.map(\.id) == ["tourapi:2771234", "cultureinfo:204025"])
        #expect(page.items.first?.distanceMeters == 303)
        let map = try await local.spotsInBounds(
            SpotMapQuery(bounds: .around(.seoulCityHall, radiusMeters: 1_000)))
        #expect(map.items.map(\.id) == ["tourapi:2771234"])
    }

    @Test func 상세는_끝난_항목도_기기_데이터에서_종료로_보인다() async throws {
        let detail = RecordingDetail(result: nil)
        let local = try service(detail: detail)
        let ended = try await local.spot(id: "seoul_culture:1")
        #expect(ended.isEnded)
        #expect(await detail.ids.isEmpty)
    }

    @Test func 상세의_끝남은_기기_시각으로_다시_계산한다() async throws {
        // 파일에선 is_ended=false지만 기기 시각(2027-01-10)으로는 끝났다.
        let local = try service(now: kst(2027, 1, 10))
        #expect(try await local.spot(id: "tourapi:2771234").isEnded)
        let listed = try await local.spots(SpotQuery(coordinate: .seoulCityHall, radiusMeters: 20_000))
        #expect(listed.items.isEmpty)
    }

    @Test func 기기_데이터에_없으면_서버_상세로() async throws {
        let remote = Spot(
            id: "old:1", title: "오래전 항목", category: .nature, coordinate: .seoulCityHall, startsAt: now,
            source: "x", fetchedAt: now, isEnded: true)
        let detail = RecordingDetail(result: remote)
        let local = try service(detail: detail)
        #expect(try await local.spot(id: "old:1") == remote)
        #expect(await detail.ids == ["old:1"])
    }
}
