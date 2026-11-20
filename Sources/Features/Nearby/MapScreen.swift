import DesignSystem
import Domain
import MapUI
import SwiftUI

/// "목록으로 보기"가 넘기는 값. `origin`이 있으면 지도에서 다른 동네를 다시 찾은 것 — 목록도 그 중심 기준.
public struct MapListRequest: Hashable, Sendable {
    public let filter: HomeListFilter
    public let origin: Coordinate?
    public let placeName: String?
}

/// S2 지도 탭 (herezi-api docs/design/screens/S2-map.md).
/// 위치명·검색 / 기간 탭 / 칩 줄 위에, 네이버 지도 + 핀·클러스터 + "이 지역에서 다시 찾기" + 내 위치 + 목록으로 보기 + 시트.
public struct NearbyMapScreen: View {
    @State private var viewModel: MapViewModel
    let banner: LocationBannerConfig?
    let onSearch: (() -> Void)?
    let onShowList: ((MapListRequest) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 시트 접힘 높이 (DESIGN §6.5).
    static let collapsedHeight: CGFloat = 88

    public init(
        viewModel: MapViewModel, banner: LocationBannerConfig? = nil, onSearch: (() -> Void)? = nil,
        onShowList: ((MapListRequest) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.banner = banner
        self.onSearch = onSearch
        self.onShowList = onShowList
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            NearbyFilters(viewModel: viewModel)
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    map
                    floatingTop
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        bottomControls
                            .padding(.bottom, HZSpace.s4)
                            .hzToast(message: $viewModel.toastMessage)
                        MapSpotSheet(viewModel: viewModel, maxHeight: proxy.size.height * 0.6)
                    }
                }
            }
        }
        .background(Color.hz.bgPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.start() }
        .onChange(of: viewModel.state) { _, state in
            if state == .loaded {
                AccessibilityNotification.Announcement(viewModel.sheetTitle).post()
            }
        }
    }

    // MARK: - 위

    private var topBar: some View {
        HStack(spacing: HZSpace.s2) {
            Text(viewModel.placeName ?? " ")
                .hzText(.title2)
                .foregroundStyle(Color.hz.textPrimary)
                .lineLimit(1)
                .accessibilityLabel("현재 위치, \(viewModel.placeName ?? "")")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let onSearch {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.hz.iconPrimary)
                        .frame(width: HZSize.touch, height: HZSize.touch)
                }
                .accessibilityLabel("검색")
            }
        }
        .padding(.leading, HZSpace.screen)
        .padding(.trailing, HZSpace.s3)
        .frame(minHeight: 56)
        .background(Color.hz.bgPrimary)
    }

    @ViewBuilder private var floatingTop: some View {
        VStack(spacing: HZSpace.s3) {
            if viewModel.isUsingFallbackLocation, let banner {
                LocationBanner(actionTitle: banner.actionTitle, action: banner.action)
                    .padding(.top, HZSpace.s2)
                    .hzElevation(.level1)
            }
            if viewModel.showsSearchHere || viewModel.isSearchingHere {
                FloatingPill(
                    title: "이 지역에서 다시 찾기", symbol: "arrow.clockwise", light: true,
                    spinning: viewModel.state == .loading
                ) {
                    Task { await viewModel.searchThisArea() }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, HZSpace.s3)
        .animation(HZMotion.adjusted(HZMotion.base, reduceMotion: reduceMotion), value: viewModel.showsSearchHere)
    }

    // MARK: - 지도

    @ViewBuilder private var map: some View {
        if SpotMapView.isConfigured {
            SpotMapView(
                spots: viewModel.spots, selectedID: viewModel.selectedSpotID, camera: viewModel.camera,
                showsUserLocation: !viewModel.isUsingFallbackLocation,
                bottomInset: Self.collapsedHeight,
                onSelect: { spot in
                    withAnimation(HZMotion.adjusted(HZMotion.slow, reduceMotion: reduceMotion)) {
                        viewModel.select(spot.id)
                    }
                },
                onTapMap: {
                    withAnimation(HZMotion.adjusted(HZMotion.slow, reduceMotion: reduceMotion)) {
                        viewModel.deselect()
                    }
                },
                onCameraIdle: { bounds, byUser in viewModel.cameraDidBecomeIdle(bounds: bounds, byUser: byUser) }
            )
            .ignoresSafeArea(edges: .bottom)
        } else {
            // 지도 키 없음(개발 빌드).
            ZStack {
                Color.hz.bgSecondary
                Text("지도를 불러오지 못했어요")
                    .font(Font.hz.body)
                    .foregroundStyle(Color.hz.textSecondary)
            }
        }
    }

    // MARK: - 아래

    private var bottomControls: some View {
        ZStack {
            if let onShowList {
                FloatingPill(title: "목록으로 보기", symbol: "list.bullet") {
                    onShowList(
                        MapListRequest(
                            filter: viewModel.currentFilter,
                            origin: viewModel.hasSearchedElsewhere ? viewModel.searchedBounds?.center : nil,
                            placeName: viewModel.hasSearchedElsewhere ? viewModel.placeName : nil))
                }
            }
            if SpotMapView.isConfigured {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            if await !viewModel.moveToMyLocation() { banner?.action() }
                        }
                    } label: {
                        Image(systemName: viewModel.isFollowingUser ? "location.fill" : "location")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.hz.iconPrimary)
                            .frame(width: HZSize.touch, height: HZSize.touch)
                            .background(Circle().fill(Color.hz.bgPrimary))
                            .hzElevation(.level1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("내 위치로 이동")
                }
                .padding(.horizontal, HZSpace.s4)
            }
        }
    }
}

/// 지도 바텀시트 `SpotSheet` (DESIGN §6.5): 접힘(요약 한 줄) / 카드(SpotCard 1장) / 펼침(화면 60%, 목록).
/// 탭 바 위에 붙는 시트라 시스템 `.sheet` 대신 직접 그린다. 스크림 없음.
struct MapSpotSheet: View {
    let viewModel: MapViewModel
    let maxHeight: CGFloat
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.hz.border)
                .frame(width: 36, height: 4)
                .padding(.top, HZSpace.s2)
                .padding(.bottom, HZSpace.s2)
                .accessibilityHidden(true)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: fixedHeight.map { max(NearbyMapScreen.collapsedHeight, $0 - drag) }, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: HZRadius.xl, topTrailingRadius: HZRadius.xl)
                .fill(Color.hz.bgPrimary)
                .hzElevation(.level2)
                .ignoresSafeArea(edges: .bottom)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    withAnimation(HZMotion.adjusted(HZMotion.slow, reduceMotion: reduceMotion)) {
                        if value.translation.height < -40 {
                            viewModel.expandSheet()
                        } else if value.translation.height > 40 {
                            viewModel.lowerSheet()
                        }
                    }
                }
        )
        .accessibilityAction(named: "목록 펼치기") { viewModel.expandSheet() }
        .accessibilityAction(named: "목록 접기") { viewModel.lowerSheet() }
    }

    /// 카드 단계는 내용 높이를 따른다(다이나믹 타입).
    private var fixedHeight: CGFloat? {
        switch viewModel.sheet {
        case .collapsed: NearbyMapScreen.collapsedHeight
        case .card: nil
        case .expanded: maxHeight
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.sheet {
        case .card:
            if let spot = viewModel.selectedSpot {
                SpotRowLink(spot: spot) {
                    SpotCard(spot: spot, distanceMeters: .some(viewModel.distance(to: spot)))
                }
                .padding(.bottom, HZSpace.s2)
            } else {
                summary
            }
        case .collapsed:
            summary
        case .expanded:
            VStack(spacing: 0) {
                summary
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.listSpots) { spot in
                            SpotRowLink(spot: spot) {
                                SpotCard(spot: spot, distanceMeters: .some(viewModel.distance(to: spot)))
                            }
                        }
                    }
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: HZSpace.s2) {
            Text(viewModel.sheetTitle)
                .hzText(.title3)
                .foregroundStyle(Color.hz.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let action = viewModel.sheetAction {
                Button(action.title) { Task { await viewModel.perform(action) } }
                    .buttonStyle(HZTextButtonStyle(.caption, color: Color.hz.textPrimary))
            }
        }
        .padding(.horizontal, HZSpace.screen)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(HZMotion.adjusted(HZMotion.slow, reduceMotion: reduceMotion)) {
                if viewModel.sheet == .expanded { viewModel.lowerSheet() } else { viewModel.expandSheet() }
            }
        }
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("지도") {
    NavigationStack {
        NearbyMapScreen(
            viewModel: MapViewModel(service: FakeSpotsService(), location: FixedLocationProvider()),
            onShowList: { _ in })
    }
}
