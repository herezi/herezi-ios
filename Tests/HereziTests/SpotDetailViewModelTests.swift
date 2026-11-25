import Domain
import FeatureSpotDetail
import Foundation
import Testing

@MainActor
struct SpotDetailViewModelTests {
    private let now = TestData.now
    private var spots: [Spot] { TestData.spots }

    private func makeViewModel(
        id: String, initial: Spot? = nil, service: (any SpotsService)? = nil, saved: SavedLibrary? = nil,
        fallback: Bool = false
    ) -> SpotDetailViewModel {
        let now = self.now
        return SpotDetailViewModel(
            id: id, initial: initial, service: service ?? FakeSpotsService(spots: spots),
            saved: saved ?? makeLibrary(), usesFallbackLocation: fallback,
            now: { now })
    }

    @Test func 목록에서_오면_먼저_그리고_응답으로_갱신하며_거리를_유지한다() async {
        let listed = spots[0]
        let viewModel = makeViewModel(id: listed.id, initial: listed)
        #expect(viewModel.state == .loaded)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.spot?.distanceMeters == 280)
        #expect(viewModel.distanceText == "내 위치에서 280m")
        #expect(viewModel.sourceText == "출처 · 한국관광공사")
        #expect(viewModel.fetchedText == "20분 전 갱신")
        #expect(viewModel.endedNotice == nil)
    }

    @Test func 위치가_없으면_서울시청에서_거리로_보여준다() {
        let viewModel = makeViewModel(id: spots[2].id, initial: spots[2], fallback: true)
        #expect(viewModel.distanceText == "서울시청에서 1.5km")
    }

    @Test func 링크로_오면_로딩부터_시작한다() async {
        let viewModel = makeViewModel(id: "sample-3")
        #expect(viewModel.state == .loading)
        await viewModel.load()
        #expect(viewModel.spot?.id == "sample-3")
    }

    @Test func 끝난_항목은_안내와_장소_보기를_보여준다() async throws {
        let viewModel = makeViewModel(id: SampleSpots.endedID)
        await viewModel.load()

        #expect(viewModel.isEnded)
        // 끝난 날 = now - 10일 = 2026-11-08 (서울)
        #expect(viewModel.endedNotice == "11월 8일에 끝난 볼거리예요.")
        let links = try #require(viewModel.mapLinks)
        #expect(links.app.absoluteString.hasPrefix("nmap://place?"))
        #expect(links.web.absoluteString.hasPrefix("https://map.naver.com/p/search/"))
    }

    @Test func 진행_중이면_네이버지도_길찾기_링크() throws {
        let viewModel = makeViewModel(id: "sample-1", initial: spots[0])
        let links = try #require(viewModel.mapLinks)
        #expect(links.app.absoluteString.hasPrefix("nmap://route/walk?dlat=37.569&dlng=126.9784"))
        #expect(links.app.absoluteString.contains("appname=com.herezi.app"))
    }

    @Test func 없는_항목은_404_상태가_된다() async {
        let viewModel = makeViewModel(id: "nope")
        await viewModel.load()
        #expect(viewModel.state == .notFound)
    }

    @Test func 오류면_미리_그린_내용은_유지하고_토스트를_띄운다() async {
        let failing = FakeSpotsService(spots: spots, failure: FakeSpotsService.FakeError.notFound)
        let withInitial = makeViewModel(id: "sample-1", initial: spots[0], service: failing)
        await withInitial.load()
        #expect(withInitial.state == .loaded)
        #expect(withInitial.toastMessage == "최신 정보를 불러오지 못했어요")

        let withoutInitial = makeViewModel(id: "sample-1", service: failing)
        await withoutInitial.load()
        #expect(withoutInitial.state == .failed)
    }

    @Test func 저장_토글은_계정에_저장하고_토스트를_띄운다() async {
        let library = makeLibrary()
        let viewModel = makeViewModel(id: "sample-1", initial: spots[0], saved: library)

        await viewModel.toggleSave()
        #expect(viewModel.isSaved)
        #expect(library.items.first?.savedAt == now)
        #expect(viewModel.toastMessage == "저장했어요")

        await viewModel.toggleSave()
        #expect(!viewModel.isSaved)
        #expect(viewModel.toastMessage == "저장을 취소했어요")
    }

    @Test func 로그인_전_저장은_로그인_시트를_띄우고_아이콘을_채우지_않는다() async {
        let library = makeLibrary(provider: nil)
        let viewModel = makeViewModel(id: "sample-1", initial: spots[0], saved: library)
        await viewModel.toggleSave()
        #expect(!viewModel.isSaved)
        #expect(library.auth.loginRequest?.purpose == .save)
    }

    @Test func 공유_문구에_링크를_담는다() {
        let viewModel = makeViewModel(id: "sample-1", initial: spots[0])
        let lines = viewModel.shareText?.split(separator: "\n").map(String.init)
        #expect(lines?.first == "서울빛초롱축제")
        #expect(lines?[1].hasSuffix(" · 청계광장") == true)
        #expect(lines?.last == "https://herezi.com/s/sample-1")
    }

    @Test func 오류_제보_메일_제목에_id와_제목을_담는다() throws {
        let viewModel = makeViewModel(id: "sample-1", initial: spots[0])
        let url = try #require(viewModel.reportMailURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "help@herezi.com")
        #expect(components.queryItems?.first?.value == "[정보 오류] sample-1 서울빛초롱축제")
    }
}
