import Domain
import FeatureSaved
import Foundation
import Testing

@MainActor
struct SavedViewModelTests {
    private let now = TestData.now

    private func store(with spots: [Spot]) -> SavedSpotsStore {
        let store = SavedSpotsStore(defaults: freshDefaults())
        for (offset, spot) in spots.enumerated() {
            store.save(spot, at: now.addingTimeInterval(Double(offset) * 60))
        }
        return store
    }

    private func makeViewModel(_ store: SavedSpotsStore, service: any SpotsService) -> SavedViewModel {
        let now = self.now
        return SavedViewModel(store: store, service: service, origin: .seoulCityHall, now: { now })
    }

    @Test func 진행_중과_끝난_항목을_나누고_최신_저장순으로_보여준다() {
        let store = store(with: TestData.spots)
        let viewModel = makeViewModel(store, service: FakeSpotsService(spots: TestData.spots))

        #expect(viewModel.active.map(\.id) == ["sample-5", "sample-4", "sample-3", "sample-2", "sample-1"])
        #expect(viewModel.ended.map(\.id) == [SampleSpots.endedID])
        #expect(viewModel.endedHeader == "끝난 볼거리 1")
    }

    @Test func 끝_시각이_지난_스냅샷도_끝난_것으로_보고_배지를_켠다() {
        let past = Spot(
            id: "old", title: "지난 전시", category: .exhibition, coordinate: .seoulCityHall,
            startsAt: now.addingTimeInterval(-5 * 86_400), endsAt: now.addingTimeInterval(-86_400),
            source: "test", fetchedAt: now)
        let store = store(with: [past])
        let viewModel = makeViewModel(store, service: FakeSpotsService(spots: []))

        #expect(viewModel.ended.map(\.id) == ["old"])
        #expect(viewModel.displaySpot(viewModel.ended[0]).isEnded)
    }

    @Test func 다시_받아_스냅샷을_갱신하고_404는_종료로_표시한다() async {
        let original = TestData.spots
        let store = store(with: [original[0], original[1], original[2]])
        let updated = original[0].copy(isEnded: true)
        let service = ScriptedDetailService(outcomes: [
            "sample-1": .spot(updated), "sample-2": .notFound, "sample-3": .failure,
        ])
        let viewModel = makeViewModel(store, service: service)

        await viewModel.refresh()

        #expect(Set(viewModel.ended.map(\.id)) == ["sample-1", "sample-2"])
        // 다른 오류는 조용히 무시 — 스냅샷 그대로.
        #expect(viewModel.active.map(\.id) == ["sample-3"])
        #expect(store.items.first { $0.id == "sample-2" }?.spot.title == original[1].title)
    }

    @Test func 밀어서_지우면_되돌릴_수_있다() {
        let store = store(with: Array(TestData.listedSpots.prefix(2)))
        let viewModel = makeViewModel(store, service: FakeSpotsService(spots: []))

        viewModel.delete("sample-1")
        #expect(viewModel.active.map(\.id) == ["sample-2"])
        #expect(viewModel.toastMessage == "저장을 취소했어요")

        viewModel.undo()
        #expect(viewModel.active.map(\.id) == ["sample-2", "sample-1"])
    }

    @Test func 편집에서_고른_항목만_지운다() {
        let store = store(with: TestData.spots)
        let viewModel = makeViewModel(store, service: FakeSpotsService(spots: []))

        viewModel.setEditing(true)
        viewModel.toggleSelection("sample-1")
        viewModel.toggleSelection("sample-2")
        #expect(viewModel.deleteSelectedTitle == "2개 지우기")
        viewModel.deleteSelected()

        #expect(!viewModel.isEditing)
        #expect(!store.isSaved("sample-1") && !store.isSaved("sample-2"))
        #expect(store.items.count == TestData.spots.count - 2)
    }

    @Test func 끝난_볼거리_모두_지우기() {
        let store = store(with: TestData.spots)
        let viewModel = makeViewModel(store, service: FakeSpotsService(spots: []))
        #expect(viewModel.clearEndedPrompt == "끝난 볼거리 1개를 지울까요?")
        viewModel.clearEnded()
        #expect(viewModel.ended.isEmpty)
        #expect(viewModel.active.count == 5)
    }

    @Test func 위치를_알면_거리를_계산한다() {
        let viewModel = makeViewModel(store(with: []), service: FakeSpotsService(spots: []))
        let distance = viewModel.distance(for: TestData.spots[0])
        // 서울시청(37.5663, 126.9779) ↔ 청계광장(37.5690, 126.9784) ≈ 303m
        #expect((290...315).contains(distance ?? 0))
    }

    @Test func 저장_목록은_기기에_남는다() {
        let defaults = freshDefaults()
        let first = SavedSpotsStore(defaults: defaults)
        first.save(TestData.spots[0], at: now)
        let reopened = SavedSpotsStore(defaults: defaults)
        #expect(reopened.items.map(\.id) == ["sample-1"])
        #expect(reopened.items.first?.savedAt == now)
        #expect(reopened.items.first?.spot == TestData.spots[0])
    }
}
