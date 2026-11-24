import DesignSystem
import Domain
import SwiftUI
import UIKit

/// S3 상세 (herezi-api docs/design/screens/S3-detail.md).
/// 대표 이미지 → 제목 블록 → (종료 안내) → 정보 행 → 요약 → 출처 카드 → 오류 제보, 하단 고정 길찾기 바.
public struct SpotDetailView: View {
    @State private var viewModel: SpotDetailViewModel
    let onGoHome: () -> Void

    @State private var barVisible = false
    @State private var browser: BrowserLink?
    @Environment(\.openURL) private var openURL

    public init(viewModel: SpotDetailViewModel, onGoHome: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onGoHome = onGoHome
    }

    public var body: some View {
        content
            .background(Color.hz.bgPrimary)
            .navigationTitle(barVisible ? (viewModel.spot?.title ?? "") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(barVisible || viewModel.spot == nil ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(Color.hz.bgPrimary, for: .navigationBar)
            .toolbar { toolbarItems }
            // 하단 길찾기 바와 겹치지 않게 상세에서는 탭 바를 숨긴다.
            .toolbar(.hidden, for: .tabBar)
            .task { await viewModel.load() }
            .hzToast(message: $viewModel.toastMessage)
            .sheet(item: $browser) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            DetailSkeleton()
        case .notFound:
            HZStateView(
                symbol: "mappin.slash", title: "끝났거나 없는 볼거리예요", message: "목록에서 다른 볼거리를 찾아보세요."
            ) {
                VStack(spacing: HZSpace.s2) {
                    HZStateButton("주변 보기", action: onGoHome)
                    if viewModel.isSaved {
                        Button("저장에서 지우기") { viewModel.removeFromSaved() }
                            .buttonStyle(HZTextButtonStyle())
                    }
                }
            }
        case .failed:
            HZStateView(symbol: "wifi.exclamationmark", title: "불러오지 못했어요", message: "잠시 후 다시 시도해 주세요.") {
                HZStateButton("다시 시도") { Task { await viewModel.load() } }
            }
        case .loaded:
            if let spot = viewModel.spot {
                loaded(spot)
            }
        }
    }

    // MARK: 데이터 있음

    private func loaded(_ spot: Spot) -> some View {
        GeometryReader { outer in
            let threshold = outer.safeAreaInsets.top + 44
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(spot, topInset: threshold)
                        .onGeometryChange(for: Bool.self) { proxy in
                            proxy.frame(in: .scrollView).maxY < threshold
                        } action: { passed in
                            withAnimation(HZMotion.fast) { barVisible = passed }
                        }
                    titleBlock(spot)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.top, HZSpace.s5)
                    if let notice = viewModel.endedNotice {
                        Text(notice)
                            .font(Font.hz.caption)
                            .foregroundStyle(Color.hz.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(HZSpace.s3)
                            .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
                            .padding(.horizontal, HZSpace.screen)
                            .padding(.top, HZSpace.s4)
                    }
                    infoRows(spot)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.top, HZSpace.s5)
                    Color.hz.bgSecondary
                        .frame(height: 8)
                        .padding(.top, HZSpace.s6)
                    if let summary = spot.summary {
                        Text(summary)
                            .hzText(.body)
                            .foregroundStyle(Color.hz.textPrimary)
                            .padding(.horizontal, HZSpace.screen)
                            .padding(.top, HZSpace.s6)
                    }
                    sourceCard(spot)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.top, HZSpace.s6)
                    reportButton
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.top, HZSpace.s3)
                        .padding(.bottom, HZSpace.s6)
                }
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
    }

    private func hero(_ spot: Spot, topInset: CGFloat) -> some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { SpotImage(spot: spot, fallback: .poster(.init(topInset: topInset))) }
            .clipped()
    }

    private func titleBlock(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: HZSpace.s2) {
            if spot.isEnded || spot.isFree == true {
                HStack(spacing: HZSpace.s2) {
                    if spot.isEnded { HZBadge(.ended) }
                    if spot.isFree == true { HZBadge(.free) }
                }
            }
            HStack(spacing: 6) {
                CategoryDot(spot.category)
                Text(spot.category.displayName)
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textSecondary)
            }
            Text(spot.title)
                .hzText(.title1)
                .foregroundStyle(Color.hz.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func infoRows(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: HZSpace.s3) {
            if let period = viewModel.periodText {
                InfoRow(symbol: "calendar", label: "기간", value: period, note: viewModel.periodNote)
            }
            if let time = viewModel.timeText {
                InfoRow(symbol: "clock", label: "시간", value: time)
            }
            if let place = spot.placeName ?? spot.address {
                InfoRow(
                    symbol: "mappin.and.ellipse", label: "장소", value: place,
                    note: spot.placeName == nil ? nil : spot.address
                )
                .onLongPressGesture { copyAddress(spot) }
                .accessibilityAction(named: "주소 복사") { copyAddress(spot) }
            }
            if let distance = viewModel.distanceText {
                InfoRow(symbol: "figure.walk", label: "거리", value: distance)
            }
        }
    }

    private func copyAddress(_ spot: Spot) {
        UIPasteboard.general.string = spot.address ?? spot.placeName
        viewModel.addressCopied()
    }

    private func sourceCard(_ spot: Spot) -> some View {
        HStack(alignment: .center, spacing: HZSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.sourceText ?? "")
                Text(viewModel.fetchedText ?? "")
                    .monospacedDigit()
                    .accessibilityLabel(
                        "\(viewModel.fetchedText ?? ""), \(SpotFormatting.spokenDateTime(spot.fetchedAt))")
            }
            .font(Font.hz.caption)
            .foregroundStyle(Color.hz.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let url = spot.sourceURL {
                Button {
                    browser = BrowserLink(url)
                } label: {
                    HStack(spacing: 2) {
                        Text("원문 보기")
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(HZTextButtonStyle(.caption, color: Color.hz.textPrimary))
                .accessibilityHint("브라우저가 열려요")
            }
        }
        .padding(HZSpace.s4)
        .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
    }

    /// 오류 제보 행: 아이콘 + 제목 + 설명 + 화살표. 글자 버튼만으로는 신고 기능으로 보이지 않아서 행 형태로 둔다.
    private var reportButton: some View {
        Button {
            guard let url = viewModel.reportMailURL else { return }
            openURL(url) { accepted in
                if !accepted { viewModel.showMailUnavailable() }
            }
        } label: {
            HStack(spacing: HZSpace.s3) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.hz.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("정보가 달라요")
                        .font(Font.hz.bodyStrong)
                        .foregroundStyle(Color.hz.textPrimary)
                    Text("기간·장소·요금이 틀렸다면 알려 주세요")
                        .font(Font.hz.caption)
                        .foregroundStyle(Color.hz.textSecondary)
                }
                Spacer(minLength: HZSpace.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hz.iconSecondary)
            }
            .padding(HZSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: HZRadius.md).stroke(Color.hz.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: HZRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("정보가 달라요. 잘못된 정보 신고")
        .accessibilityHint("메일 앱이 열려요")
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Color.hz.border.frame(height: 1)
            Group {
                if viewModel.isEnded {
                    Button("장소 보기") { openMap() }
                        .buttonStyle(HZSecondaryButtonStyle())
                } else {
                    Button("네이버지도로 길찾기") { openMap() }
                        .buttonStyle(HZPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, HZSpace.screen)
            .padding(.vertical, HZSpace.s3)
        }
        .background(Color.hz.bgPrimary)
    }

    private func openMap() {
        guard let links = viewModel.mapLinks else { return }
        openURL(links.app) { accepted in
            if !accepted { openURL(links.web) }
        }
    }

    // MARK: 상단 바

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        if viewModel.state == .loaded, let shareText = viewModel.shareText {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    toolbarIcon("square.and.arrow.up")
                }
                .accessibilityLabel("공유")
                Button {
                    withAnimation(HZMotion.fast) { viewModel.toggleSave() }
                } label: {
                    toolbarIcon(viewModel.isSaved ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.selection, trigger: viewModel.isSaved)
                .accessibilityLabel(viewModel.isSaved ? "저장 취소" : "저장")
                .accessibilityValue(viewModel.isSaved ? "저장됨" : "")
            }
        }
    }

    /// 이미지 위에서는 흰 원 36(90%)을 깔아 대비를 확보한다.
    private func toolbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.hz.iconPrimary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white.opacity(barVisible ? 0 : 0.9)))
    }
}

/// 정보 행: 아이콘 20 + 값(bodyStrong) + 보조(caption). 스크린리더는 "기간, 값, 보조"로 한 번에 읽는다.
struct InfoRow: View {
    let symbol: String
    let label: String
    let value: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HZSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Color.hz.iconSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .hzText(.bodyStrong)
                    .foregroundStyle(Color.hz.textPrimary)
                if let note {
                    Text(note)
                        .font(Font.hz.caption)
                        .foregroundStyle(Color.hz.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, value, note].compactMap { $0 }.joined(separator: ", "))
    }
}

/// 로딩: 이미지 자리 + 제목 줄 2개 + 정보 행 3개 스켈레톤. 하단 바 없음.
struct DetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HZSpace.s3) {
            Color.hz.bgSecondary.aspectRatio(4 / 3, contentMode: .fit)
            Group {
                bar(0.5).padding(.top, HZSpace.s3)
                bar(0.8)
                bar(0.6).padding(.top, HZSpace.s3)
                bar(0.7)
                bar(0.4)
            }
            .padding(.horizontal, HZSpace.screen)
            Spacer()
        }
        .accessibilityElement()
        .accessibilityLabel("불러오는 중")
    }

    private func bar(_ fraction: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: HZRadius.xs)
                .fill(Color.hz.bgSecondary)
                .frame(width: proxy.size.width * fraction, height: 14)
        }
        .frame(height: 14)
    }
}

#Preview("진행 중") {
    NavigationStack {
        SpotDetailView(
            viewModel: SpotDetailViewModel(
                id: "sample-1", initial: SampleSpots.all[0], service: FakeSpotsService(),
                saved: SavedSpotsStore(defaults: UserDefaults(suiteName: "preview")!)))
    }
}

#Preview("종료됨") {
    NavigationStack {
        SpotDetailView(
            viewModel: SpotDetailViewModel(
                id: SampleSpots.endedID, service: FakeSpotsService(),
                saved: SavedSpotsStore(defaults: UserDefaults(suiteName: "preview")!)))
    }
}
