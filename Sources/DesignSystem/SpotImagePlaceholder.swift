import Domain
import SwiftUI

/// 이미지가 없을 때의 "타이포 포스터" (제품 결정, DESIGN 갱신 예정).
/// 카테고리 색 배경 + 왼쪽 아래 흰 제목(ExtraBold, 최대 3줄, 좁은 줄간격)
/// + 왼쪽 위 카테고리 라벨(흰 20% 알약) + 오른쪽 위 브랜드 눈 두 개.
/// 세부는 최종 스펙에서 바뀔 수 있어 이 컴포넌트 하나 뒤에 둔다. 장식이라 스크린리더에서 숨긴다.
public struct SpotImagePlaceholder: View {
    public struct Options: Sendable {
        /// 제목을 그릴지 (히어로처럼 카드가 제목을 따로 그리면 끈다).
        public var showsTitle: Bool
        /// 카테고리 라벨을 그릴지.
        public var showsLabel: Bool
        /// 위쪽 여백 (상세처럼 위에 상단 바가 겹치는 경우).
        public var topInset: CGFloat

        public init(showsTitle: Bool = true, showsLabel: Bool = true, topInset: CGFloat = 0) {
            self.showsTitle = showsTitle
            self.showsLabel = showsLabel
            self.topInset = topInset
        }

        public static let full = Options()
    }

    let spot: Spot
    let options: Options

    public init(spot: Spot, options: Options = .full) {
        self.spot = spot
        self.options = options
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let padding = max(10, width * 0.07)
            let titleSize = min(40, max(15, width * 0.1))
            ZStack {
                spot.category.color
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        if options.showsLabel {
                            Text(spot.category.displayName)
                                .font(.system(size: max(10, titleSize * 0.55), weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        BrandEyes(height: max(10, titleSize * 0.7))
                    }
                    Spacer(minLength: 0)
                    if options.showsTitle {
                        Text(spot.title)
                            .font(.system(size: titleSize, weight: .heavy))
                            .lineSpacing(-titleSize * 0.15)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(padding)
                .padding(.top, options.topInset)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 브랜드의 두 눈 (로고처럼 흰 타원 + 잉크 눈동자).
public struct BrandEyes: View {
    let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    public var body: some View {
        HStack(spacing: height * 0.3) {
            eye
            eye
        }
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Ellipse()
            .fill(Color.white)
            .frame(width: height * 0.78, height: height)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(Color.hz.ink)
                    .frame(width: height * 0.4, height: height * 0.4)
                    .padding(.trailing, height * 0.1)
            }
    }
}

#Preview {
    VStack {
        SpotImagePlaceholder(spot: SampleSpots.all[0]).frame(width: 148, height: 112)
        SpotImagePlaceholder(spot: SampleSpots.all[2]).frame(width: 390, height: 292)
    }
}
