import DesignSystem
import Domain
import SwiftUI

/// S5 검색 (herezi-api docs/design/screens/S5-search.md).
/// 결과 카드는 `Spot` 값을 push 한다. App 레이어가 상세를 연다.
public struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    let autoFocus: Bool
    let initialQuery: String?

    /// - Parameter initialQuery: 들어오자마자 조회할 검색어 (Debug 실행 인자 등).
    public init(viewModel: SearchViewModel, autoFocus: Bool = true, initialQuery: String? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.autoFocus = autoFocus
        self.initialQuery = initialQuery
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.hz.bgPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .hzToast(message: $viewModel.toastMessage)
        .onAppear { if autoFocus && initialQuery == nil { focused = true } }
        .task {
            guard let initialQuery, viewModel.phase == .recent else { return }
            viewModel.text = initialQuery
            await viewModel.submit()
        }
        .onChange(of: viewModel.phase) { _, phase in
            if let summary = viewModel.resultSummary, case .results = phase {
                AccessibilityNotification.Announcement(summary).post()
            }
        }
    }

    // MARK: 검색 바

    private var searchBar: some View {
        HStack(spacing: HZSpace.s3) {
            HStack(spacing: HZSpace.s2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.hz.iconSecondary)
                    .accessibilityHidden(true)
                TextField(
                    "", text: $viewModel.text,
                    prompt: Text("축제, 전시, 장소 이름으로 찾기").foregroundStyle(Color.hz.textTertiary)
                )
                .font(Font.hz.body)
                .foregroundStyle(Color.hz.textPrimary)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { Task { await viewModel.submit() } }
                .onChange(of: viewModel.text) { _, text in
                    if text.isEmpty { viewModel.clearText() }
                }
                .accessibilityLabel("볼거리 검색")
                if !viewModel.text.isEmpty {
                    Button {
                        viewModel.clearText()
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.hz.iconSecondary)
                    }
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, HZSpace.s3)
            .frame(height: 44)
            .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
            Button("취소") { dismiss() }
                .buttonStyle(HZTextButtonStyle(.body, color: Color.hz.textPrimary))
        }
        .padding(.horizontal, HZSpace.screen)
        .padding(.vertical, HZSpace.s2)
    }

    // MARK: 내용

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .recent:
            recentList
        case .loading:
            HZSkeletonList()
        case .results(let spots):
            List {
                if let summary = viewModel.resultSummary {
                    Text(summary)
                        .font(Font.hz.caption)
                        .foregroundStyle(Color.hz.textSecondary)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.top, HZSpace.s3)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                ForEach(spots) { spot in
                    SpotRowLink(spot: spot) { SpotCard(spot: spot) }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.hz.bgPrimary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        case .empty:
            HZStateView(
                symbol: "magnifyingglass", title: viewModel.emptyTitle,
                message: "지금 진행 중인 것만 찾아요. 다른 이름으로 찾아보세요.")
        case .failed:
            HZStateView(symbol: "wifi.exclamationmark", title: "불러오지 못했어요", message: "잠시 후 다시 시도해 주세요.") {
                HZStateButton("다시 시도") { Task { await viewModel.retry() } }
            }
        }
    }

    @ViewBuilder private var recentList: some View {
        if viewModel.recents.isEmpty {
            Text("최근 검색이 없어요")
                .font(Font.hz.body)
                .foregroundStyle(Color.hz.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("최근 검색")
                            .font(Font.hz.caption)
                            .foregroundStyle(Color.hz.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("전체 삭제") { viewModel.clearRecents() }
                            .buttonStyle(HZTextButtonStyle(.caption))
                    }
                    ForEach(viewModel.recents, id: \.self) { term in
                        HStack(spacing: HZSpace.s3) {
                            Button {
                                focused = false
                                Task { await viewModel.selectRecent(term) }
                            } label: {
                                HStack(spacing: HZSpace.s3) {
                                    Image(systemName: "clock")
                                        .foregroundStyle(Color.hz.iconSecondary)
                                        .accessibilityHidden(true)
                                    Text(term)
                                        .font(Font.hz.body)
                                        .foregroundStyle(Color.hz.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(minHeight: HZSize.touch)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                viewModel.removeRecent(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.hz.iconSecondary)
                                    .frame(width: HZSize.touch, height: HZSize.touch)
                            }
                            .accessibilityLabel("\(term) 지우기")
                        }
                    }
                }
                .padding(.horizontal, HZSpace.screen)
                .padding(.top, HZSpace.s2)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

#Preview {
    NavigationStack {
        SearchView(
            viewModel: SearchViewModel(
                service: FakeSpotsService(),
                recents: RecentSearchesStore(defaults: UserDefaults(suiteName: "preview-search")!),
                origin: .seoulCityHall))
    }
}
