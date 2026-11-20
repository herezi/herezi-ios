import Domain
import Foundation
import Observation

/// S4 저장 목록의 상태·로직. 저장소(`SavedSpotsStore`)는 기기 로컬, 화면에 들어올 때마다 상세를 다시 받아 갱신한다.
@MainActor
@Observable
public final class SavedViewModel {
    /// 동시에 다시 받는 개수 (S4 스펙: 동시 4개).
    public static let refreshConcurrency = 4

    public private(set) var isEditing = false
    public private(set) var selection: Set<String> = []
    public var toastMessage: String?
    /// 마지막으로 지운 항목 (되돌리기용).
    public private(set) var lastRemoved: [SavedSpot] = []

    private let store: SavedSpotsStore
    private let service: any SpotsService
    private let origin: Coordinate?
    private let now: @Sendable () -> Date

    /// - Parameter origin: 현재 위치를 알면 거리 계산에 쓴다. 모르면 nil(카드에 장소명).
    public init(
        store: SavedSpotsStore, service: any SpotsService, origin: Coordinate? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.service = service
        self.origin = origin
        self.now = now
    }

    public var isEmpty: Bool { store.items.isEmpty }

    /// 진행 중 — 저장 시각 최신순.
    public var active: [SavedSpot] { store.items.filter { !isEnded($0.spot) } }

    /// 끝난 볼거리 — 저장 시각 최신순.
    public var ended: [SavedSpot] { store.items.filter { isEnded($0.spot) } }

    public var endedHeader: String { "끝난 볼거리 \(ended.count)" }

    /// 서버가 종료로 표시했거나, 스냅샷의 끝 시각이 지났으면 끝난 것으로 본다.
    public func isEnded(_ spot: Spot) -> Bool {
        spot.isEnded || (spot.endsAt.map { $0 < now() } ?? false)
    }

    /// 카드에 넣을 spot. 끝난 항목은 `isEnded`를 켜서 `종료됨` 배지가 나오게 한다.
    public func displaySpot(_ saved: SavedSpot) -> Spot {
        isEnded(saved.spot) && !saved.spot.isEnded ? saved.spot.copy(isEnded: true) : saved.spot
    }

    public func distance(for spot: Spot) -> Int? {
        origin.map { $0.distance(to: spot.coordinate) }
    }

    /// 각 항목을 `GET /v1/spots/{id}`로 다시 받아 스냅샷을 갱신한다. 404는 종료로 표시, 그 밖의 오류는 조용히 무시.
    public func refresh() async {
        let snapshots = store.items.map(\.spot)
        guard !snapshots.isEmpty else { return }
        let service = self.service
        let results = await withTaskGroup(of: (Spot, Result<Spot, any Error>).self) { group in
            var collected: [(Spot, Result<Spot, any Error>)] = []
            var next = 0
            while next < min(Self.refreshConcurrency, snapshots.count) {
                let snapshot = snapshots[next]
                group.addTask { await Self.fetch(snapshot, from: service) }
                next += 1
            }
            for await result in group {
                collected.append(result)
                if next < snapshots.count {
                    let snapshot = snapshots[next]
                    group.addTask { await Self.fetch(snapshot, from: service) }
                    next += 1
                }
            }
            return collected
        }
        for (snapshot, result) in results {
            switch result {
            case .success(let fresh):
                store.update(fresh)
            case .failure(SpotsServiceError.notFound):
                store.update(snapshot.copy(isEnded: true))
            case .failure:
                break
            }
        }
    }

    private nonisolated static func fetch(
        _ snapshot: Spot, from service: any SpotsService
    ) async -> (Spot, Result<Spot, any Error>) {
        do {
            return (snapshot, .success(try await service.spot(id: snapshot.id)))
        } catch {
            return (snapshot, .failure(error))
        }
    }

    // MARK: 지우기

    /// 밀어서 삭제 → 토스트 "저장을 취소했어요" + 되돌리기.
    public func delete(_ id: String) {
        remove([id])
    }

    public func undo() {
        store.restore(lastRemoved)
        lastRemoved = []
    }

    public var clearEndedPrompt: String { "끝난 볼거리 \(ended.count)개를 지울까요?" }

    public func clearEnded() {
        remove(Set(ended.map(\.id)))
    }

    // MARK: 편집

    public func setEditing(_ editing: Bool) {
        isEditing = editing
        selection = []
    }

    public func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    public var deleteSelectedTitle: String { "\(selection.count)개 지우기" }

    public func deleteSelected() {
        guard !selection.isEmpty else { return }
        remove(selection)
        setEditing(false)
    }

    private func remove(_ ids: Set<String>) {
        let removed = store.remove(ids: ids)
        guard !removed.isEmpty else { return }
        lastRemoved = removed
        toastMessage = "저장을 취소했어요"
    }
}
