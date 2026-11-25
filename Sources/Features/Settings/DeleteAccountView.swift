import DesignSystem
import Domain
import SwiftUI

/// S6 회원 탈퇴 확인 화면 → 완료 화면 (herezi-api docs/design/screens/S6-settings.md "회원 탈퇴 흐름", DESIGN §6.20).
/// 빨강은 시스템 확인 대화상자의 **탈퇴** 버튼에만 쓴다. 이 화면의 주 버튼은 잉크.
struct DeleteAccountView: View {
    @State private var viewModel: DeleteAccountViewModel
    @State private var confirmingFinal = false
    @AccessibilityFocusState private var doneTitleFocused: Bool
    let onFinished: () -> Void

    init(viewModel: DeleteAccountViewModel, onFinished: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if viewModel.phase == .done {
                done
            } else {
                confirm
            }
        }
        .background(Color.hz.bgPrimary)
        .hzToast(message: $viewModel.toastMessage)
    }

    // MARK: 확인 화면

    private var confirm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("탈퇴하기 전에\n확인해 주세요")
                    .hzText(.title1)
                    .foregroundStyle(Color.hz.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, HZSpace.s6)
                VStack(alignment: .leading, spacing: 0) {
                    lossRow("bookmark", viewModel.savedLine)
                    lossRow("person.crop.circle.badge.xmark", viewModel.providerLine)
                    lossRow("exclamationmark.circle", DeleteAccountViewModel.irreversibleLine)
                }
                .padding(.vertical, HZSpace.s3)
                .padding(.horizontal, HZSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.hz.bgSecondary, in: RoundedRectangle(cornerRadius: HZRadius.md))
                .padding(.top, HZSpace.s8)
                Text(DeleteAccountViewModel.notice)
                    .font(Font.hz.caption)
                    .foregroundStyle(Color.hz.textSecondary)
                    .padding(.top, HZSpace.s3)
                checkbox
                    .padding(.top, HZSpace.s6)
            }
            .padding(.horizontal, HZSpace.screen)
        }
        .navigationBarTitleDisplayMode(.inline)
        // 진행 중에는 뒤로(버튼·스와이프)를 막는다.
        .navigationBarBackButtonHidden(viewModel.phase == .deleting)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.hz.border).frame(height: 1)
                Button {
                    confirmingFinal = true
                } label: {
                    if viewModel.phase == .deleting {
                        ProgressView().tint(Color.hz.textInverse).accessibilityLabel("탈퇴하는 중")
                    } else {
                        Text("탈퇴하기")
                    }
                }
                .buttonStyle(HZPrimaryButtonStyle())
                .disabled(!viewModel.canSubmit && viewModel.phase != .deleting)
                .allowsHitTesting(viewModel.phase == .confirm)
                .padding(.horizontal, HZSpace.screen)
                .padding(.vertical, HZSpace.s3)
            }
            .background(Color.hz.bgPrimary)
        }
        .alert(DeleteAccountViewModel.finalTitle, isPresented: $confirmingFinal) {
            Button("탈퇴", role: .destructive) { Task { await viewModel.delete() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text(DeleteAccountViewModel.finalMessage)
        }
    }

    private func lossRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: HZSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.hz.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Font.hz.bodyStrong)
                .foregroundStyle(Color.hz.textPrimary)
        }
        .frame(minHeight: 48, alignment: .leading)
    }

    private var checkbox: some View {
        Button {
            viewModel.isChecked.toggle()
        } label: {
            HStack(spacing: HZSpace.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: HZRadius.xs)
                        .fill(viewModel.isChecked ? Color.hz.ink : Color.clear)
                    RoundedRectangle(cornerRadius: HZRadius.xs)
                        .strokeBorder(viewModel.isChecked ? Color.hz.ink : Color.hz.border, lineWidth: 2)
                    if viewModel.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.hz.textInverse)
                    }
                }
                .frame(width: 24, height: 24)
                Text("위 내용을 확인했어요")
                    .font(Font.hz.bodyStrong)
                    .foregroundStyle(Color.hz.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: HZSize.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.phase == .deleting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("위 내용을 확인했어요")
        .accessibilityAddTraits(viewModel.isChecked ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(viewModel.isChecked ? "선택됨" : "선택 안 됨")
    }

    // MARK: 완료 화면

    private var done: some View {
        HZStateView(
            symbol: "checkmark.circle", title: "탈퇴했어요", message: "그동안 히어지를 써 주셔서 고마워요.",
            iconColor: Color.hz.iconPrimary
        )
        .accessibilityFocused($doneTitleFocused)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("확인", action: onFinished)
                .buttonStyle(HZPrimaryButtonStyle())
                .padding(.horizontal, HZSpace.screen)
                .padding(.vertical, HZSpace.s3)
        }
        .onAppear { doneTitleFocused = true }
    }
}
