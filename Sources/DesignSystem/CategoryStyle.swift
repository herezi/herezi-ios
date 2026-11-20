import Domain
import SwiftUI

/// 카테고리 색 (DESIGN §2.3). 핀 배경, 카드의 작은 점, 썸네일 대체 배경에만 쓴다 — 글자에는 쓰지 않는다.
/// 아이콘 이름은 `SpotCategory.symbolName`(Domain)과 DESIGN 표가 같다.
extension SpotCategory {
    public var color: Color {
        switch self {
        case .nature: Color(hex: 0x2E9E5B)
        case .festival: Color(hex: 0xE5484D)
        case .performance: Color(hex: 0x8E4FD8)
        case .exhibition: Color(hex: 0x0E8F89)
        case .popup: Color(hex: 0xDB3F78)
        case .food: Color(hex: 0xD8661F)
        case .family: Color(hex: 0x5E9414)
        case .pet: Color(hex: 0x9A6436)
        case .sports: Color(hex: 0x5A5FD6)
        }
    }
}

/// 카테고리 색 6pt 점 (카드 메타, 상세 카테고리 줄).
public struct CategoryDot: View {
    let category: SpotCategory

    public init(_ category: SpotCategory) {
        self.category = category
    }

    public var body: some View {
        Circle()
            .fill(category.color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// 이미지가 없을 때의 자리: 카테고리 색 12% 배경 + 카테고리 아이콘(카테고리 색).
public struct CategoryPlaceholder: View {
    let category: SpotCategory
    let iconSize: CGFloat

    public init(_ category: SpotCategory, iconSize: CGFloat) {
        self.category = category
        self.iconSize = iconSize
    }

    public var body: some View {
        ZStack {
            category.color.opacity(0.12)
            Image(systemName: category.symbolName)
                .font(.system(size: iconSize))
                .foregroundStyle(category.color)
        }
        .accessibilityHidden(true)
    }
}
