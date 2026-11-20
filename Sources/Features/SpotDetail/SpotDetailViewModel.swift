import Domain
import Foundation
import Observation

/// S3 상세의 상태·로직. 목록에서 들어오면 목록의 Spot으로 먼저 그리고(`initial`), 응답이 오면 갱신한다.
@MainActor
@Observable
public final class SpotDetailViewModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        /// 404 — 끝났거나 없는 볼거리.
        case notFound
        case failed
    }

    public let id: String
    public private(set) var spot: Spot?
    public private(set) var state: LoadState
    /// 화면 아래 토스트로 띄울 문구. 뷰가 보여준 뒤 nil로 되돌린다.
    public var toastMessage: String?
    /// 위치 권한이 없어 서울시청 기준 거리인지.
    public let usesFallbackLocation: Bool

    private let service: any SpotsService
    private let saved: SavedSpotsStore
    private let now: @Sendable () -> Date

    public init(
        id: String, initial: Spot? = nil, service: any SpotsService, saved: SavedSpotsStore,
        usesFallbackLocation: Bool = false, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.id = id
        self.spot = initial
        self.state = initial == nil ? .loading : .loaded
        self.service = service
        self.saved = saved
        self.usesFallbackLocation = usesFallbackLocation
        self.now = now
    }

    public func load() async {
        if spot == nil { state = .loading }
        do {
            let fresh = try await service.spot(id: id)
            // 상세 응답에는 distance_m이 없다 — 목록에서 받은 거리를 유지한다.
            let distance: Int? = fresh.distanceMeters ?? spot?.distanceMeters
            spot = fresh.copy(distanceMeters: .some(distance))
            state = .loaded
            saved.update(fresh)
        } catch SpotsServiceError.notFound {
            state = .notFound
        } catch {
            if spot != nil {
                state = .loaded
                toastMessage = "최신 정보를 불러오지 못했어요"
            } else {
                state = .failed
            }
        }
    }

    // MARK: 저장

    public var isSaved: Bool { saved.isSaved(id) }

    public func toggleSave() {
        if isSaved {
            saved.remove(ids: [id])
            toastMessage = "저장을 취소했어요"
        } else if let spot {
            saved.save(spot, at: now())
            toastMessage = "저장했어요"
        }
    }

    /// 404 화면의 "저장에서 지우기".
    public func removeFromSaved() {
        saved.remove(ids: [id])
        toastMessage = "저장을 취소했어요"
    }

    // MARK: 표시용 값

    public var isEnded: Bool { spot?.isEnded ?? false }

    public var endedNotice: String? {
        guard let spot, spot.isEnded else { return nil }
        return SpotFormatting.endedNotice(end: spot.endsAt)
    }

    /// "내 위치에서 350m" / 위치 거부 시 "서울시청에서 1.2km". 거리를 모르면 nil(행 생략).
    public var distanceText: String? {
        guard let distance = SpotFormatting.distance(meters: spot?.distanceMeters) else { return nil }
        return usesFallbackLocation ? "서울시청에서 \(distance)" : "내 위치에서 \(distance)"
    }

    public var periodText: String? {
        spot.map { SpotFormatting.detailPeriod(start: $0.startsAt, end: $0.endsAt) }
    }

    public var periodNote: String? {
        guard let spot, !spot.isEnded else { return nil }
        return SpotFormatting.detailPeriodNote(start: spot.startsAt, end: spot.endsAt, now: now())
    }

    public var timeText: String? {
        spot.flatMap { SpotFormatting.timeRange(start: $0.startsAt, end: $0.endsAt) }
    }

    public var sourceText: String? {
        spot.map { "출처 · \(SpotFormatting.sourceName($0.source))" }
    }

    public var fetchedText: String? {
        spot.map { SpotFormatting.fetchedText($0.fetchedAt, now: now()) }
    }

    public var shareText: String? {
        spot.map { SpotLinks.shareText(for: $0, now: now()) }
    }

    /// 하단 버튼: 진행 중이면 길찾기(앱, 웹), 끝났으면 장소 보기(앱, 웹).
    public var mapLinks: (app: URL, web: URL)? {
        guard let spot else { return nil }
        if spot.isEnded {
            return (SpotLinks.naverPlaceApp(spot), SpotLinks.naverPlaceWeb(spot))
        }
        let mode = SpotLinks.RouteMode.forDistance(spot.distanceMeters)
        return (SpotLinks.naverRouteApp(to: spot, mode: mode), SpotLinks.naverRouteWeb(to: spot, mode: mode))
    }

    public var reportMailURL: URL? {
        spot.map { SpotLinks.reportMail(subject: SpotLinks.reportSubject(for: $0)) }
    }

    public func showMailUnavailable() {
        toastMessage = "메일 앱이 없어요. \(SpotLinks.supportEmail) 으로 보내 주세요"
    }

    public func addressCopied() {
        toastMessage = "주소를 복사했어요"
    }
}
