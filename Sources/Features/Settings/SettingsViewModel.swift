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

    public static let aiNotice = "요약은 AI(OpenAI GPT)가 원문을 정리한 것이에요. 정확한 내용은 원문을 확인해 주세요."
    public let supportEmail = SpotLinks.supportEmail

    public private(set) var permission: LocationPermission
    public var toastMessage: String?

    private let permissions: any LocationPermissionProviding
    private let appVersion: String
    private let build: String
    private let osVersion: String

    public init(
        permissions: any LocationPermissionProviding, appVersion: String, build: String, osVersion: String
    ) {
        self.permissions = permissions
        self.permission = permissions.permission
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
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
