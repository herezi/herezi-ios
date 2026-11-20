import Domain
import Foundation
import Observation

/// 홈(S1) 상태·로직. 위치를 찾고(5초, 실패하면 서울시청) `when=week&limit=100`을 한 번 불러
/// `HomeFeed.build`로 섹션을 나눈다.
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
    private let saved: SavedSpotsStore
    private let now: @Sendable () -> Date

    public init(
        service: any SpotsService, location: any LocationProviding, naming: any PlaceNaming, saved: SavedSpotsStore,
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

    /// 위치를 다시 확인하고 재조회한다(당겨서 새로고침도 같음).
    public func reload() async {
        let hadData = feed != nil
        if !hadData { state = .loading }
        let origin = await resolveLocation()
        do {
            let page = try await service.spots(
                SpotQuery(coordinate: origin, radiusMeters: Self.radiusMeters, when: .week, limit: Self.limit))
            let current = now()
            clock = HomeClock(now: current)
            feed = HomeFeed.build(spots: page.items, now: current, hasMore: page.nextCursor != nil)
            loadedAt = current
            state = .loaded
        } catch {
            if hadData {
                state = .loaded
                toastMessage = "최신 정보를 불러오지 못했어요"
            } else {
                state = .failed
            }
        }
    }

    /// 백그라운드에서 15분 넘게 있다 돌아오면 재조회.
    public func reloadIfStale() async {
        guard let loadedAt, now().timeIntervalSince(loadedAt) > 15 * 60 else { return }
        await reload()
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

    public func toggleSave(_ spot: Spot) {
        if saved.isSaved(spot.id) {
            saved.remove(ids: [spot.id])
            toastMessage = "저장을 취소했어요"
        } else {
            saved.save(spot, at: now())
            toastMessage = "저장했어요"
        }
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
