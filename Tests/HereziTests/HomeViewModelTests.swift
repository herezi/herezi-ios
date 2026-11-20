import Domain
import FeatureHome
import FeatureNearby
import Foundation
import Testing

@MainActor
struct HomeViewModelTests {
    private let now = TestData.now

    private func makeViewModel(
        service: any SpotsService = FakeSpotsService(spots: TestData.spots),
        location: any LocationProviding = FixedLocationProvider(),
        name: String? = "중구 태평로1가", saved: SavedSpotsStore = SavedSpotsStore(defaults: freshDefaults())
    ) -> HomeViewModel {
        let now = self.now
        return HomeViewModel(
            service: service, location: location, naming: FixedPlaceNaming(name: name), saved: saved, now: { now })
    }

    @Test func 홈은_week_limit_100으로_한_번_부른다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)

        await viewModel.reload()

        let queries = await service.queries
        #expect(queries.count == 1)
        #expect(queries.first?.when == .week)
        #expect(queries.first?.limit == 100)
        #expect(queries.first?.radiusMeters == 3_000)
        #expect(viewModel.state == .loaded)
        #expect(viewModel.placeName == "중구 태평로1가")
        #expect(viewModel.feed?.hero?.spot.id == "sample-1")
    }

    @Test func 위치를_모르면_서울시청_주변() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service, location: DeniedLocationProvider())

        await viewModel.reload()

        #expect(await service.queries.first?.coordinate == .seoulCityHall)
        #expect(viewModel.isUsingFallbackLocation)
        #expect(viewModel.placeName == "서울시청 주변")
        #expect(viewModel.headline?.line1 == "서울시청 주변에")
    }

    @Test func 역지오코딩에_실패하면_내_주변() async {
        let viewModel = makeViewModel(name: nil)
        await viewModel.reload()
        #expect(viewModel.placeName == "내 주변")
    }

    @Test func 오류면_오류_상태_이전_데이터가_있으면_토스트() async {
        let failing = makeViewModel(service: FakeSpotsService(failure: FakeSpotsService.FakeError.notFound))
        await failing.reload()
        #expect(failing.state == .failed)

        let service = ToggleFailingService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)
        await viewModel.reload()
        await service.setFailing(true)
        await viewModel.reload()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.toastMessage == "최신 정보를 불러오지 못했어요")
    }

    @Test func 빈_응답이면_빈_상태() async {
        let viewModel = makeViewModel(service: FakeSpotsService(spots: []))
        await viewModel.reload()
        #expect(viewModel.feed?.isEmpty == true)
        #expect(viewModel.headline == nil)
    }

    @Test func 히어로_저장_토글() async {
        let store = SavedSpotsStore(defaults: freshDefaults())
        let viewModel = makeViewModel(saved: store)
        let spot = TestData.spots[0]
        viewModel.toggleSave(spot)
        #expect(viewModel.isSaved(spot))
        #expect(viewModel.toastMessage == "저장했어요")
        viewModel.toggleSave(spot)
        #expect(!store.isSaved(spot.id))
    }

    @Test func 가로_카드_배지() {
        let viewModel = makeViewModel()
        let free = TestData.spots[0]
        #expect(viewModel.tileBadge(free, in: .weekend) == .free)
        #expect(viewModel.tileBadge(free, in: .free) == nil)
    }
}

@MainActor
struct NearbyListViewModelTests {
    @Test func 시작_필터와_기준_위치로_조회한다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = NearbyViewModel(
            service: service, location: DeniedLocationProvider(),
            filter: HomeListFilter(when: .week, categories: [.nature], freeOnly: true),
            origin: Coordinate(latitude: 37.5, longitude: 127), isUsingFallbackLocation: false)

        await viewModel.reload()

        let query = await service.queries.last
        #expect(query?.when == .week)
        #expect(query?.categories == [.nature])
        #expect(query?.freeOnly == true)
        #expect(query?.coordinate == Coordinate(latitude: 37.5, longitude: 127))
        #expect(!viewModel.isUsingFallbackLocation)
        #expect(viewModel.hasActiveFilter)
    }

    @Test func 결과_수_줄과_다음_페이지() async {
        let service = PagedService(pages: [
            SpotPage(items: Array(TestData.listedSpots.prefix(3)), nextCursor: "next"),
            SpotPage(items: Array(TestData.listedSpots.suffix(2))),
        ])
        let viewModel = NearbyViewModel(service: service, location: FixedLocationProvider())

        await viewModel.reload()
        #expect(viewModel.resultSummary == "3km 안에 3개 이상")

        await viewModel.loadMore()
        #expect(viewModel.resultSummary == "3km 안에 5개")
        #expect(await service.cursors == [nil, "next"])
    }

    @Test func 필터_초기화는_지금_전체_무료_끔() async {
        let viewModel = NearbyViewModel(
            service: FakeSpotsService(spots: TestData.spots), location: FixedLocationProvider(),
            filter: HomeListFilter(when: .weekend, categories: [.festival], freeOnly: true))
        await viewModel.resetFilters()
        #expect(viewModel.currentFilter == HomeListFilter())
        #expect(!viewModel.hasActiveFilter)
    }

    @Test func 지도로_필터를_넘긴다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let map = NearbyViewModel(service: service, location: FixedLocationProvider())
        await map.apply(HomeListFilter(when: .weekend))
        #expect(await service.queries.last?.when == .weekend)
    }
}
