import Domain
import FeatureNearby
import Testing

@MainActor
struct NearbyViewModelTests {
    @Test func 처음_로드하면_가까운_순서로_보여준다() async {
        let viewModel = NearbyViewModel(
            service: FakeSpotsService(spots: TestData.spots), location: FixedLocationProvider())

        await viewModel.reload()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.visibleSpots.map(\.id) == ["sample-2", "sample-1", "sample-4", "sample-5", "sample-3"])
        #expect(viewModel.isUsingFallbackLocation == false)
    }

    @Test func 카테고리를_고르면_쿼리에_담아_다시_불러온다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = NearbyViewModel(service: service, location: FixedLocationProvider())

        await viewModel.toggle(.festival)

        let last = await service.queries.last
        #expect(last?.categories == [.festival])
        #expect(viewModel.visibleSpots.map(\.id) == ["sample-1"])
        #expect(viewModel.isSelected(.festival))

        await viewModel.toggle(.festival)
        #expect(viewModel.selectedCategories.isEmpty)
        #expect(viewModel.visibleSpots.count == TestData.spots.count)
    }

    @Test func 무료만_필터는_free_쿼리로_전달되고_무료_항목만_남긴다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = NearbyViewModel(service: service, location: FixedLocationProvider())

        await viewModel.setFreeOnly(true)

        let last = await service.queries.last
        #expect(last?.freeOnly == true)
        #expect(viewModel.visibleSpots.allSatisfy { $0.isFree == true })
        #expect(viewModel.visibleSpots.map(\.id) == ["sample-1", "sample-4"])
    }

    @Test func 기간을_바꾸면_when_쿼리가_바뀐다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = NearbyViewModel(service: service, location: FixedLocationProvider())

        await viewModel.setWhen(.weekend)
        await viewModel.setWhen(.weekend)  // 같은 값이면 다시 부르지 않는다

        let queries = await service.queries
        #expect(queries.count == 1)
        #expect(queries.first?.when == .weekend)
    }

    @Test func 위치를_모르면_서울시청_기준으로_조회한다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = NearbyViewModel(service: service, location: DeniedLocationProvider())

        await viewModel.reload()

        let last = await service.queries.last
        #expect(last?.coordinate == .seoulCityHall)
        #expect(viewModel.isUsingFallbackLocation)
        #expect(viewModel.state == .loaded)
    }

    @Test func 서비스가_실패하면_에러_상태가_된다() async {
        let viewModel = NearbyViewModel(
            service: FakeSpotsService(failure: FakeSpotsService.FakeError.notFound),
            location: FixedLocationProvider())

        await viewModel.reload()

        guard case .failed = viewModel.state else {
            Issue.record("expected .failed, got \(viewModel.state)")
            return
        }
        #expect(viewModel.spots.isEmpty)
    }

    @Test func 거리를_모르는_항목은_맨_뒤로_간다() {
        let near = TestData.spots[0]
        let unknown = Spot(
            id: "x", title: "거리 모름", category: .festival, coordinate: .seoulCityHall,
            startsAt: TestData.now, source: "test")

        let sorted = NearbyViewModel.filter([unknown, near], categories: [])

        #expect(sorted.map(\.id) == [near.id, "x"])
    }
}
