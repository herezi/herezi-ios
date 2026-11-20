import Domain
import FeatureNearby
import Foundation
import Testing

@MainActor
struct MapViewModelTests {
    private let cityHall = Coordinate.seoulCityHall
    private var elsewhere: CoordinateBounds {
        CoordinateBounds(
            southWest: Coordinate(latitude: 37.575, longitude: 126.97),
            northEast: Coordinate(latitude: 37.585, longitude: 126.99))
    }

    private func makeViewModel(
        service: any SpotsService = FakeSpotsService(spots: TestData.spots),
        location: any LocationProviding = FixedLocationProvider(), naming: (any PlaceNaming)? = nil
    ) -> MapViewModel {
        MapViewModel(service: service, location: location, naming: naming)
    }

    @Test func 첫_진입은_내_위치_반경_3km를_조회하고_카메라를_옮긴다() async throws {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service, naming: StubNaming("중구 태평로1가"))
        await viewModel.start()

        let query = try #require(await service.mapQueries.first)
        #expect(query.bounds == .around(cityHall, radiusMeters: 3_000))
        #expect(viewModel.camera?.center == cityHall)
        #expect(viewModel.camera?.zoom == 14)
        #expect(viewModel.state == .loaded)
        #expect(viewModel.sheet == .collapsed)
        #expect(viewModel.sheetTitle == "이 지역 볼거리 \(viewModel.spots.count)개")
        #expect(viewModel.placeName == "중구 태평로1가")
        #expect(!viewModel.showsSearchHere)
    }

    @Test func 위치가_없으면_서울시청_기준() async {
        let viewModel = makeViewModel(location: DeniedLocationProvider(), naming: StubNaming("중구 태평로1가"))
        await viewModel.start()
        #expect(viewModel.isUsingFallbackLocation)
        #expect(viewModel.camera?.center == cityHall)
        #expect(viewModel.placeName == "서울시청 주변")
        #expect(viewModel.distance(to: viewModel.spots[0]) == nil)
        #expect(await !viewModel.moveToMyLocation())
    }

    @Test func 사용자가_지도를_움직이면_다시_찾기가_보이고_탭하면_보이는_영역으로_조회() async throws {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service, naming: StubNaming("종로구 사간동"))
        await viewModel.start()

        // 프로그램이 옮긴 카메라(첫 이동)는 알약을 띄우지 않는다.
        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: false)
        #expect(!viewModel.showsSearchHere)
        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: true)
        #expect(viewModel.showsSearchHere)
        #expect(await service.mapQueries.count == 1)  // 자동 재조회 안 함

        await viewModel.searchThisArea()
        #expect(!viewModel.showsSearchHere)
        #expect(await service.mapQueries.last?.bounds == elsewhere)
        #expect(viewModel.hasSearchedElsewhere)
        #expect(viewModel.placeName == "종로구 사간동")
        // 국립현대미술관(37.5796, 126.98)만 그 영역 안.
        #expect(viewModel.spots.map(\.id) == ["sample-3"])

        // 같은 영역에서 다시 멈추면 알약이 다시 뜨지 않는다.
        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: true)
        #expect(!viewModel.showsSearchHere)
    }

    @Test func 필터를_바꾸면_보이는_영역으로_바로_재조회() async throws {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)
        await viewModel.start()
        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: false)

        await viewModel.toggle(.performance)
        let query = try #require(await service.mapQueries.last)
        #expect(query.categories == [.performance])
        #expect(query.bounds == elsewhere)
        await viewModel.setFreeOnly(true)
        await viewModel.setWhen(.weekend)
        let last = try #require(await service.mapQueries.last)
        #expect(last.freeOnly && last.when == .weekend)
        #expect(await service.mapQueries.count == 4)
    }

    @Test func 핀_선택은_카드_시트_빈_지도_탭은_해제() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        let spot = viewModel.spots[0]

        viewModel.select(spot.id)
        #expect(viewModel.sheet == .card)
        #expect(viewModel.selectedSpot == spot)

        viewModel.expandSheet()
        #expect(viewModel.sheet == .expanded)
        viewModel.lowerSheet()
        #expect(viewModel.sheet == .card)
        viewModel.deselect()
        #expect(viewModel.sheet == .collapsed)
        #expect(viewModel.selectedSpot == nil)

        viewModel.select("없는-id")
        #expect(viewModel.sheet == .collapsed)
    }

    @Test func 다시_조회해서_선택한_핀이_빠지면_선택_해제() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        viewModel.select("sample-1")
        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: true)
        await viewModel.searchThisArea()
        #expect(viewModel.selectedSpotID == nil)
        #expect(viewModel.sheet == .collapsed)
    }

    @Test func 펼친_목록은_조회_영역_중심에서_가까운_순() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        let center = cityHall
        let distances = viewModel.listSpots.map { center.distance(to: $0.coordinate) }
        #expect(distances == distances.sorted())
        #expect(
            viewModel.distance(to: viewModel.listSpots[0]) == center.distance(to: viewModel.listSpots[0].coordinate))
    }

    @Test func 빈_결과_문구와_이번_주로_보기() async throws {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: []))
        let viewModel = makeViewModel(service: service)
        await viewModel.start()
        #expect(viewModel.sheetTitle == "이 지역엔 지금 볼거리가 없어요")
        #expect(viewModel.sheetAction == .showWeek)
        await viewModel.perform(.showWeek)
        #expect(viewModel.when == .week)
        #expect(await service.mapQueries.last?.when == .week)
        #expect(viewModel.sheetAction == nil)
    }

    @Test func 오류는_기존_핀을_유지하고_다시_시도() async {
        let toggle = FailingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: toggle)
        await viewModel.start()
        let before = viewModel.spots
        #expect(!before.isEmpty)

        await toggle.setFailing(true)
        await viewModel.retry()
        #expect(viewModel.state == .failed)
        #expect(viewModel.sheetTitle == "불러오지 못했어요")
        #expect(viewModel.sheetAction == .retry)
        #expect(viewModel.spots == before)

        await toggle.setFailing(false)
        await viewModel.perform(.retry)
        #expect(viewModel.state == .loaded)
    }

    @Test func 너무_많으면_영역당_한_번만_토스트() async {
        let many = (0..<5).map { index in
            Spot(
                id: "m\(index)", title: "m\(index)", category: .festival,
                coordinate: Coordinate(latitude: 37.5663 + Double(index) * 0.0001, longitude: 126.9779),
                startsAt: TestData.now, source: "test", fetchedAt: TestData.now)
        }
        let viewModel = makeViewModel(service: LimitedSpotsService(base: FakeSpotsService(spots: many), limit: 2))
        await viewModel.start()
        #expect(viewModel.toastMessage == "볼거리가 많아요. 지도를 확대하면 더 보여요")
        viewModel.toastMessage = nil
        await viewModel.retry()
        #expect(viewModel.toastMessage == nil)
    }

    @Test func 내_위치_버튼은_내_위치로_옮기고_재조회() async throws {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)
        await viewModel.start()
        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: true)
        let firstCamera = try #require(viewModel.camera)

        #expect(await viewModel.moveToMyLocation())
        #expect(viewModel.camera?.id != firstCamera.id)
        #expect(viewModel.isFollowingUser)
        #expect(!viewModel.showsSearchHere)
        #expect(await service.mapQueries.last?.bounds == .around(cityHall, radiusMeters: 3_000))

        viewModel.cameraDidBecomeIdle(bounds: elsewhere, byUser: true)
        #expect(!viewModel.isFollowingUser)
    }

    @Test func 목록에서_넘겨받은_필터를_적용() async throws {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)
        await viewModel.start()
        await viewModel.apply(HomeListFilter(when: .week, categories: [.festival], freeOnly: true))
        #expect(viewModel.currentFilter == HomeListFilter(when: .week, categories: [.festival], freeOnly: true))
        let query = try #require(await service.mapQueries.last)
        #expect(query.when == .week && query.categories == [.festival] && query.freeOnly)
    }
}

/// 고정 위치명을 돌려주는 `PlaceNaming`.
@MainActor
struct StubNaming: PlaceNaming {
    let name: String?

    init(_ name: String?) {
        self.name = name
    }

    func placeName(for coordinate: Coordinate) async -> String? {
        name
    }
}

/// 켜고 끌 수 있는 실패 서비스.
actor FailingSpotsService: SpotsService {
    private let base: FakeSpotsService
    private var failing = false

    init(base: FakeSpotsService) {
        self.base = base
    }

    func setFailing(_ value: Bool) {
        failing = value
    }

    func spots(_ query: SpotQuery) async throws -> SpotPage {
        if failing { throw FakeSpotsService.FakeError.notFound }
        return try await base.spots(query)
    }

    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap {
        if failing { throw FakeSpotsService.FakeError.notFound }
        return try await base.spotsInBounds(query)
    }

    func spot(id: String) async throws -> Spot {
        try await base.spot(id: id)
    }

    func reverseGeocode(_ coordinate: Coordinate) async throws -> String {
        try await base.reverseGeocode(coordinate)
    }
}

/// 지도 조회의 `limit`을 작게 바꿔 `truncated`를 흉내 낸다.
struct LimitedSpotsService: SpotsService {
    let base: FakeSpotsService
    let limit: Int

    func spots(_ query: SpotQuery) async throws -> SpotPage {
        try await base.spots(query)
    }

    func spotsInBounds(_ query: SpotMapQuery) async throws -> SpotMap {
        var limited = query
        limited.limit = limit
        return try await base.spotsInBounds(limited)
    }

    func spot(id: String) async throws -> Spot {
        try await base.spot(id: id)
    }

    func reverseGeocode(_ coordinate: Coordinate) async throws -> String {
        try await base.reverseGeocode(coordinate)
    }
}
