import Domain
import Foundation
import Observation

/// 홈(S1) 상태·로직. 위치를 찾고(5초, 실패하면 서울시청) 기기에 받아 둔 지역 데이터에서 `when=week`·3km·가까운 100개를
/// 골라(`SpotsService` — 좌표는 서버로 가지 않는다, #37) `HomeFeed.build`로 섹션을 나눈다.
@MainActor
@Observable
public final class HomeViewModel {
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed
    }

    /// 홈 조회 파라미터 (S1 "데이터").
    public static let radiusMeters = 3_000
    public static let limit = 100

    public private(set) var state: LoadState = .idle
    public private(set) var feed: HomeFeed?
    public private(set) var coordinate: Coordinate?
    public private(set) var isUsingFallbackLocation = false
    /// "중구 태평로1가" / 위치 거부 "서울시청 주변" / 역지오코딩 실패 "내 주변". 찾는 중이면 nil.
    public private(set) var placeName: String?
    public var toastMessage: String?
    /// 마지막 조회 시각 (백그라운드 15분 규칙).
    public private(set) var loadedAt: Date?

    private let service: any SpotsService
    private let location: any LocationProviding
    private let naming: any PlaceNaming
    private let saved: SavedLibrary
    private let now: @Sendable () -> Date

    public init(
        service: any SpotsService, location: any LocationProviding, naming: any PlaceNaming, saved: SavedLibrary,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.location = location
        self.naming = naming
        self.saved = saved
        self.now = now
    }

    public var headline: (line1: String, line2: String)? {
        guard let feed, !feed.isEmpty else { return nil }
        return feed.headline(usesFallbackLocation: isUsingFallbackLocation)
    }

    /// 기준 시각 고정용 시계 (섹션을 만든 순간).
    public private(set) var clock = HomeClock(now: Date())

    /// 첫 진입: 기기 데이터가 있으면 그것으로 먼저 그리고, 지역 파일을 확인한다(앱 실행 후 첫 확인은 항상, 대부분 304).
    public func start() async {
        await load(forceSync: false)
    }

    /// 당겨서 새로고침·다시 시도·위치 허용 직후: 위치를 다시 확인하고 지역 파일을 확인(`If-None-Match`)한 뒤 다시 계산.
    public func reload() async {
        await load(forceSync: true)
    }

    private func load(forceSync: Bool) async {
        let hadData = feed != nil
        if !hadData { state = .loading }
        let origin = await resolveLocation()
        // 1) 기기 데이터로 먼저 그린다(없으면 이때 처음 받는다).
        var shown = await rebuild(origin: origin)
        // 2) 지역 파일 확인. 바뀌었으면(또는 1에서 못 그렸으면) 다시 계산.
        var syncFailed = false
        do {
            if try await service.refreshData(force: forceSync) || !shown {
                shown = await rebuild(origin: origin)
            }
        } catch {
            syncFailed = true
        }
        if shown {
            state = .loaded
            // 기기 데이터로 그렸지만 최신을 못 받음 — 사용자가 새로고침했을 때만 알린다(S1 '새로고침 오류').
            if syncFailed && forceSync && hadData { toastMessage = "최신 정보를 불러오지 못했어요" }
        } else if hadData {
            state = .loaded
            toastMessage = "최신 정보를 불러오지 못했어요"
        } else {
            state = .failed
        }
    }

    /// 지금 위치·데이터로 섹션을 다시 만든다. 데이터가 없어 못 만들면 false.
    private func rebuild(origin: Coordinate) async -> Bool {
        do {
            let page = try await service.spots(
                SpotQuery(coordinate: origin, radiusMeters: Self.radiusMeters, when: .week, limit: Self.limit))
            let current = now()
            clock = HomeClock(now: current)
            feed = HomeFeed.build(spots: page.items, now: current, hasMore: page.nextCursor != nil)
            loadedAt = current
            return true
        } catch {
            return false
        }
    }

    /// 포그라운드 복귀: 지역 파일은 마지막 확인이 1시간(서버 max-age) 넘었을 때만 확인하고, 데이터가 바뀌었거나
    /// 마지막 계산이 15분 넘었으면 같은 위치로 다시 계산한다(위치 재조회는 하지 않음 — S1 인터랙션).
    public func reloadIfStale() async {
        guard state == .loaded, let coordinate else { return }
        let changed = (try? await service.refreshData(force: false)) ?? false
        let stale = loadedAt.map { now().timeIntervalSince($0) > 15 * 60 } ?? true
        if changed || stale { _ = await rebuild(origin: coordinate) }
    }

    private func resolveLocation() async -> Coordinate {
        do {
            let resolved = try await location.currentCoordinate()
            coordinate = resolved
            isUsingFallbackLocation = false
            placeName = await naming.placeName(for: resolved) ?? "내 주변"
            return resolved
        } catch {
            coordinate = .seoulCityHall
            isUsingFallbackLocation = true
            placeName = "서울시청 주변"
            return .seoulCityHall
        }
    }

    // MARK: 저장 (히어로 버튼, 가로 카드 길게 누르기)

    public func isSaved(_ spot: Spot) -> Bool { saved.isSaved(spot.id) }

    /// 저장/취소 (계정). 로그인 전이면 로그인 시트를 띄우고, 로그인 뒤 저장한다(S7).
    public func toggleSave(_ spot: Spot) async {
        if let message = await saved.toggle(spot) { toastMessage = message }
    }

    // MARK: 카드 문구

    /// 가로 카드 배지: '오늘 끝나요'면 "오늘 18:00까지", 무료 섹션이 아니고 무료면 `무료`.
    public func tileBadge(_ spot: Spot, in section: HomeFeed.SectionKind) -> TileBadge? {
        if section == .endingToday, let end = spot.endsAt { return .text(clock.endsTodayText(end)) }
        if section != .free, spot.isFree == true { return .free }
        return nil
    }

    public enum TileBadge: Equatable, Sendable {
        case free
        case text(String)
    }
}
