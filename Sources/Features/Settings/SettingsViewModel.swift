import Domain
import Foundation
import Observation

/// S6 설정의 상태·로직: 위치 권한 상태, 정보 출처, 오류 제보, 앱 버전.
@MainActor
@Observable
public final class SettingsViewModel {
    /// 정보 출처 목록 한 줄.
    public struct DataSource: Identifiable, Hashable, Sendable {
        public let name: String
        public let url: URL
        public var id: String { name }
    }

    public static let dataSources: [DataSource] = [
        DataSource(name: "한국관광공사 TourAPI", url: URL(string: "https://api.visitkorea.or.kr")!),
        DataSource(name: "KOPIS 공연예술통합전산망", url: URL(string: "https://www.kopis.or.kr")!),
        DataSource(name: "서울 열린데이터광장", url: URL(string: "https://data.seoul.go.kr")!),
        DataSource(name: "문화공공데이터광장", url: URL(string: "https://www.culture.go.kr/data")!),
        DataSource(name: "산림청·기상청", url: URL(string: "https://www.data.go.kr")!),
    ]

    /// 이용약관·개인정보 처리방침 (S7 로그인 시트와 같은 값 — `SpotLinks`).
    public static let termsURL = SpotLinks.termsURL
    public static let privacyURL = SpotLinks.privacyURL

    /// 오픈소스 라이선스 한 줄. `licenseFile`은 앱 번들 리소스 폴더 기준 경로.
    public struct OpenSourceLicense: Identifiable, Hashable, Sendable {
        public let name: String
        public let license: String
        public let url: URL
        public let licenseFile: String
        public var id: String { name }
    }

    public static let openSourceLicenses: [OpenSourceLicense] = [
        OpenSourceLicense(
            name: "Pretendard", license: "SIL Open Font License 1.1",
            url: URL(string: "https://github.com/orioncactus/pretendard")!, licenseFile: "Fonts/OFL.txt")
    ]

    public static let aiNotice = "요약은 AI(OpenAI GPT)가 원문을 정리한 것이에요. 정확한 내용은 원문을 확인해 주세요."
    public let supportEmail = SpotLinks.supportEmail

    public private(set) var permission: LocationPermission
    public var toastMessage: String?

    private let permissions: any LocationPermissionProviding
    private let appVersion: String
    private let build: String
    private let osVersion: String
    /// 계정 그룹(로그인·로그아웃·탈퇴). nil이면 계정 그룹을 그리지 않는다(미리보기).
    public let account: AccountActions?

    public init(
        permissions: any LocationPermissionProviding, appVersion: String, build: String, osVersion: String,
        account: AccountActions? = nil
    ) {
        self.account = account
        self.permissions = permissions
        self.permission = permissions.permission
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
    }

    // MARK: 계정 (S6 계정 그룹)

    /// 로그인 제공자. nil이면 로그인 전(행 **로그인** 하나).
    public var provider: AuthProvider? { account?.auth.provider }

    /// "카카오로 로그인됨" / "Apple로 로그인됨"
    public var accountTitle: String? {
        provider.map { "\($0.displayName)로 로그인됨" }
    }

    /// 로그인 행 → S7 시트("로그인하고 저장한 볼거리를 모아 보세요"). 성공하면 토스트 "로그인했어요"는 로그인 흐름이 띄운다.
    public func login() {
        account?.auth.requestLogin(.account)
    }

    public static let logoutTitle = "로그아웃할까요?"
    public static let logoutMessage = "다시 로그인하면 저장한 볼거리를 그대로 볼 수 있어요."

    /// 로그아웃 확인 → 세션·캐시 삭제, 카카오 SDK 로그아웃. 설정 화면에 머문 채 토스트.
    public func logout() async {
        guard let account else { return }
        await account.signOut()
        toastMessage = "로그아웃했어요"
    }

    /// 앱이 포그라운드로 돌아올 때 다시 읽는다(설정 앱에서 바꿨을 수 있음).
    public func refresh() {
        permission = permissions.permission
    }

    public var permissionText: String {
        switch permission {
        case .authorized: "허용됨"
        case .approximate: "대략적 위치만"
        case .denied, .notDetermined: "허용 안 됨"
        }
    }

    /// "1.0.0 (12)"
    public var versionText: String { "\(appVersion) (\(build))" }

    /// 받는 사람 운영 메일, 제목 `[정보 오류]`, 본문에 앱 버전·OS.
    public var reportMailURL: URL {
        SpotLinks.reportMail(subject: "[정보 오류]", body: "\n\n---\n앱 버전: \(versionText)\nOS: iOS \(osVersion)")
    }

    public func showMailUnavailable() {
        toastMessage = "메일 앱이 없어요. \(SpotLinks.supportEmail) 으로 보내 주세요"
    }
}
