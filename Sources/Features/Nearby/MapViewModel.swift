import Domain
import Foundation
import Observation

/// 기간·카테고리·무료 필터를 가진 화면 (S1b 목록, S2 지도). 필터 줄 UI가 이것만 본다.
@MainActor
public protocol SpotFilterControlling: AnyObject {
    var when: WhenFilter { get }
    var freeOnly: Bool { get }
    var selectedCategories: Set<SpotCategory> { get }
    func setWhen(_ newValue: WhenFilter) async
    func setFreeOnly(_ newValue: Bool) async
    func clearCategories() async
    func toggle(_ category: SpotCategory) async
}

extension SpotFilterControlling {
    public func isSelected(_ category: SpotCategory) -> Bool {
        selectedCategories.contains(category)
    }
}

/// S2 지도 화면의 상태·로직 (herezi-api docs/design/screens/S2-map.md). 지도 SDK를 모른다 — 단위 테스트 가능.
///
/// - 첫 진입: 내 위치(없으면 서울시청) 중심, 반경 3km 영역을 `GET /v1/spots/map`으로 조회.
/// - 지도 이동: 자동 재조회하지 않고 "이 지역에서 다시 찾기"를 띄운다. 탭하면 보이는 영역으로 조회.
/// - 필터 변경: 지금 보이는 영역으로 바로 재조회.
/// - 시트: 접힘(요약 한 줄) / 카드(선택한 핀) / 펼침(목록).
@MainActor
@Observable
public final class MapViewModel: SpotFilterControlling {
    public enum LoadState: Equatable, Sendable {
        case idle, loading, loaded, failed
    }

    public enum SheetDetent: Equatable, Sendable {
        case collapsed, card, expanded
    }

    /// 시트 접힘 줄의 글자 버튼.
    public enum SheetAction: Equatable, Sendable {
        case showWeek, retry

        public var title: String {
            switch self {
            case .showWeek: "이번 주로 보기"
            case .retry: "다시 시도"
            }
        }
    }

    public private(set) var when: WhenFilter
    public private(set) var selectedCategories: Set<SpotCategory>
    public private(set) var freeOnly: Bool

    public private(set) var spots: [Spot] = []
    public private(set) var state: LoadState = .idle
    public private(set) var selectedSpotID: String?
    public var sheet: SheetDetent
    /// "이 지역에서 다시 찾기" 알약. 사용자가 지도를 움직였을 때만.
    public private(set) var showsSearchHere = false
    /// "다시 찾기"로 조회하는 중 (알약 아이콘이 돈다).
    public private(set) var isSearchingHere = false
    /// 내 위치로 이동한 뒤 사용자가 지도를 움직이기 전까지 (아이콘 `location.fill`).
    public private(set) var isFollowingUser = false
    /// 지도에 보낼 카메라 이동 요청.
    public private(set) var camera: MapCameraTarget?
    public private(set) var placeName: String?
    public private(set) var isUsingFallbackLocation = false
    /// 사용자 위치(거리 표시용). 위치를 모르면 nil.
    public private(set) var userCoordinate: Coordinate?
    public var toastMessage: String?

    /// 마지막으로 조회한 영역 / 지도가 마지막으로 알려준 보이는 영역.
    public private(set) var searchedBounds: CoordinateBounds?
    public private(set) var visibleBounds: CoordinateBounds?
    /// "다시 찾기"·내 위치 이동 등으로 처음과 다른 곳을 조회했는지. "목록으로 보기"가 지도 중심 기준이 된다.
    public private(set) var hasSearchedElsewhere = false

    private var truncatedToastBounds: CoordinateBounds?
    private var debugTreatNextIdleAsUser = false
    private let service: any SpotsService
    private let location: any LocationProviding
    private let naming: (any PlaceNaming)?

    /// 첫 진입 반경 (S2: 3km가 보이는 줌).
    public static let initialRadiusMeters = 3_000.0

    public init(
        service: any SpotsService, location: any LocationProviding, naming: (any PlaceNaming)? = nil,
        filter: HomeListFilter = HomeListFilter(), startsExpanded: Bool = false
    ) {
        self.service = service
        self.location = location
        self.naming = naming
        self.when = filter.when
        self.selectedCategories = filter.categories
        self.freeOnly = filter.freeOnly
        self.sheet = startsExpanded ? .expanded : .collapsed
    }

    // MARK: - 시트

    public var selectedSpot: Spot? {
        guard let selectedSpotID else { return nil }
        return spots.first { $0.id == selectedSpotID }
    }

    /// 접힘 줄 문구.
    public var sheetTitle: String {
        switch state {
        case .idle, .loading: "찾는 중…"
        case .failed: "불러오지 못했어요"
        case .loaded: spots.isEmpty ? "이 지역엔 지금 볼거리가 없어요" : "이 지역 볼거리 \(spots.count)개"
        }
    }

    public var sheetAction: SheetAction? {
        switch state {
        case .failed: .retry
        case .loaded where spots.isEmpty && when != .week: .showWeek
        default: nil
        }
    }

    /// 펼친 시트의 목록: 조회 영역 중심에서 가까운 순.
    public var listSpots: [Spot] {
        guard let center = searchedBounds?.center else { return spots }
        return spots.sorted { center.distance(to: $0.coordinate) < center.distance(to: $1.coordinate) }
    }

    /// 카드의 거리: 내 위치를 알 때만 (서울시청 기준이면 장소명).
    public func distance(to spot: Spot) -> Int? {
        guard let userCoordinate, !isUsingFallbackLocation else { return nil }
        return userCoordinate.distance(to: spot.coordinate)
    }

    public func select(_ spotID: String) {
        guard spots.contains(where: { $0.id == spotID }) else { return }
        selectedSpotID = spotID
        sheet = .card
    }

    /// 빈 지도 탭 / 시트 내리기.
    public func deselect() {
        selectedSpotID = nil
        if sheet == .card { sheet = .collapsed }
    }

    public func expandSheet() {
        sheet = .expanded
    }

    /// 시트를 한 단계 내린다: 펼침 → (선택 있으면 카드, 없으면 접힘), 카드 → 접힘(선택 해제).
    public func lowerSheet() {
        switch sheet {
        case .expanded: sheet = selectedSpot == nil ? .collapsed : .card
        case .card: deselect()
        case .collapsed: break
        }
    }

    // MARK: - 지도 이벤트

    /// 지도 카메라가 멈췄을 때. `byUser`면 제스처로 움직인 것.
    public func cameraDidBecomeIdle(bounds: CoordinateBounds, byUser: Bool) {
        visibleBounds = bounds
        let byUser = byUser || debugTreatNextIdleAsUser
        debugTreatNextIdleAsUser = false
        guard byUser else { return }
        isFollowingUser = false
        if bounds != searchedBounds { showsSearchHere = true }
    }

    #if DEBUG
        /// 스크린샷·QA용: 사용자가 지도를 끌어 옮긴 것처럼 카메라를 옮긴다(다음 멈춤을 사용자 이동으로 본다).
        public func debugPan(to center: Coordinate) {
            debugTreatNextIdleAsUser = true
            camera = MapCameraTarget(center: center, zoom: camera?.zoom ?? MapCameraTarget.defaultZoom)
        }
    #endif

    // MARK: - 조회

    /// 첫 진입. 이미 불러왔으면 아무것도 안 한다.
    public func start() async {
        guard state == .idle else { return }
        let origin = await resolveOrigin()
        camera = MapCameraTarget(center: origin)
        if isUsingFallbackLocation {
            placeName = "서울시청 주변"
        } else if let naming {
            placeName = await naming.placeName(for: origin) ?? "내 주변"
        } else {
            placeName = "내 주변"
        }
        await search(.around(origin, radiusMeters: Self.initialRadiusMeters))
    }

    /// "이 지역에서 다시 찾기".
    public func searchThisArea() async {
        guard let bounds = visibleBounds else { return }
        showsSearchHere = false
        hasSearchedElsewhere = true
        isSearchingHere = true
        await search(bounds)
        isSearchingHere = false
        await updatePlaceName(for: bounds.center)
    }

    /// 내 위치 버튼. 위치를 쓸 수 없으면 false — 화면이 배너의 `설정` 동작을 한다.
    @discardableResult
    public func moveToMyLocation() async -> Bool {
        guard let coordinate = try? await location.currentCoordinate() else { return false }
        userCoordinate = coordinate
        isUsingFallbackLocation = false
        camera = MapCameraTarget(center: coordinate)
        isFollowingUser = true
        showsSearchHere = false
        let bounds = CoordinateBounds.around(coordinate, radiusMeters: Self.initialRadiusMeters)
        visibleBounds = nil
        await search(bounds)
        await updatePlaceName(for: coordinate)
        return true
    }

    /// 포그라운드 복귀: 지역 파일을 확인하고(마지막 확인이 1시간 넘었을 때만) 같은 영역을 기기 데이터로 다시 계산한다.
    /// 기기 계산이라 바로 끝나므로 로딩 표시("찾는 중…")·카메라 이동 없이 핀만 바꾼다.
    public func refreshOnForeground() async {
        guard state == .loaded, let bounds = searchedBounds else { return }
        _ = try? await service.refreshData(force: false)
        guard searchedBounds == bounds,
            let result = try? await service.spotsInBounds(
                SpotMapQuery(bounds: bounds, categories: selectedCategories, when: when, freeOnly: freeOnly)),
            searchedBounds == bounds
        else { return }
        spots = result.items
        if let selectedSpotID, !spots.contains(where: { $0.id == selectedSpotID }) { deselect() }
    }

    public func retry() async {
        await search(searchedBounds ?? visibleBounds ?? .around(.seoulCityHall, radiusMeters: Self.initialRadiusMeters))
    }

    public func perform(_ action: SheetAction) async {
        switch action {
        case .retry: await retry()
        case .showWeek: await setWhen(.week)
        }
    }

    // MARK: - 필터 (바뀌면 지금 보이는 영역으로 바로 재조회)

    public var currentFilter: HomeListFilter {
        HomeListFilter(when: when, categories: selectedCategories, freeOnly: freeOnly)
    }

    public func apply(_ filter: HomeListFilter) async {
        guard filter != currentFilter else { return }
        when = filter.when
        selectedCategories = filter.categories
        freeOnly = filter.freeOnly
        await refilter()
    }

    public func setWhen(_ newValue: WhenFilter) async {
        guard newValue != when else { return }
        when = newValue
        await refilter()
    }

    public func setFreeOnly(_ newValue: Bool) async {
        guard newValue != freeOnly else { return }
        freeOnly = newValue
        await refilter()
    }

    public func clearCategories() async {
        guard !selectedCategories.isEmpty else { return }
        selectedCategories = []
        await refilter()
    }

    public func toggle(_ category: SpotCategory) async {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        await refilter()
    }

    private func refilter() async {
        guard state != .idle else { return }  // 첫 진입 전이면 start()가 이 필터로 조회한다.
        if let visibleBounds, visibleBounds != searchedBounds {
            showsSearchHere = false
            await search(visibleBounds)
        } else {
            await retry()
        }
    }

    private func search(_ bounds: CoordinateBounds) async {
        state = .loading
        searchedBounds = bounds
        do {
            let result = try await service.spotsInBounds(
                SpotMapQuery(bounds: bounds, categories: selectedCategories, when: when, freeOnly: freeOnly))
            guard searchedBounds == bounds else { return }  // 그새 다른 영역을 조회했다.
            spots = result.items
            state = .loaded
            if let selectedSpotID, !spots.contains(where: { $0.id == selectedSpotID }) { deselect() }
            if result.truncated, truncatedToastBounds != bounds {
                truncatedToastBounds = bounds
                toastMessage = "볼거리가 많아요. 지도를 확대하면 더 보여요"
            }
        } catch {
            guard searchedBounds == bounds else { return }
            state = .failed  // 기존 핀은 유지한다.
        }
    }

    private func resolveOrigin() async -> Coordinate {
        do {
            let coordinate = try await location.currentCoordinate()
            userCoordinate = coordinate
            return coordinate
        } catch {
            isUsingFallbackLocation = true
            return .seoulCityHall
        }
    }

    private func updatePlaceName(for coordinate: Coordinate) async {
        guard let naming, let name = await naming.placeName(for: coordinate) else { return }
        placeName = name
    }
}
