import Domain
import Foundation
import Observation

/// State + logic for the Nearby screen. UI-free so it is unit-testable (see NearbyViewModelTests).
@MainActor
@Observable
public final class NearbyViewModel {
    public enum DisplayMode: String, CaseIterable, Sendable {
        case list
        case map

        public var displayName: String {
            switch self {
            case .list: "목록"
            case .map: "지도"
            }
        }
    }

    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public var mode: DisplayMode = .list
    public private(set) var selectedCategories: Set<SpotCategory> = []
    public private(set) var when: WhenFilter = .now
    /// "무료만" 필터. 서버에 `free=true`로 전달된다.
    public private(set) var freeOnly = false
    public private(set) var spots: [Spot] = []
    public private(set) var state: LoadState = .idle
    public private(set) var coordinate: Coordinate?
    /// True when location was unavailable and we fell back to 서울시청.
    public private(set) var isUsingFallbackLocation = false

    private let service: any SpotsService
    private let location: any LocationProviding

    public init(service: any SpotsService, location: any LocationProviding) {
        self.service = service
        self.location = location
    }

    /// Spots after client-side category filtering, nearest first. Unknown distance goes last.
    public var visibleSpots: [Spot] {
        Self.filter(spots, categories: selectedCategories, freeOnly: freeOnly)
    }

    /// Pure filter used by `visibleSpots`; exposed for tests.
    public nonisolated static func filter(
        _ spots: [Spot], categories: Set<SpotCategory>, freeOnly: Bool = false
    ) -> [Spot] {
        spots
            .filter { categories.isEmpty || categories.contains($0.category) }
            .filter { !freeOnly || $0.isFree == true }
            .sorted { ($0.distanceMeters ?? .max, $0.title) < ($1.distanceMeters ?? .max, $1.title) }
    }

    public func isSelected(_ category: SpotCategory) -> Bool {
        selectedCategories.contains(category)
    }

    public func toggle(_ category: SpotCategory) async {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        await reload()
    }

    public func clearCategories() async {
        guard !selectedCategories.isEmpty else { return }
        selectedCategories = []
        await reload()
    }

    public func setFreeOnly(_ newValue: Bool) async {
        guard newValue != freeOnly else { return }
        freeOnly = newValue
        await reload()
    }

    public func setWhen(_ newValue: WhenFilter) async {
        guard newValue != when else { return }
        when = newValue
        await reload()
    }

    /// Resolves location once, then fetches spots for the current filters.
    public func reload() async {
        state = .loading
        let origin = await resolveCoordinate()
        let query = SpotQuery(
            coordinate: origin, categories: selectedCategories, when: when, freeOnly: freeOnly)
        do {
            spots = try await service.spots(query).items
            state = .loaded
        } catch {
            state = .failed("주변 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }

    private func resolveCoordinate() async -> Coordinate {
        if let coordinate { return coordinate }
        do {
            let resolved = try await location.currentCoordinate()
            coordinate = resolved
            return resolved
        } catch {
            isUsingFallbackLocation = true
            coordinate = .seoulCityHall
            return .seoulCityHall
        }
    }
}

/// `LocationProviding` that always returns a fixed coordinate. For previews and tests.
public struct FixedLocationProvider: LocationProviding {
    public let coordinate: Coordinate

    public init(_ coordinate: Coordinate = .seoulCityHall) {
        self.coordinate = coordinate
    }

    public func currentCoordinate() async throws -> Coordinate {
        coordinate
    }
}
