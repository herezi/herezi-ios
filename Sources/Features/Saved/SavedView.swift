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
                if !viewModel.isEmpty {
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
                    Button(viewModel.deleteSelectedTitle) { viewModel.deleteSelected() }
                        .buttonStyle(HZPrimaryButtonStyle())
                        .disabled(viewModel.selection.isEmpty)
                        .padding(.horizontal, HZSpace.screen)
                        .padding(.vertical, HZSpace.s3)
                        .background(Color.hz.bgPrimary)
                }
            }
            .task { await viewModel.refresh() }
            .hzToast($toast) { viewModel.undo() }
            .onChange(of: viewModel.toastMessage) { _, message in
                guard let message else { return }
                toast = HZToast(message, actionTitle: "되돌리기", duration: .seconds(4))
                viewModel.toastMessage = nil
            }
            .confirmationDialog(
                viewModel.clearEndedPrompt, isPresented: $confirmingClear, titleVisibility: .visible
            ) {
                Button("지우기", role: .destructive) { viewModel.clearEnded() }
                Button("취소", role: .cancel) {}
            }
    }

    @ViewBuilder private var content: some View {
        if viewModel.isEmpty {
            HZStateView(
                symbol: "bookmark", title: "저장한 볼거리가 없어요", message: "마음에 드는 곳을 저장해 두면 여기에 모여요."
            ) {
                HZStateButton("주변 둘러보기", action: onBrowse)
            }
        } else {
            List {
                Section {
                    ForEach(viewModel.active) { row($0) }
                }
                if !viewModel.ended.isEmpty {
                    Section {
                        ForEach(viewModel.ended) { row($0) }
                    } header: {
                        endedHeader
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(0)
            .environment(\.defaultMinListHeaderHeight, 0)
        }
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
                        Button("삭제", role: .destructive) { viewModel.delete(saved.id) }
                    }
                    .accessibilityAction(named: "삭제") { viewModel.delete(saved.id) }
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

#Preview {
    let store = SavedSpotsStore(defaults: UserDefaults(suiteName: "preview-saved")!)
    for spot in SampleSpots.all { store.save(spot) }
    return NavigationStack {
        SavedView(viewModel: SavedViewModel(store: store, service: FakeSpotsService()))
    }
}
