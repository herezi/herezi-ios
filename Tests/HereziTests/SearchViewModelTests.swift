import Domain
import FeatureSearch
import Foundation
import Testing

@MainActor
struct SearchViewModelTests {
    private func makeViewModel(
        service: any SpotsService = FakeSpotsService(spots: TestData.spots),
        recents: RecentSearchesStore = RecentSearchesStore(defaults: freshDefaults())
    ) -> SearchViewModel {
        SearchViewModel(service: service, recents: recents, origin: .seoulCityHall)
    }

    @Test func 검색어를_q로_보내고_반경_20km에서_찾는다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)
        viewModel.text = " 빛초롱 "

        await viewModel.submit()

        let query = await service.queries.last
        #expect(query?.normalizedKeyword == "빛초롱")
        #expect(query?.radiusMeters == 20_000)
        #expect(query?.coordinate == .seoulCityHall)
        #expect(viewModel.phase == .results([TestData.spots[0]]))
        #expect(viewModel.resultSummary == "'빛초롱' 검색 결과 1개")
        #expect(viewModel.recents == ["빛초롱"])
    }

    @Test func 두_글자_미만이면_검색하지_않는다() async {
        let service = RecordingSpotsService(base: FakeSpotsService(spots: TestData.spots))
        let viewModel = makeViewModel(service: service)
        viewModel.text = "빛 "

        await viewModel.submit()

        #expect(await service.queries.isEmpty)
        #expect(viewModel.toastMessage == "두 글자 이상 입력해 주세요")
        #expect(viewModel.phase == .recent)
    }

    @Test func 결과가_없으면_빈_상태() async {
        let viewModel = makeViewModel()
        viewModel.text = "국화"  // 끝난 항목만 맞음 → 결과 없음

        await viewModel.submit()

        #expect(viewModel.phase == .empty)
        #expect(viewModel.emptyTitle == "'국화'에 맞는 볼거리가 없어요")
    }

    @Test func 오류면_다시_시도할_수_있다() async {
        let viewModel = makeViewModel(
            service: FakeSpotsService(spots: TestData.spots, failure: FakeSpotsService.FakeError.notFound))
        viewModel.text = "광화문"
        await viewModel.submit()
        #expect(viewModel.phase == .failed)
    }

    @Test func 최근_검색어는_최신순_중복없이_10개까지() async {
        let recents = RecentSearchesStore(defaults: freshDefaults())
        let viewModel = makeViewModel(recents: recents)
        for index in 0..<12 {
            viewModel.text = "검색\(index)"
            await viewModel.submit()
        }
        await viewModel.selectRecent("검색5")

        #expect(viewModel.recents.count == 10)
        #expect(viewModel.recents.first == "검색5")
        #expect(viewModel.recents.filter { $0 == "검색5" }.count == 1)
        #expect(!viewModel.recents.contains("검색0"))

        viewModel.removeRecent("검색5")
        #expect(!viewModel.recents.contains("검색5"))
        viewModel.clearRecents()
        #expect(viewModel.recents.isEmpty)
    }

    @Test func 입력을_지우면_최근_검색으로_돌아간다() async {
        let viewModel = makeViewModel()
        viewModel.text = "광화문"
        await viewModel.submit()
        viewModel.clearText()
        #expect(viewModel.phase == .recent)
        #expect(viewModel.text.isEmpty)
    }
}
