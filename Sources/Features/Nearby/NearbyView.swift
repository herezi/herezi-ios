import Domain
import MapUI
import SwiftUI

/// "지금 내 주변" screen: filters on top, list or map below.
/// Rows push `Spot` values; the App layer registers `.navigationDestination(for: Spot.self)`.
public struct NearbyView: View {
    @State private var viewModel: NearbyViewModel

    public init(viewModel: NearbyViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("지금 내 주변")
        .toolbar { whenMenu }
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
            .padding(.horizontal)
            CategoryChips(viewModel: viewModel)
            if viewModel.isUsingFallbackLocation {
                Label("위치를 확인할 수 없어 서울시청 기준으로 보여드려요", systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
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
            ProgressView("주변을 둘러보는 중…")
        case .failed(let message):
            ContentUnavailableView {
                Label("불러오지 못했어요", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("다시 시도") { Task { await viewModel.reload() } }
            }
        default:
            if viewModel.visibleSpots.isEmpty {
                ContentUnavailableView(
                    "근처에 지금 볼 만한 게 없어요", systemImage: "mappin.slash",
                    description: Text("필터를 바꾸거나 기간을 늘려 보세요."))
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
                    SpotRow(spot: selected)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding()
            }
        }
    }
}

struct CategoryChips: View {
    let viewModel: NearbyViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("무료", symbol: "gift", selected: viewModel.freeOnly) {
                    await viewModel.setFreeOnly(!viewModel.freeOnly)
                }
                Divider().frame(height: 20)
                chip("전체", symbol: "square.grid.2x2", selected: viewModel.selectedCategories.isEmpty) {
                    await viewModel.clearCategories()
                }
                ForEach(SpotCategory.allCases, id: \.self) { category in
                    chip(category.displayName, symbol: category.symbolName, selected: viewModel.isSelected(category)) {
                        await viewModel.toggle(category)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(
        _ title: String, symbol: String, selected: Bool, action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
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
