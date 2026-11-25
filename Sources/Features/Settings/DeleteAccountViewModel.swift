import Domain
import Foundation
import Observation

/// S6 회원 탈퇴 흐름: 확인 화면(`DestructiveConfirm`) → 시스템 확인 → 진행 → 완료 화면 (DESIGN §6.20).
@MainActor
@Observable
public final class DeleteAccountViewModel {
    public enum Phase: Equatable, Sendable {
        case confirm
        case deleting
        /// 완료 화면으로 교체(뒤로 돌아갈 수 없음).
        case done
    }

    public private(set) var phase: Phase = .confirm
    /// "위 내용을 확인했어요" 체크. 실패해도 유지한다.
    public var isChecked = false
    public var toastMessage: String?

    private let actions: AccountActions
    /// 화면을 열 때의 제공자·저장 수 (탈퇴 뒤에도 문구가 바뀌지 않게).
    public let provider: AuthProvider?
    public let savedCount: Int

    public init(actions: AccountActions) {
        self.actions = actions
        self.provider = actions.auth.provider
        self.savedCount = actions.library.items.count
    }

    public var canSubmit: Bool { isChecked && phase == .confirm }

    /// "지워지는 것" 세 줄.
    public var savedLine: String {
        savedCount > 0 ? "저장한 볼거리 \(savedCount)개가 모두 지워져요" : "저장한 볼거리가 모두 지워져요"
    }

    public var providerLine: String {
        "\((provider ?? .kakao).displayName) 계정 연결이 끊어져요"
    }

    public static let irreversibleLine = "지운 정보는 되돌릴 수 없어요"
    public static let notice = "같은 계정으로 다시 가입할 수 있지만, 저장한 볼거리는 돌아오지 않아요."
    public static let finalTitle = "정말 탈퇴할까요?"
    public static let finalMessage = "저장한 볼거리와 계정 정보가 바로 지워져요."
    public static let appleCancelledMessage = "Apple 확인을 취소해서 탈퇴하지 않았어요."

    /// 시스템 확인 대화상자에서 **탈퇴**.
    public func delete() async {
        guard canSubmit else { return }
        phase = .deleting
        do {
            try await actions.deleteAccount()
            phase = .done
        } catch AuthError.cancelled {
            // Apple 재인증 시트에서 취소 — 탈퇴를 멈춘다(아무것도 지우지 않음).
            phase = .confirm
            toastMessage = Self.appleCancelledMessage
        } catch AuthError.sessionExpired {
            // 세션이 만료됐으면 다시 로그인하게 하고 이 화면에 머문다(대기 동작 없음 — 사용자가 다시 탈퇴하기).
            phase = .confirm
            actions.auth.requestLogin(.account)
        } catch AuthError.notLoggedIn {
            phase = .confirm
            actions.auth.requestLogin(.account)
        } catch AccountError.offline {
            phase = .confirm
            toastMessage = "인터넷 연결을 확인하고 다시 시도해 주세요."
        } catch {
            phase = .confirm
            toastMessage = "탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
