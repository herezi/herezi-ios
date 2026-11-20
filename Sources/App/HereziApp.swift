import DesignSystem
import Domain
import FeatureNearby
import FeatureOnboarding
import FeatureSaved
import FeatureSearch
import FeatureSettings
import FeatureSpotDetail
import Networking
import SwiftUI
import UIKit

/// Composition root: the only place that knows concrete adapters.
@main
struct HereziApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .tint(Color.hz.ink)
                // M1은 라이트 모드만 (DESIGN §2.2).
                .preferredColorScheme(.light)
        }
    }
}

/// 앱 전체에서 공유하는 어댑터·상태.
@MainActor
@Observable
final class AppModel {
    let service = AppEnvironment.makeSpotsService()
    let location = CoreLocationProvider()
    let saved = SavedSpotsStore()
    let recents = RecentSearchesStore()
    let nearby: NearbyViewModel
    var showsOnboarding: Bool
    var path = NavigationPath()

    init() {
        nearby = NearbyViewModel(service: service, location: location)
        showsOnboarding = OnboardingViewModel.shouldShow(permission: location.permission)
        #if DEBUG
            DebugLaunch.apply(to: self)
        #endif
    }

    /// 화면 이동 (주변 화면의 상단 바 입구, 상세 404의 "주변 보기" 등).
    enum Route: Hashable {
        case search
        case saved
        case settings
        case spot(id: String)
    }

    func popToRoot() {
        path = NavigationPath()
    }

    /// 위치를 알면 실제 위치, 모르면 서울시청 (검색·저장 거리 기준).
    var knownCoordinate: Coordinate? {
        nearby.isUsingFallbackLocation ? nil : nearby.coordinate
    }
}

struct RootView: View {
    @Bindable var app: AppModel

    var body: some View {
        ZStack {
            if app.showsOnboarding {
                OnboardingView(
                    viewModel: OnboardingViewModel(permissions: app.location) { _ in
                        app.showsOnboarding = false
                    }
                )
                .transition(.opacity)
            } else {
                NavigationStack(path: $app.path) {
                    NearbyView(
                        viewModel: app.nearby,
                        onSearch: { app.path.append(AppModel.Route.search) },
                        onSaved: { app.path.append(AppModel.Route.saved) },
                        onSettings: { app.path.append(AppModel.Route.settings) }
                    )
                    .navigationDestination(for: Spot.self) { spot in
                        detail(id: spot.id, initial: spot)
                    }
                    .navigationDestination(for: AppModel.Route.self) { route in
                        destination(route)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(HZMotion.base, value: app.showsOnboarding)
    }

    @ViewBuilder private func destination(_ route: AppModel.Route) -> some View {
        switch route {
        case .search:
            SearchView(
                viewModel: SearchViewModel(
                    service: app.service, recents: app.recents, origin: app.nearby.coordinate ?? .seoulCityHall),
                initialQuery: DebugLaunch.searchQuery)
        case .saved:
            SavedView(
                viewModel: SavedViewModel(store: app.saved, service: app.service, origin: app.knownCoordinate),
                onBrowse: app.popToRoot)
        case .settings:
            SettingsView(
                viewModel: SettingsViewModel(
                    permissions: app.location, appVersion: AppEnvironment.appVersion, build: AppEnvironment.build,
                    osVersion: UIDevice.current.systemVersion))
        case .spot(let id):
            detail(id: id, initial: nil)
        }
    }

    private func detail(id: String, initial: Spot?) -> some View {
        SpotDetailView(
            viewModel: SpotDetailViewModel(
                id: id, initial: initial, service: app.service, saved: app.saved,
                usesFallbackLocation: app.nearby.isUsingFallbackLocation),
            onGoHome: app.popToRoot)
    }
}

enum AppEnvironment {
    /// 가짜 데이터(`FakeSpotsService`) 사용 여부.
    /// 1) 스킴 환경 변수 `HEREZI_FAKE_API=1|0`이 있으면 그 값을 따른다.
    /// 2) 없으면 Info.plist `HereziUseFakeAPI`(project.yml: Debug=YES, Release=NO).
    /// API 서버가 아직 배포되지 않았으므로 Debug 기본값은 오프라인 샘플 데이터다.
    static func usesFakeAPI(
        environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main
    ) -> Bool {
        if let override = environment["HEREZI_FAKE_API"] {
            return override == "1"
        }
        return (bundle.object(forInfoDictionaryKey: "HereziUseFakeAPI") as? String) == "YES"
    }

    static func makeSpotsService() -> any SpotsService {
        if usesFakeAPI() {
            return FakeSpotsService()
        }
        return LiveSpotsService(client: APIClient(baseURL: APIClient.baseURL()))
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
}

/// Debug 전용 실행 인자. 스크린샷·QA에서 화면을 바로 연다.
///
///     xcrun simctl launch booted com.herezi.app -HZScreen search -HZSearchQuery 광화문
///
/// - `-HZScreen onboarding|search|saved|settings|detail|detail-ended`
/// - `-HZSearchQuery <검색어>`: 검색 화면을 열자마자 조회
/// - `-HZSeedSaved YES`: 샘플 볼거리를 저장 목록에 넣는다
enum DebugLaunch {
    static var screen: String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: "HZScreen")
        #else
            nil
        #endif
    }

    static var searchQuery: String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: "HZSearchQuery")
        #else
            nil
        #endif
    }

    @MainActor
    static func apply(to app: AppModel) {
        if UserDefaults.standard.bool(forKey: "HZSeedSaved") {
            for (offset, spot) in SampleSpots.all.enumerated() {
                app.saved.save(spot, at: Date().addingTimeInterval(-Double(offset) * 3_600))
            }
        }
        if let query = searchQuery {
            app.recents.add("빛초롱")
            app.recents.add(query)
        }
        guard let screen else { return }
        app.showsOnboarding = screen == "onboarding"
        switch screen {
        case "search": app.path.append(AppModel.Route.search)
        case "saved": app.path.append(AppModel.Route.saved)
        case "settings": app.path.append(AppModel.Route.settings)
        case "detail": app.path.append(AppModel.Route.spot(id: "sample-1"))
        case "detail-ended": app.path.append(AppModel.Route.spot(id: SampleSpots.endedID))
        default: break
        }
    }
}
