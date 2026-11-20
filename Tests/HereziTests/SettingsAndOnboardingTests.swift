import Domain
import FeatureOnboarding
import FeatureSettings
import Foundation
import Testing

@MainActor
struct SettingsViewModelTests {
    @Test(arguments: [
        (LocationPermission.authorized, "허용됨"), (.approximate, "대략적 위치만"), (.denied, "허용 안 됨"),
        (.notDetermined, "허용 안 됨"),
    ])
    func 위치_권한_상태를_보여준다(permission: LocationPermission, expected: String) {
        let viewModel = SettingsViewModel(
            permissions: FakeLocationPermissions(permission), appVersion: "1.0.0", build: "12", osVersion: "26.3")
        #expect(viewModel.permissionText == expected)
    }

    @Test func 포그라운드로_돌아오면_권한을_다시_읽는다() {
        let permissions = FakeLocationPermissions(.denied)
        let viewModel = SettingsViewModel(
            permissions: permissions, appVersion: "1.0.0", build: "12", osVersion: "26.3")
        permissions.permission = .authorized
        viewModel.refresh()
        #expect(viewModel.permissionText == "허용됨")
    }

    @Test func 버전과_오류_제보_메일() throws {
        let viewModel = SettingsViewModel(
            permissions: FakeLocationPermissions(.authorized), appVersion: "1.0.0", build: "12", osVersion: "26.3")
        #expect(viewModel.versionText == "1.0.0 (12)")
        #expect(viewModel.supportEmail == "help@herezi.com")
        let components = try #require(URLComponents(url: viewModel.reportMailURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "help@herezi.com")
        #expect(components.queryItems?.first { $0.name == "subject" }?.value == "[정보 오류]")
        let body = components.queryItems?.first { $0.name == "body" }?.value ?? ""
        #expect(body.contains("앱 버전: 1.0.0 (12)") && body.contains("OS: iOS 26.3"))

        viewModel.showMailUnavailable()
        #expect(viewModel.toastMessage == "메일 앱이 없어요. help@herezi.com 으로 보내 주세요")
    }

    @Test func 약관_링크와_오픈소스_라이선스() {
        #expect(SettingsViewModel.termsURL.absoluteString == "https://herezi.github.io/terms/")
        #expect(SettingsViewModel.privacyURL.absoluteString == "https://herezi.github.io/privacy/")
        let pretendard = SettingsViewModel.openSourceLicenses.first { $0.name == "Pretendard" }
        #expect(pretendard?.license == "SIL Open Font License 1.1")
        #expect(pretendard?.licenseFile == "Fonts/OFL.txt")
    }
}

@MainActor
struct OnboardingViewModelTests {
    @Test func 처음이고_묻지_않았을_때만_보인다() {
        let defaults = freshDefaults()
        #expect(OnboardingViewModel.shouldShow(permission: .notDetermined, defaults: defaults))
        #expect(!OnboardingViewModel.shouldShow(permission: .authorized, defaults: defaults))
        #expect(!OnboardingViewModel.shouldShow(permission: .denied, defaults: defaults))
    }

    @Test func 허용하기는_권한을_요청하고_결과와_함께_끝난다() async {
        let defaults = freshDefaults()
        let permissions = FakeLocationPermissions(.notDetermined, answer: .denied)
        var finished: LocationPermission?
        let viewModel = OnboardingViewModel(permissions: permissions, defaults: defaults) { finished = $0 }

        await viewModel.allow()

        #expect(permissions.requestCount == 1)
        #expect(finished == .denied)
        #expect(!OnboardingViewModel.shouldShow(permission: .notDetermined, defaults: defaults))
    }

    @Test func 나중에는_권한_창_없이_끝나고_다시_보이지_않는다() {
        let defaults = freshDefaults()
        let permissions = FakeLocationPermissions(.notDetermined)
        var finished: LocationPermission?
        let viewModel = OnboardingViewModel(permissions: permissions, defaults: defaults) { finished = $0 }

        viewModel.later()

        #expect(permissions.requestCount == 0)
        #expect(finished == .notDetermined)
        #expect(!OnboardingViewModel.shouldShow(permission: .notDetermined, defaults: defaults))
    }
}

struct DetailFormattingTests {
    @Test func 상세_기간() {
        #expect(
            SpotFormatting.detailPeriod(start: kst(2026, 11, 20), end: kst(2026, 12, 14)) == "11월 20일(금) – 12월 14일(월)")
        #expect(SpotFormatting.detailPeriod(start: kst(2026, 11, 20), end: nil) == "11월 20일(금)부터")
        #expect(SpotFormatting.detailPeriod(start: kst(2026, 11, 20, 18), end: kst(2026, 11, 20, 22)) == "11월 20일(금)")
    }

    @Test func 시간_행은_시각이_있을_때만() {
        #expect(SpotFormatting.timeRange(start: kst(2026, 11, 20), end: kst(2026, 12, 14)) == nil)
        #expect(
            SpotFormatting.timeRange(start: kst(2026, 11, 20, 17), end: kst(2026, 12, 14, 22)) == "매일 17:00 – 22:00")
        #expect(SpotFormatting.timeRange(start: kst(2026, 11, 20, 18), end: kst(2026, 11, 20, 22)) == "18:00 – 22:00")
    }

    @Test func 갱신_시각() {
        let now = kst(2026, 11, 20, 12)
        #expect(SpotFormatting.fetchedText(now.addingTimeInterval(-30), now: now) == "방금 갱신")
        #expect(SpotFormatting.fetchedText(now.addingTimeInterval(-5 * 60), now: now) == "5분 전 갱신")
        #expect(SpotFormatting.fetchedText(now.addingTimeInterval(-2 * 3_600), now: now) == "2시간 전 갱신")
        #expect(SpotFormatting.fetchedText(kst(2026, 11, 18, 9), now: now) == "11월 18일 갱신")
        #expect(SpotFormatting.spokenDateTime(kst(2026, 11, 20, 9, 12)) == "11월 20일 오전 9시 12분")
    }

    @Test func 종료_안내와_출처_이름() {
        #expect(SpotFormatting.endedNotice(end: kst(2026, 11, 17, 18)) == "11월 17일에 끝난 볼거리예요.")
        #expect(SpotFormatting.sourceName("kopis") == "KOPIS 공연예술통합전산망")
        #expect(SpotFormatting.sourceName("news") == "news")
    }

    @Test func 멀면_대중교통_길찾기와_웹_대체_링크() {
        #expect(SpotLinks.RouteMode.forDistance(1_999) == .walk)
        #expect(SpotLinks.RouteMode.forDistance(2_000) == .publicTransit)
        let spot = TestData.spots[0]
        #expect(
            SpotLinks.naverRouteWeb(to: spot, mode: .walk).absoluteString
                == "https://map.naver.com/p/directions/-/126.9784,37.569,%EC%B2%AD%EA%B3%84%EA%B4%91%EC%9E%A5/-/walk")
        #expect(
            SpotLinks.naverRouteApp(to: spot, mode: .publicTransit).absoluteString.hasPrefix("nmap://route/public?"))
    }
}
