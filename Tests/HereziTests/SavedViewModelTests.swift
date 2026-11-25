import Domain
import FeatureSaved
import Foundation
import Testing

@MainActor
struct SavedViewModelTests {
    private let now = TestData.now

    /// 로그인 상태 + 계정에 `spots`가 저장된(먼저 저장한 게 아래) 목록.
    private func loggedIn(with spots: [Spot], account: ScriptedAccountService? = nil) async -> (
        SavedViewModel, SavedLibrary
    ) {
        let account = account ?? ScriptedAccountService()
        let library = makeLibrary(account: account)
        for spot in spots { _ = await library.save(spot) }
        // 저장 시각을 다르게: 나중에 저장한 게 위.
        let now = self.now
        return (SavedViewModel(library: library, origin: .seoulCityHall, now: { now }), library)
    }

    @Test func 로그인_전에는_로그인_안내와_기기_저장_개수() {
        let library = makeLibrary(provider: nil, legacy: Array(TestData.spots.prefix(3)))
        let viewModel = SavedViewModel(library: library)
        #expect(viewModel.content == .loggedOut)
        #expect(!viewModel.canEdit)
        #expect(viewModel.signInMessage == "이 기기에 저장한 볼거리 3개가 있어요. 로그인하면 계정으로 옮겨 드려요.")

        viewModel.login()
        #expect(library.auth.loginRequest?.purpose == .account)

        let empty = SavedViewModel(library: makeLibrary(provider: nil))
        #expect(empty.signInMessage == "저장한 볼거리를 어느 기기에서든 다시 볼 수 있어요.")
    }

    @Test func 첫_로딩_빈_오류_상태() async {
        let account = ScriptedAccountService()
        let library = makeLibrary(account: account)
        let viewModel = SavedViewModel(library: library)
        #expect(viewModel.content == .loading)

        await viewModel.refresh()
        #expect(viewModel.content == .empty)

        await account.set(list: AccountError.offline)
        let failing = SavedViewModel(library: makeLibrary(account: account))
        await failing.refresh()
        #expect(failing.content == .failed)
    }

    @Test func 진행_중과_끝난_항목을_나누고_최신_저장순으로_보여준다() async {
        let (viewModel, _) = await loggedIn(with: TestData.spots)
        await viewModel.refresh()

        #expect(viewModel.content == .list)
        #expect(viewModel.canEdit)
        #expect(viewModel.ended.map(\.id) == [SampleSpots.endedID])
        #expect(viewModel.endedHeader == "끝난 볼거리 1")
        #expect(viewModel.active.count == TestData.spots.count - 1)
    }

    @Test func 끝_시각이_지난_스냅샷도_끝난_것으로_보고_배지를_켠다() async {
        let past = Spot(
            id: "old", title: "지난 전시", category: .exhibition, coordinate: .seoulCityHall,
            startsAt: now.addingTimeInterval(-5 * 86_400), endsAt: now.addingTimeInterval(-86_400),
            source: "test", fetchedAt: now)
        let account = ScriptedAccountService(
            base: FakeAccountService(spots: TestData.spots + [past], now: { TestData.now }))
        let (viewModel, _) = await loggedIn(with: [past], account: account)

        #expect(viewModel.ended.map(\.id) == ["old"])
        #expect(viewModel.displaySpot(viewModel.ended[0]).isEnded)
    }

    @Test func 밀어서_지우면_되돌릴_수_있다() async {
        let (viewModel, library) = await loggedIn(with: Array(TestData.listedSpots.prefix(2)))

        await viewModel.delete("sample-1")
        #expect(viewModel.active.map(\.id) == ["sample-2"])
        #expect(viewModel.toast?.message == "저장을 취소했어요")
        #expect(viewModel.toast?.undo == true)

        await viewModel.undo()
        #expect(library.isSaved("sample-1"))
    }

    @Test func 지우기_실패는_되돌리고_토스트() async {
        let account = ScriptedAccountService()
        let (viewModel, library) = await loggedIn(with: [TestData.spots[0]], account: account)
        await account.set(unsave: AccountError.server)

        await viewModel.delete("sample-1")

        #expect(library.isSaved("sample-1"))
        #expect(viewModel.toast?.message == "지우지 못했어요. 잠시 후 다시 시도해 주세요.")
        #expect(viewModel.toast?.undo == false)
    }

    @Test func 편집에서_고른_항목만_지운다() async {
        let (viewModel, library) = await loggedIn(with: TestData.spots)

        viewModel.setEditing(true)
        viewModel.toggleSelection("sample-1")
        viewModel.toggleSelection("sample-2")
        #expect(viewModel.deleteSelectedTitle == "2개 지우기")
        await viewModel.deleteSelected()

        #expect(!viewModel.isEditing)
        #expect(!library.isSaved("sample-1") && !library.isSaved("sample-2"))
        #expect(library.items.count == TestData.spots.count - 2)
    }

    @Test func 끝난_볼거리_모두_지우기() async {
        let (viewModel, _) = await loggedIn(with: TestData.spots)
        #expect(viewModel.clearEndedPrompt == "끝난 볼거리 1개를 지울까요?")
        await viewModel.clearEnded()
        #expect(viewModel.ended.isEmpty)
        #expect(viewModel.active.count == TestData.spots.count - 1)
    }

    @Test func 당겨서_새로고침_실패는_캐시가_있을_때_토스트() async {
        let account = ScriptedAccountService()
        let (viewModel, _) = await loggedIn(with: [TestData.spots[0]], account: account)
        await account.set(list: AccountError.offline)

        await viewModel.refresh()
        #expect(viewModel.toast == nil)  // 화면 진입 실패는 조용히
        await viewModel.refresh(userInitiated: true)
        #expect(viewModel.toast?.message == "최신 목록을 불러오지 못했어요")
        #expect(viewModel.content == .list)
    }

    @Test func 세션이_만료되면_로그인_전_상태와_토스트() async {
        let account = ScriptedAccountService()
        let (viewModel, _) = await loggedIn(with: [TestData.spots[0]], account: account)
        await account.set(list: AuthError.unauthorized)

        await viewModel.refresh()

        #expect(viewModel.content == .loggedOut)
        #expect(viewModel.toast?.message == "다시 로그인해 주세요")
    }

    @Test func 위치를_알면_거리를_계산한다() async {
        let (viewModel, _) = await loggedIn(with: [])
        let distance = viewModel.distance(for: TestData.spots[0])
        // 서울시청(37.5663, 126.9779) ↔ 청계광장(37.5690, 126.9784) ≈ 303m
        #expect((290...315).contains(distance ?? 0))
    }

    @Test func 기기_로컬_저장은_다시_열어도_남는다() {
        let defaults = freshDefaults()
        let first = SavedSpotsStore(defaults: defaults)
        first.save(TestData.spots[0], at: now)
        let reopened = SavedSpotsStore(defaults: defaults)
        #expect(reopened.items.map(\.id) == ["sample-1"])
        #expect(reopened.items.first?.savedAt == now)
        #expect(reopened.items.first?.spot == TestData.spots[0])
    }
}
