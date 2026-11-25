import DesignSystem
import Domain
import SwiftUI

/// S4 저장 목록 (herezi-api docs/design/screens/S4-saved.md).
/// 카드는 `Spot` 값을 push 한다. App 레이어가 `.navigationDestination(for: Spot.self)`로 상세를 연다.
public struct SavedView: View {
    @State private var viewModel: SavedViewModel
    let onBrowse: () -> Void

    @State private var toast: HZToast?
    @State private var confirmingClear = false

    /// 설정 톱니는 없다 — 설정은 하단 MY 탭(DESIGN §6.12).
    public init(viewModel: SavedViewModel, onBrowse: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onBrowse = onBrowse
    }

    public var body: some View {
        content
            .background(Color.hz.bgPrimary)
            .navigationTitle("저장")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(viewModel.isEditing ? "완료" : "편집") {
                            viewModel.setEditing(!viewModel.isEditing)
                        }
                        .foregroundStyle(Color.hz.textPrimary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isEditing {
                    Button(viewModel.deleteSelectedTitle) { Task { await viewModel.deleteSelected() } }
                        .buttonStyle(HZPrimaryButtonStyle())
                        .disabled(viewModel.selection.isEmpty)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.vertical, HZSpace.s3)
                        .background(Color.hz.bgPrimary)
                }
            }
            .onAppear { Task { await viewModel.refresh() } }
            .hzToast($toast) { Task { await viewModel.undo() } }
            .onChange(of: viewModel.toast) { _, new in
                guard let new else { return }
                toast =
                    new.undo
                    ? HZToast(new.message, actionTitle: "되돌리기", duration: .seconds(4)) : HZToast(new.message)
                viewModel.toast = nil
            }
            .confirmationDialog(
                viewModel.clearEndedPrompt, isPresented: $confirmingClear, titleVisibility: .visible
            ) {
                Button("지우기", role: .destructive) { Task { await viewModel.clearEnded() } }
                Button("취소", role: .cancel) {}
            }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.content {
        case .loggedOut:
            signInPrompt
        case .loading:
            HZSkeletonList()
        case .failed:
            HZStateView(symbol: "wifi.exclamationmark", title: "저장 목록을 불러오지 못했어요", message: "잠시 후 다시 시도해 주세요.") {
                HZStateButton("다시 시도") { Task { await viewModel.refresh(userInitiated: true) } }
            }
        case .empty:
            HZStateView(
                symbol: "bookmark", title: "저장한 볼거리가 없어요", message: "마음에 드는 곳을 저장해 두면 여기에 모여요."
            ) {
                HZStateButton("주변 둘러보기", action: onBrowse)
            }
            .refreshable { await viewModel.refresh(userInitiated: true) }
        case .list:
            list
        }
    }

    /// 로그인 전 본문 (`SignInPrompt`, 목업 saved-logged-out.png). 브랜드 버튼은 S7 시트에만 둔다.
    private var signInPrompt: some View {
        HZStateView(symbol: "bookmark", title: SavedViewModel.signInTitle, message: viewModel.signInMessage) {
            VStack(spacing: HZSpace.s3) {
                Button(action: viewModel.login) {
                    Text("로그인").padding(.horizontal, HZSpace.s8)
                }
                .buttonStyle(HZPrimaryButtonStyle(height: HZSize.buttonMedium, radius: HZRadius.sm))
                .fixedSize()
                .accessibilityHint("로그인 창이 열려요")
                Button("주변 둘러보기", action: onBrowse)
                    .buttonStyle(HZTextButtonStyle())
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.active) { row($0) }
            }
            if !viewModel.ended.isEmpty {
                Section {
                    ForEach(viewModel.ended) { row($0) }
                } header: {
                    endedHeader
                } footer: {
                    Text("끝난 지 90일이 지나면 자동으로 지워져요.")
                        .font(Font.hz.caption)
                        .foregroundStyle(Color.hz.textSecondary)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.vertical, HZSpace.s3)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .refreshable { await viewModel.refresh(userInitiated: true) }
    }

    private var endedHeader: some View {
        HStack {
            Text(viewModel.endedHeader)
                .font(Font.hz.caption)
                .foregroundStyle(Color.hz.textSecondary)
            Spacer()
            if !viewModel.isEditing {
                Button("모두 지우기") { confirmingClear = true }
                    .buttonStyle(HZTextButtonStyle(.caption))
            }
        }
        .padding(.horizontal, HZSpace.screen)
        .padding(.top, HZSpace.s6)
        .listRowInsets(EdgeInsets())
        .background(Color.hz.bgPrimary)
        .textCase(nil)
    }

    @ViewBuilder private func row(_ saved: SavedSpot) -> some View {
        let spot = viewModel.displaySpot(saved)
        Group {
            if viewModel.isEditing {
                Button {
                    viewModel.toggleSelection(saved.id)
                } label: {
                    HStack(spacing: 0) {
                        let selected = viewModel.selection.contains(saved.id)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(selected ? Color.hz.ink : Color.hz.iconSecondary)
                            .padding(.leading, HZSpace.screen)
                        card(spot)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.selection.contains(saved.id) ? .isSelected : [])
            } else {
                SpotRowLink(spot: spot) { card(spot) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("삭제", role: .destructive) { Task { await viewModel.delete(saved.id) } }
                    }
                    .accessibilityAction(named: "삭제") { Task { await viewModel.delete(saved.id) } }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.hz.bgPrimary)
    }

    private func card(_ spot: Spot) -> some View {
        SpotCard(spot: spot, distanceMeters: viewModel.distance(for: spot), showsEnded: true)
    }
}

#Preview("로그인 후") {
    let auth = AuthService(
        backend: FakeAuthBackend(), storage: InMemorySessionStore(FakeAuthBackend.session(provider: .kakao)))
    let library = SavedLibrary(
        auth: auth, account: FakeAccountService(savedIDs: SampleSpots.all.map(\.id)),
        legacy: SavedSpotsStore(defaults: UserDefaults(suiteName: "preview-legacy")!),
        cache: UserDefaults(suiteName: "preview-saved")!)
    return NavigationStack {
        SavedView(viewModel: SavedViewModel(library: library))
    }
}

#Preview("로그인 전") {
    let auth = AuthService(backend: FakeAuthBackend(), storage: InMemorySessionStore())
    let library = SavedLibrary(
        auth: auth, account: FakeAccountService(),
        legacy: SavedSpotsStore(defaults: UserDefaults(suiteName: "preview-legacy")!),
        cache: UserDefaults(suiteName: "preview-saved")!)
    return NavigationStack {
        SavedView(viewModel: SavedViewModel(library: library))
    }
}
