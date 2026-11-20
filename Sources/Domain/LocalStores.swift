import Foundation
import Observation

/// 저장(찜)한 볼거리 하나: 저장할 때의 Spot 스냅샷 + 저장 시각 (S4).
public struct SavedSpot: Identifiable, Hashable, Sendable, Codable {
    public var spot: Spot
    public let savedAt: Date

    public var id: String { spot.id }

    public init(spot: Spot, savedAt: Date) {
        self.spot = spot
        self.savedAt = savedAt
    }
}

/// 기기 로컬 저장 목록 (가입 없음). `UserDefaults`에 JSON으로 둔다.
/// 상세(S3)와 저장 목록(S4)이 같은 인스턴스를 공유해 저장 상태가 바로 맞춰진다.
@MainActor
@Observable
public final class SavedSpotsStore {
    /// 저장 시각 최신순.
    public private(set) var items: [SavedSpot] = []

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "herezi.savedSpots.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([SavedSpot].self, from: data)
        {
            items = decoded.sorted { $0.savedAt > $1.savedAt }
        }
    }

    public func isSaved(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    public func save(_ spot: Spot, at date: Date = Date()) {
        guard !isSaved(spot.id) else { return }
        items.insert(SavedSpot(spot: spot, savedAt: date), at: 0)
        persist()
    }

    /// 지운 항목을 돌려준다(되돌리기용).
    @discardableResult
    public func remove(ids: Set<String>) -> [SavedSpot] {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        items.removeAll { ids.contains($0.id) }
        persist()
        return removed
    }

    /// 지웠던 항목을 원래 저장 시각 그대로 되살린다.
    public func restore(_ saved: [SavedSpot]) {
        let new = saved.filter { !isSaved($0.id) }
        guard !new.isEmpty else { return }
        items = (items + new).sorted { $0.savedAt > $1.savedAt }
        persist()
    }

    /// 다시 받아온 최신 정보로 스냅샷을 바꾼다(저장 시각은 유지). 저장돼 있지 않으면 무시.
    public func update(_ spot: Spot) {
        guard let index = items.firstIndex(where: { $0.id == spot.id }), items[index].spot != spot else { return }
        items[index].spot = spot
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

/// 최근 검색어 (S5). 최신순, 중복 없이 최대 10개, 기기 로컬.
@MainActor
@Observable
public final class RecentSearchesStore {
    public static let maxCount = 10
    public private(set) var terms: [String] = []

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "herezi.recentSearches.v1") {
        self.defaults = defaults
        self.key = key
        terms = defaults.stringArray(forKey: key) ?? []
    }

    public func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        terms.removeAll { $0 == trimmed }
        terms.insert(trimmed, at: 0)
        if terms.count > Self.maxCount { terms.removeLast(terms.count - Self.maxCount) }
        persist()
    }

    public func remove(_ term: String) {
        terms.removeAll { $0 == term }
        persist()
    }

    public func clear() {
        terms = []
        persist()
    }

    private func persist() {
        defaults.set(terms, forKey: key)
    }
}
