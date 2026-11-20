import DesignSystem
import Domain
import MapUI
import SwiftUI

/// "지금 내 주변" screen: filters on top, list or map below.
/// Rows push `Spot` values; the App layer registers `.navigationDestination(for: Spot.self)`.
public struct NearbyView: View {
    @State private var viewModel: NearbyViewModel
    /// 다른 화면으로 가는 입구 (App이 연결). 홈 재설계 전까지 상단 바 아이콘으로 둔다.
    let onSearch: (() -> Void)?
    let onSaved: (() -> Void)?
    let onSettings: (() -> Void)?

    public init(
        viewModel: NearbyViewModel, onSearch: (() -> Void)? = nil, onSaved: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSearch = onSearch
        self.onSaved = onSaved
        self.onSettings = onSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("지금 내 주변")
        .toolbar {
            whenMenu
            entryPoints
        }
        .task {
            if viewModel.state == .idle { await viewModel.reload() }
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            Picker("보기", selection: $viewModel.mode) {
                ForEach(NearbyViewModel.DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, HZSpace.screen)
            CategoryChips(viewModel: viewModel)
            if viewModel.isUsingFallbackLocation {
                Label("위치를 확인할 수 없어 서울시청 기준으로 보여드려요", systemImage: "location.slash")
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, HZSpace.s3)
                    .padding(.horizontal, HZSpace.s4)
                    .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
                    .padding(.horizontal, HZSpace.screen)
            }
        }
        .padding(.vertical, HZSpace.s2)
    }

    @ToolbarContentBuilder private var entryPoints: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if let onSaved {
                Button(action: onSaved) { Image(systemName: "bookmark") }
                    .accessibilityLabel("저장")
            }
            if let onSettings {
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("설정")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let onSearch {
                Button(action: onSearch) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("검색")
            }
        }
    }

    private var whenMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(WhenFilter.allCases, id: \.self) { option in
                    Button {
                        Task { await viewModel.setWhen(option) }
                    } label: {
                        if option == viewModel.when {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                Label(viewModel.when.displayName, systemImage: "calendar")
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle,
            .loading where viewModel.spots.isEmpty:
            HZSkeletonList()
        case .failed(let message):
            HZStateView(symbol: "wifi.exclamationmark", title: "불러오지 못했어요", message: message) {
                HZStateButton("다시 시도") { Task { await viewModel.reload() } }
            }
        default:
            if viewModel.visibleSpots.isEmpty {
                HZStateView(
                    symbol: "mappin.slash", title: "근처에 지금 볼 만한 게 없어요",
                    message: "필터를 바꾸거나 기간을 늘려 보세요.")
            } else if viewModel.mode == .list {
                SpotList(spots: viewModel.visibleSpots) { await viewModel.reload() }
            } else {
                NearbyMap(spots: viewModel.visibleSpots, center: viewModel.coordinate ?? .seoulCityHall)
            }
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
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            if let selected, spots.contains(selected) {
                NavigationLink(value: selected) {
                    SpotCard(spot: selected)
                        .background(Color.hz.bgPrimary, in: RoundedRectangle(cornerRadius: HZRadius.lg))
                        .hzElevation(.level1)
                }
                .buttonStyle(.plain)
                .padding(HZSpace.s4)
            }
        }
    }
}

struct CategoryChips: View {
    let viewModel: NearbyViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HZSpace.s2) {
                chip("무료만", symbol: viewModel.freeOnly ? "checkmark" : nil, tint: nil, selected: viewModel.freeOnly) {
                    await viewModel.setFreeOnly(!viewModel.freeOnly)
                }
                Rectangle()
                    .fill(Color.hz.border)
                    .frame(width: 1, height: 16)
                chip("전체", symbol: nil, tint: nil, selected: viewModel.selectedCategories.isEmpty) {
                    await viewModel.clearCategories()
                }
                ForEach(SpotCategory.allCases, id: \.self) { category in
                    chip(
                        category.displayName, symbol: category.symbolName, tint: category.color,
                        selected: viewModel.isSelected(category)
                    ) {
                        await viewModel.toggle(category)
                    }
                }
            }
            .padding(.horizontal, HZSpace.screen)
        }
    }

    /// 칩 (DESIGN §6.2): 높이 36, 좌우 14, radius.full, caption. 선택 = 잉크 배경·흰 글자.
    private func chip(
        _ title: String, symbol: String?, tint: Color?, selected: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: HZSpace.s1) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? Color.hz.textInverse : (tint ?? Color.hz.textPrimary))
                }
                Text(title)
                    .font(selected ? Font.hz.caption.weight(.semibold) : Font.hz.caption)
                    .foregroundStyle(selected ? Color.hz.textInverse : Color.hz.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(height: HZSize.chip)
            .background(selected ? Color.hz.bgInverse : Color.hz.bgSecondary, in: Capsule())
            .frame(minHeight: HZSize.touch)
            .contentShape(Rectangle())
            .animation(HZMotion.fast, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview("목록") {
    NavigationStack {
        NearbyView(viewModel: NearbyViewModel(service: FakeSpotsService(), location: FixedLocationProvider()))
    }
}

#Preview("에러") {
    NavigationStack {
        NearbyView(
            viewModel: NearbyViewModel(
                service: FakeSpotsService(failure: FakeSpotsService.FakeError.notFound),
                location: FixedLocationProvider()))
    }
}
