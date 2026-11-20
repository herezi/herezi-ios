import Foundation

/// `components.schemas.Category` in `api/openapi.yaml`. Raw values MUST match the contract
/// (checked by scripts/check-api-drift.sh). 무료 여부는 카테고리가 아니라 `Spot.isFree` + `free` 필터다.
public enum SpotCategory: String, CaseIterable, Hashable, Sendable {
    case nature
    case festival
    case performance
    case exhibition
    case popup
    case food
    case family
    case pet
    case sports

    /// Korean label shown in chips and rows.
    public var displayName: String {
        switch self {
        case .nature: "자연·계절"
        case .festival: "축제·행사"
        case .performance: "공연"
        case .exhibition: "전시"
        case .popup: "팝업"
        case .food: "먹거리"
        case .family: "아이·가족"
        case .pet: "반려동물"
        case .sports: "스포츠"
        }
    }

    /// SF Symbol name. A plain string so Domain does not import SwiftUI.
    public var symbolName: String {
        switch self {
        case .nature: "leaf"
        case .festival: "party.popper"
        case .performance: "music.mic"
        case .exhibition: "photo.artframe"
        case .popup: "bag"
        case .food: "fork.knife"
        case .family: "figure.2.and.child.holdinghands"
        case .pet: "pawprint"
        case .sports: "figure.run"
        }
    }
}

/// `when` query parameter of `GET /v1/spots`.
public enum WhenFilter: String, CaseIterable, Hashable, Sendable {
    case now
    case today
    case weekend
    case week

    public var displayName: String {
        switch self {
        case .now: "지금"
        case .today: "오늘"
        case .weekend: "이번 주말"
        case .week: "이번 주"
        }
    }
}
