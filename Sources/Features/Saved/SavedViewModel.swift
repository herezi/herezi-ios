import Domain
import Foundation
import Observation

/// S4 저장 목록의 상태·로직 (herezi-api docs/design/screens/S4-saved.md).
/// 저장은 계정에 한다(`SavedLibrary` — `GET/PUT/DELETE /v1/me/saved`). 로그인 전에는 목록 대신 로그인 안내.
@MainActor
@Observable
public final class SavedViewModel {
    /// 본문 상태 (S4 "상태" 표).
    public enum Content: Equatable, Sendable {
        /// 로그인 전 — `SignInPrompt`.
        case loggedOut
        /// 첫 로딩(캐시 없음)·첫 로그인 옮기기 중 — 스켈레톤.
        case loading
        /// 불러오기 오류(캐시 없음).
        case failed
        /// 로그인 후 0개.
        case empty
        case list
    }

    /// 토스트. `undo`면 "되돌리기" 버튼을 붙인다(4초).
    public struct Toast: Equatable, Sendable {
        public let id = UUID()
        public let message: String
        public let undo: Bool
    }

    public private(set) var isEditing = false
    public private(set) var selection: Set<String> = []
    public var toast: Toast?
    /// 마지막으로 지운 항목 (되돌리기용).
    public private(set) var lastRemoved: [SavedSpot] = []

    private let library: SavedLibrary
    private let origin: Coordinate?
    private let now: @Sendable () -> Date

    /// - Parameter origin: 현재 위치를 알면 거리 계산에 쓴다. 모르면 nil(카드에 장소명).
    public init(library: SavedLibrary, origin: Coordinate? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.library = library
        self.origin = origin
        self.now = now
    }

    public var content: Content {
        guard library.isLoggedIn else { return .loggedOut }
        if library.items.isEmpty {
            if library.isMigrating { return .loading }
            switch library.state {
            case .idle, .loading: return .loading
            case .failed: return .failed
            case .loaded: return .empty
            }
        }
        return .list
    }

    /// 편집 버튼은 로그인 상태이고 항목이 있을 때만.
    public var canEdit: Bool { content == .list }

    // MARK: 로그인 전

    public static let signInTitle = "로그인하면 저장할 수 있어요"

    /// 기기 로컬 저장(이전 버전)이 남아 있으면 개수 안내로 바꾼다.
    public var signInMessage: String {
        let count = library.legacyCount
        return count > 0
            ? "이 기기에 저장한 볼거리 \(count)개가 있어요. 로그인하면 계정으로 옮겨 드려요."
            : "저장한 볼거리를 어느 기기에서든 다시 볼 수 있어요."
    }

    /// 로그인 버튼 → S7 시트(대기 동작 없음, 성공 후 이 화면이 목록으로 바뀜).
    public func login() {
        library.auth.requestLogin(.account)
    }

    // MARK: 목록

    public var items: [SavedSpot] { library.items }

    /// 진행 중 — 저장 시각 최신순.
    public var active: [SavedSpot] { items.filter { !isEnded($0.spot) } }

    /// 끝난 볼거리 — 저장 시각 최신순.
    public var ended: [SavedSpot] { items.filter { isEnded($0.spot) } }

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

    /// 화면에 들어올 때(조용히)·당겨서 새로고침(`userInitiated`). 캐시가 있으면 캐시로 먼저 그려져 있다.
    public func refresh(userInitiated: Bool = false) async {
        guard library.isLoggedIn else { return }
        do {
            try await library.refresh()
        } catch AuthError.sessionExpired {
            show("다시 로그인해 주세요")
        } catch {
            if userInitiated && !items.isEmpty { show("최신 목록을 불러오지 못했어요") }
        }
    }

    // MARK: 지우기

    /// 밀어서 삭제 → 토스트 "저장을 취소했어요" + 되돌리기.
    public func delete(_ id: String) async {
        await remove([id])
    }

    /// 되돌리기 → 다시 `PUT`.
    public func undo() async {
        let restored = lastRemoved
        lastRemoved = []
        do {
            try await library.restore(restored)
        } catch {
            show(SavedLibrary.message(for: error, fallback: "저장하지 못했어요. 다시 눌러 주세요."))
        }
    }

    public var clearEndedPrompt: String { "끝난 볼거리 \(ended.count)개를 지울까요?" }

    public func clearEnded() async {
        await remove(Set(ended.map(\.id)))
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

    public func deleteSelected() async {
        guard !selection.isEmpty else { return }
        let ids = selection
        setEditing(false)
        await remove(ids)
    }

    private func remove(_ ids: Set<String>) async {
        do {
            let removed = try await library.remove(ids: ids)
            guard !removed.isEmpty else { return }
            lastRemoved = removed
            toast = Toast(message: "저장을 취소했어요", undo: true)
        } catch AuthError.sessionExpired {
            show("다시 로그인해 주세요")
        } catch {
            show("지우지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }

    private func show(_ message: String) {
        toast = Toast(message: message, undo: false)
    }
}
