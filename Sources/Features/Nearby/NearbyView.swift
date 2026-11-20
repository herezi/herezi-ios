import DesignSystem
import Domain
import MapUI
import SwiftUI

/// S1b 전체 목록 (herezi-api docs/design/screens/S1b-list.md).
/// 행은 `Spot` 값을 push 한다. App 레이어가 `.navigationDestination(for: Spot.self)`를 등록한다.
public struct NearbyView: View {
    @State private var viewModel: NearbyViewModel
    let placeName: String
    let banner: LocationBannerConfig?
    let onSearch: (() -> Void)?
    let onShowMap: ((HomeListFilter) -> Void)?

    public init(
        viewModel: NearbyViewModel, placeName: String = "내 주변", banner: LocationBannerConfig? = nil,
        onSearch: (() -> Void)? = nil, onShowMap: ((HomeListFilter) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.placeName = placeName
        self.banner = banner
        self.onSearch = onSearch
        self.onShowMap = onShowMap
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 현재 위치명 (iOS 26 상단 바 버튼 안에서는 잘려서 바로 아래 줄에 둔다).
            Text(placeName)
                .hzText(.title2)
                .foregroundStyle(Color.hz.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HZSpace.screen)
                .accessibilityLabel("현재 위치, \(placeName)")
                .accessibilityAddTraits(.isHeader)
            NearbyFilters(viewModel: viewModel)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.hz.bgPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onSearch {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSearch) { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("검색")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let onShowMap {
                FloatingPill(title: "지도로 보기", symbol: "map") { onShowMap(viewModel.currentFilter) }
                    .padding(.bottom, HZSpace.s4)
            }
        }
        .task {
            if viewModel.state == .idle { await viewModel.reload() }
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .loaded {
                AccessibilityNotification.Announcement("3km 안에 볼거리 \(viewModel.visibleSpots.count)개").post()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 0) {
                bannerView
                HZSkeletonList()
            }
        case .failed:
            VStack(spacing: 0) {
                bannerView
                HZStateView(
                    symbol: "wifi.exclamationmark", title: "불러오지 못했어요",
                    message: "주변 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
                ) {
                    HZStateButton("다시 시도") { Task { await viewModel.reload() } }
                }
            }
        case .loaded:
            if viewModel.visibleSpots.isEmpty {
                VStack(spacing: 0) {
                    bannerView
                    emptyState
                }
            } else {
                list
            }
        }
    }

    @ViewBuilder private var bannerView: some View {
        if viewModel.isUsingFallbackLocation, let banner {
            LocationBanner(actionTitle: banner.actionTitle, action: banner.action)
                .padding(.top, HZSpace.s3)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if viewModel.hasActiveFilter
            && !(viewModel.when == .week && viewModel.selectedCategories.isEmpty
                && !viewModel.freeOnly)
        {
            HZStateView(
                symbol: "mappin.slash", title: "조건에 맞는 볼거리가 없어요", message: "필터를 바꾸거나 기간을 늘려 보세요."
            ) {
                HZStateButton("필터 초기화") { Task { await viewModel.resetFilters() } }
            }
        } else {
            HZStateView(
                symbol: "mappin.slash", title: "근처에 지금 볼 만한 게 없어요", message: "기간을 늘리거나 지도를 움직여 보세요."
            ) {
                if viewModel.when == .week {
                    if let onShowMap {
                        HZStateButton("지도로 보기") { onShowMap(viewModel.currentFilter) }
                    }
                } else {
                    HZStateButton("이번 주로 보기") { Task { await viewModel.setWhen(.week) } }
                }
            }
        }
    }

    private var list: some View {
        List {
            Group {
                bannerView
                Text(viewModel.resultSummary)
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.horizontal, HZSpace.screen)
                ForEach(viewModel.visibleSpots) { spot in
                    SpotRowLink(spot: spot) { SpotCard(spot: spot) }
                        .task { await viewModel.loadMoreIfNeeded(current: spot) }
                }
                listFooter
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.hz.bgPrimary)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .refreshable { await viewModel.reload() }
    }

    @ViewBuilder private var listFooter: some View {
        if viewModel.loadMoreFailed {
            HStack(spacing: HZSpace.s2) {
                Text("더 불러오지 못했어요")
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textSecondary)
                Button("다시 시도") { Task { await viewModel.loadMore() } }
                    .buttonStyle(HZTextButtonStyle(.caption, color: Color.hz.textPrimary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HZSpace.s4)
        } else if viewModel.nextCursor == nil {
            Text("여기까지예요")
                .font(Font.hz.caption)
                .foregroundStyle(Color.hz.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HZSpace.s6)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, HZSpace.s4)
        }
    }
}

/// 기간 탭 + 칩 줄 (S1b·S2 공통).
struct NearbyFilters: View {
    let viewModel: NearbyViewModel

    var body: some View {
        VStack(spacing: 0) {
            WhenTabs(selected: viewModel.when) { option in
                Task { await viewModel.setWhen(option) }
            }
            CategoryChips(viewModel: viewModel)
                .padding(.top, HZSpace.s1)
                .padding(.bottom, HZSpace.s2)
            Color.hz.border.frame(height: 1)
        }
        .background(Color.hz.bgPrimary)
    }
}

/// 기간 탭 (DESIGN §6.3): 글자 탭, 선택 = text.primary Bold, 비선택 = text.tertiary.
struct WhenTabs: View {
    let selected: WhenFilter
    let onSelect: (WhenFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HZSpace.s5) {
                ForEach(WhenFilter.allCases, id: \.self) { option in
                    let isSelected = option == selected
                    Button {
                        withAnimation(HZMotion.fast) { onSelect(option) }
                    } label: {
                        Text(option.displayName)
                            .font(HZTextStyle.title3.font(weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? Color.hz.textPrimary : Color.hz.textTertiary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.displayName), 기간")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, HZSpace.screen)
        }
    }
}

/// S2 지도 탭. 기간 탭·칩 + 네이버 지도 + "목록으로 보기".
public struct NearbyMapScreen: View {
    @State private var viewModel: NearbyViewModel
    let banner: LocationBannerConfig?
    let onShowList: ((HomeListFilter) -> Void)?

    public init(
        viewModel: NearbyViewModel, banner: LocationBannerConfig? = nil,
        onShowList: ((HomeListFilter) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.banner = banner
        self.onShowList = onShowList
    }

    public var body: some View {
        VStack(spacing: 0) {
            NearbyFilters(viewModel: viewModel)
            if viewModel.isUsingFallbackLocation, let banner {
                LocationBanner(actionTitle: banner.actionTitle, action: banner.action)
                    .padding(.vertical, HZSpace.s2)
            }
            NearbyMap(spots: viewModel.visibleSpots, center: viewModel.coordinate ?? .seoulCityHall)
                .overlay(alignment: .bottom) {
                    if let onShowList {
                        FloatingPill(title: "목록으로 보기", symbol: "list.bullet") {
                            onShowList(viewModel.currentFilter)
                        }
                        .padding(.bottom, HZSpace.s4)
                    }
                }
        }
        .background(Color.hz.bgPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.state == .idle { await viewModel.reload() }
        }
    }
}

/// Map mode: Naver map (via MapUI) + a bottom card for the tapped marker that pushes the detail.
struct NearbyMap: View {
    let spots: [Spot]
    let center: Coordinate
    @State private var selected: Spot?

    var body: some View {
        SpotMapView(spots: spots, center: center) { spot in
            selected = spot
        }
        .overlay(alignment: .bottom) {
            if let selected, spots.contains(selected) {
                NavigationLink(value: selected) {
                    SpotCard(spot: selected)
                        .background(Color.hz.bgPrimary, in: RoundedRectangle(cornerRadius: HZRadius.lg))
                        .hzElevation(.level1)
                }
                .buttonStyle(.plain)
                .padding(HZSpace.s4)
                .padding(.bottom, 56)
            }
        }
    }
}

/// 플로팅 알약 (DESIGN §6.10): 높이 44, 잉크 배경, 흰 caption Bold + 아이콘 16.
struct FloatingPill: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(HZTextStyle.caption.font(weight: .bold))
            }
            .foregroundStyle(Color.hz.textInverse)
            .padding(.horizontal, HZSpace.s4)
            .frame(height: 44)
            .background(Color.hz.bgInverse, in: Capsule())
            .hzElevation(.level1)
        }
        .buttonStyle(.plain)
    }
}

/// S1b 칩 줄 (DESIGN §6.2): `무료만 │ 전체 · 카테고리…`. 홈 카테고리 줄과 같은 `HZPill`을 쓴다.
struct CategoryChips: View {
    let viewModel: NearbyViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HZSpace.s2) {
                chip(
                    HZPill("무료만", leadingSymbol: viewModel.freeOnly ? "checkmark" : nil, selected: viewModel.freeOnly)
                ) {
                    await viewModel.setFreeOnly(!viewModel.freeOnly)
                }
                Rectangle()
                    .fill(Color.hz.border)
                    .frame(width: 1, height: 16)
                chip(HZPill("전체", selected: viewModel.selectedCategories.isEmpty)) {
                    await viewModel.clearCategories()
                }
                ForEach(SpotCategory.allCases, id: \.self) { category in
                    chip(
                        HZPill(category.displayName, dot: category.color, selected: viewModel.isSelected(category))
                    ) {
                        await viewModel.toggle(category)
                    }
                }
            }
            .padding(.horizontal, HZSpace.screen)
        }
    }

    private func chip(_ pill: HZPill, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            pill
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

#Preview("목록") {
    NavigationStack {
        NearbyView(viewModel: NearbyViewModel(service: FakeSpotsService(), location: FixedLocationProvider()))
    }
}
