import Domain
import Foundation
import Observation

/// S0 위치 권한 안내의 상태·로직. 첫 실행이고 권한을 한 번도 묻지 않았을 때만 보인다.
@MainActor
@Observable
public final class OnboardingViewModel {
    static let completedKey = "herezi.onboardingCompleted.v1"

    public private(set) var isRequesting = false

    private let permissions: any LocationPermissionProviding
    private let defaults: UserDefaults
    private let onFinish: @MainActor (LocationPermission) -> Void

    /// - Parameter onFinish: 허용·거부·나중에 모두 S1으로. 결과 권한을 넘긴다.
    public init(
        permissions: any LocationPermissionProviding, defaults: UserDefaults = .standard,
        onFinish: @escaping @MainActor (LocationPermission) -> Void
    ) {
        self.permissions = permissions
        self.defaults = defaults
        self.onFinish = onFinish
    }

    /// 이미 허용/거부했거나 S0을 한 번 지나갔으면 보여주지 않는다.
    public static func shouldShow(permission: LocationPermission, defaults: UserDefaults = .standard) -> Bool {
        permission == .notDetermined && !defaults.bool(forKey: completedKey)
    }

    /// "위치 허용하기" → 시스템 권한 창. 결과와 관계없이 S1으로.
    public func allow() async {
        guard !isRequesting else { return }
        isRequesting = true
        let result = await permissions.requestWhenInUse()
        isRequesting = false
        finish(result)
    }

    /// "나중에 할게요" → 권한 창 없이 S1으로. 다음 실행 때 S0을 다시 보여주지 않는다.
    public func later() {
        finish(permissions.permission)
    }

    private func finish(_ permission: LocationPermission) {
        defaults.set(true, forKey: Self.completedKey)
        onFinish(permission)
    }
}
