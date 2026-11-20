import Domain
import Foundation
import Observation

/// S5 검색의 상태·로직. 키보드의 검색 키를 누를 때만 조회한다(글자 입력마다 조회하지 않음).
@MainActor
@Observable
public final class SearchViewModel {
    public enum Phase: Equatable, Sendable {
        /// 검색 전 — 최근 검색어.
        case recent
        case loading
        case results([Spot])
        case empty
        case failed
    }

    /// 2글자 미만이면 검색하지 않는다.
    public static let minimumLength = 2
    /// 현재 위치 기준 반경 20km.
    public static let radiusMeters = 20_000

    public var text = ""
    public private(set) var phase: Phase = .recent
    /// 마지막으로 조회한 검색어.
    public private(set) var submittedQuery: String?
    public var toastMessage: String?

    private let service: any SpotsService
    private let recentStore: RecentSearchesStore
    private let origin: Coordinate

    public init(service: any SpotsService, recents: RecentSearchesStore, origin: Coordinate) {
        self.service = service
        self.recentStore = recents
        self.origin = origin
    }

    public var recents: [String] { recentStore.terms }

    /// "'빛초롱' 검색 결과 3개"
    public var resultSummary: String? {
        guard case .results(let items) = phase, let submittedQuery else { return nil }
        return "'\(submittedQuery)' 검색 결과 \(items.count)개"
    }

    /// "'{q}'에 맞는 볼거리가 없어요"
    public var emptyTitle: String { "'\(submittedQuery ?? "")'에 맞는 볼거리가 없어요" }

    /// 키보드 검색 키.
    public func submit() async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumLength else {
            toastMessage = "두 글자 이상 입력해 주세요"
            return
        }
        await search(query)
    }

    /// 최근 검색어를 누르면 바로 조회.
    public func selectRecent(_ term: String) async {
        await search(term)
    }

    public func retry() async {
        guard let submittedQuery else { return }
        await search(submittedQuery)
    }

    /// 입력을 지우면 검색 전(최근 검색) 상태로.
    public func clearText() {
        text = ""
        submittedQuery = nil
        phase = .recent
    }

    public func removeRecent(_ term: String) {
        recentStore.remove(term)
    }

    public func clearRecents() {
        recentStore.clear()
    }

    private func search(_ query: String) async {
        text = query
        submittedQuery = query
        recentStore.add(query)
        phase = .loading
        let request = SpotQuery(coordinate: origin, radiusMeters: Self.radiusMeters, keyword: query)
        do {
            let items = try await service.spots(request).items
                .sorted { ($0.distanceMeters ?? .max, $0.title) < ($1.distanceMeters ?? .max, $1.title) }
            guard submittedQuery == query else { return }
            phase = items.isEmpty ? .empty : .results(items)
        } catch {
            guard submittedQuery == query else { return }
            phase = .failed
        }
    }
}
