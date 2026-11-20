import DesignSystem
import Domain
import SwiftUI

/// S1 홈 — 사진 카드 피드 (herezi-api docs/design/screens/S1-home.md).
/// 카드는 `Spot` 값을 push 하고, 카테고리·전체 보기는 `onOpenList`로 S1b 시작 필터를 넘긴다.
public struct HomeView: View {
    @State private var viewModel: HomeViewModel
    let banner: LocationBannerConfig?
    let onSearch: () -> Void
    let onOpenList: (HomeListFilter) -> Void
    let onShowMap: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    public init(
        viewModel: HomeViewModel, banner: LocationBannerConfig? = nil,
        onSearch: @escaping () -> Void, onOpenList: @escaping (HomeListFilter) -> Void,
        onShowMap: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.banner = banner
        self.onSearch = onSearch
        self.onOpenList = onOpenList
        self.onShowMap = onShowMap
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                content
            }
            .padding(.bottom, HZSpace.s8)
        }
        .background(Color.hz.bgPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await viewModel.reload() }
        .task {
            if viewModel.state == .idle { await viewModel.reload() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reloadIfStale() } }
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .loaded, let headline = viewModel.headline {
                AccessibilityNotification.Announcement("\(headline.line1) \(headline.line2)").post()
            }
        }
        .hzToast(message: $viewModel.toastMessage)
    }

    // MARK: 상단 바

    private var topBar: some View {
        HStack(spacing: HZSpace.s1) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.hz.textSecondary)
                .accessibilityHidden(true)
            if let place = viewModel.placeName {
                Text(place)
                    .font(Font.hz.bodyStrong)
                    .foregroundStyle(Color.hz.textSecondary)
                    .lineLimit(1)
                    .accessibilityLabel("현재 위치, \(place)")
            } else {
                SkeletonBar(width: 120, height: 14)
            }
            Spacer()
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.hz.iconPrimary)
                    .frame(width: HZSize.touch, height: HZSize.touch)
            }
            .accessibilityLabel("검색")
        }
        .padding(.leading, HZSpace.screen)
        .padding(.trailing, HZSpace.s2)
        .frame(height: 56)
    }

    // MARK: 내용

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .failed:
            HZStateView(
                symbol: "wifi.exclamationmark", title: "불러오지 못했어요",
                message: "주변 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
            ) {
                HZStateButton("다시 시도") { Task { await viewModel.reload() } }
            }
        case .loaded:
            if let feed = viewModel.feed, !feed.isEmpty {
                loaded(feed)
            } else {
                HZStateView(
                    symbol: "mappin.slash", title: "근처에 이번 주 볼거리가 없어요", message: "지도에서 다른 동네를 둘러보세요."
                ) {
                    HZStateButton("지도로 보기", action: onShowMap)
                }
            }
        }
    }

    private func loaded(_ feed: HomeFeed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let headline = viewModel.headline {
                Text("\(headline.line1)\n\(headline.line2)")
                    .hzText(.display)
                    .foregroundStyle(Color.hz.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HZSpace.screen)
                    .padding(.top, HZSpace.s2)
                    .accessibilityLabel("\(headline.line1) \(headline.line2)")
                    .accessibilityAddTraits(.isHeader)
            }
            bannerView
            categoryRow
                .padding(.top, HZSpace.s5)
            if let hero = feed.hero {
                VStack(alignment: .leading, spacing: HZSpace.s3) {
                    HZSectionHeader(hero.title) { onOpenList(hero.listFilter) }
                    NavigationLink(value: hero.spot) {
                        HeroCard(
                            spot: hero.spot, badge: viewModel.clock.heroBadge(hero.spot),
                            meta: viewModel.clock.heroMeta(hero.spot), isSaved: viewModel.isSaved(hero.spot)
                        ) {
                            viewModel.toggleSave(hero.spot)
                        }
                    }
                    .buttonStyle(CardPressStyle())
                    .padding(.horizontal, HZSpace.screen)
                }
                .padding(.top, HZSpace.s8)
            }
            ForEach(feed.sections) { section in
                VStack(alignment: .leading, spacing: HZSpace.s3) {
                    HZSectionHeader(section.kind.title) { onOpenList(section.kind.listFilter) }
                    tileRow(section)
                }
                .padding(.top, HZSpace.s8)
            }
            Button("전체 목록 보기") { onOpenList(HomeListFilter(when: .week)) }
                .buttonStyle(HZSecondaryButtonStyle())
                .padding(.horizontal, HZSpace.screen)
                .padding(.top, HZSpace.s8)
            Text("3km 안 볼거리를 거리순으로 모두 볼 수 있어요")
                .font(Font.hz.caption)
                .foregroundStyle(Color.hz.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, HZSpace.s2)
        }
    }

    @ViewBuilder private var bannerView: some View {
        if viewModel.isUsingFallbackLocation, let banner {
            LocationBanner(actionTitle: banner.actionTitle, action: banner.action)
                .padding(.top, HZSpace.s4)
        }
    }

    /// 카테고리 줄: 글자 알약(S1b 칩과 같은 `HZPill`). `전체`는 잉크, 나머지는 카테고리 색 점 + 이름.
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HZSpace.s2) {
                Button {
                    onOpenList(HomeListFilter())
                } label: {
                    HZPill("전체", selected: true)
                }
                .buttonStyle(.plain)
                .accessibilityRemoveTraits(.isSelected)
                ForEach(SpotCategory.allCases, id: \.self) { category in
                    Button {
                        onOpenList(HomeListFilter(categories: [category]))
                    } label: {
                        HZPill(category.displayName, dot: category.color, selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HZSpace.screen)
        }
    }

    private func tileRow(_ section: HomeFeed.Section) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: HZSpace.s3) {
                ForEach(section.items) { spot in
                    NavigationLink(value: spot) {
                        SpotTile(spot: spot, badge: tileBadge(spot, section.kind))
                    }
                    .buttonStyle(CardPressStyle())
                    .contextMenu {
                        Button(
                            viewModel.isSaved(spot) ? "저장 취소" : "저장",
                            systemImage: viewModel.isSaved(spot) ? "bookmark.slash" : "bookmark"
                        ) {
                            viewModel.toggleSave(spot)
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, HZSpace.screen, for: .scrollContent)
        .accessibilityElement(children: .contain)
    }

    private func tileBadge(_ spot: Spot, _ kind: HomeFeed.SectionKind) -> SpotTile.Badge? {
        switch viewModel.tileBadge(spot, in: kind) {
        case .free: .free
        case .text(let text): .text(text)
        case nil: nil
        }
    }

    // MARK: 로딩 (헤드라인·섹션 자리 스켈레톤, 카테고리 줄은 바로)

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: HZSpace.s3) {
            SkeletonBar(width: 170, height: 26).padding(.top, HZSpace.s2)
            SkeletonBar(width: 230, height: 26)
            categoryRow
                .padding(.horizontal, -HZSpace.screen)
                .padding(.top, HZSpace.s2)
            SkeletonBar(width: 150, height: 19).padding(.top, HZSpace.s6)
            RoundedRectangle(cornerRadius: HZRadius.lg)
                .fill(Color.hz.bgSecondary)
                .frame(height: 200)
            SkeletonBar(width: 150, height: 19).padding(.top, HZSpace.s6)
            HStack(spacing: HZSpace.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: HZRadius.md)
                        .fill(Color.hz.bgSecondary)
                        .frame(width: 148, height: 112)
                }
            }
        }
        .padding(.horizontal, HZSpace.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("불러오는 중")
    }
}

/// 카드 누름: 0.98 축소 + 불투명도 90% (motion.fast).
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(HZMotion.fast, value: configuration.isPressed)
    }
}

struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: HZRadius.xs)
            .fill(Color.hz.bgSecondary)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
