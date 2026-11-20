import Domain
import Foundation
import Observation

/// State + logic for the Nearby screen. UI-free so it is unit-testable (see NearbyViewModelTests).
@MainActor
@Observable
public final class NearbyViewModel: SpotFilterControlling {
    public enum DisplayMode: String, CaseIterable, Sendable {
        case list
        case map

        public var displayName: String {
            switch self {
            case .list: "목록"
            case .map: "지도"
            }
        }
    }

    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public var mode: DisplayMode = .list
    public private(set) var selectedCategories: Set<SpotCategory> = []
    public private(set) var when: WhenFilter = .now
    /// "무료만" 필터. 서버에 `free=true`로 전달된다.
    public private(set) var freeOnly = false
    public private(set) var spots: [Spot] = []
    public private(set) var state: LoadState = .idle
    public private(set) var coordinate: Coordinate?
    /// True when location was unavailable and we fell back to 서울시청.
    public private(set) var isUsingFallbackLocation = false

    /// 다음 페이지 커서. 있으면 "N개 이상".
    public private(set) var nextCursor: String?
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreFailed = false

    private let service: any SpotsService
    private let location: any LocationProviding

    /// - Parameters:
    ///   - filter: 시작 필터 (홈의 카테고리·전체 보기에서 넘긴다).
    ///   - origin: 기준 위치를 이미 알면 넘긴다(홈이 찾은 위치). nil이면 직접 찾는다.
    public init(
        service: any SpotsService, location: any LocationProviding, filter: HomeListFilter = HomeListFilter(),
        origin: Coordinate? = nil, isUsingFallbackLocation: Bool = false
    ) {
        self.service = service
        self.location = location
        self.when = filter.when
        self.selectedCategories = filter.categories
        self.freeOnly = filter.freeOnly
        self.coordinate = origin
        self.isUsingFallbackLocation = origin != nil && isUsingFallbackLocation
    }

    /// 반경 (S1b: 3km).
    public static let radiusMeters = 3_000

    /// "3km 안에 24개" / 다음 페이지가 있으면 "3km 안에 30개 이상".
    public var resultSummary: String {
        "\(Self.radiusMeters / 1000)km 안에 \(visibleSpots.count)개\(nextCursor == nil ? "" : " 이상")"
    }

    /// 카테고리·무료·기간 중 하나라도 기본값(지금·전체·무료 끔)이 아닌지.
    public var hasActiveFilter: Bool {
        !selectedCategories.isEmpty || freeOnly || when != .now
    }

    /// 빈 상태 "필터 초기화": 지금·전체·무료 끔.
    public func resetFilters() async {
        selectedCategories = []
        freeOnly = false
        when = .now
        await reload()
    }

    /// 다른 화면(목록 → 지도)에서 필터를 넘겨받는다.
    public func apply(_ filter: HomeListFilter) async {
        guard filter != currentFilter else { return }
        when = filter.when
        selectedCategories = filter.categories
        freeOnly = filter.freeOnly
        await reload()
    }

    public var currentFilter: HomeListFilter {
        HomeListFilter(when: when, categories: selectedCategories, freeOnly: freeOnly)
    }

    /// 목록 끝에서 5개 남았을 때 다음 페이지.
    public func loadMoreIfNeeded(current spot: Spot) async {
        guard let index = visibleSpots.firstIndex(of: spot), index >= visibleSpots.count - 5 else { return }
        await loadMore()
    }

    public func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, let origin = coordinate else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await service.spots(query(origin: origin, cursor: cursor))
            let known = Set(spots.map(\.id))
            spots += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            loadMoreFailed = true
        }
    }

    private func query(origin: Coordinate, cursor: String? = nil) -> SpotQuery {
        SpotQuery(
            coordinate: origin, radiusMeters: Self.radiusMeters, categories: selectedCategories, when: when,
            freeOnly: freeOnly, cursor: cursor)
    }

    /// Spots after client-side category filtering, nearest first. Unknown distance goes last.
    public var visibleSpots: [Spot] {
        Self.filter(spots, categories: selectedCategories, freeOnly: freeOnly)
    }

    /// Pure filter used by `visibleSpots`; exposed for tests.
    public nonisolated static func filter(
        _ spots: [Spot], categories: Set<SpotCategory>, freeOnly: Bool = false
    ) -> [Spot] {
        spots
            .filter { categories.isEmpty || categories.contains($0.category) }
            .filter { !freeOnly || $0.isFree == true }
            .sorted { ($0.distanceMeters ?? .max, $0.title) < ($1.distanceMeters ?? .max, $1.title) }
    }

    public func isSelected(_ category: SpotCategory) -> Bool {
        selectedCategories.contains(category)
    }

    public func toggle(_ category: SpotCategory) async {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        await reload()
    }

    public func clearCategories() async {
        guard !selectedCategories.isEmpty else { return }
        selectedCategories = []
        await reload()
    }

    public func setFreeOnly(_ newValue: Bool) async {
        guard newValue != freeOnly else { return }
        freeOnly = newValue
        await reload()
    }

    public func setWhen(_ newValue: WhenFilter) async {
        guard newValue != when else { return }
        when = newValue
        await reload()
    }

    /// Resolves location once, then fetches spots for the current filters.
    public func reload() async {
        state = .loading
        let origin = await resolveCoordinate()
        do {
            let page = try await service.spots(query(origin: origin))
            spots = page.items
            nextCursor = page.nextCursor
            loadMoreFailed = false
            state = .loaded
        } catch {
            state = .failed("주변 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }

    private func resolveCoordinate() async -> Coordinate {
        if let coordinate { return coordinate }
        do {
            let resolved = try await location.currentCoordinate()
            coordinate = resolved
            return resolved
        } catch {
            isUsingFallbackLocation = true
            coordinate = .seoulCityHall
            return .seoulCityHall
        }
    }
}

/// `LocationProviding` that always returns a fixed coordinate. For previews and tests.
public struct FixedLocationProvider: LocationProviding {
    public let coordinate: Coordinate

    public init(_ coordinate: Coordinate = .seoulCityHall) {
        self.coordinate = coordinate
    }

    public func currentCoordinate() async throws -> Coordinate {
        coordinate
    }
}
