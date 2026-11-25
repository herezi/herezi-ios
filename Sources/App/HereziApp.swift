import DesignSystem
import Domain
import FeatureAuth
import FeatureHome
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
    /// 하단 탭 (DESIGN §6.12): 주변 · 지도 · 저장. 설정은 저장 탭 톱니.
    enum Tab: Hashable {
        case nearby, map, saved
    }

    /// 탭 안에서 push 하는 화면.
    enum Route: Hashable {
        case search
        case settings
        case spot(id: String)
        /// S1b 전체 목록 + 시작 필터. 지도에서 다른 동네를 다시 찾았으면 그 중심·위치명.
        case list(HomeListFilter, origin: Coordinate? = nil, placeName: String? = nil)
    }

    let service = AppEnvironment.makeSpotsService()
    let location = CoreLocationProvider(timeout: .seconds(5))
    let naming: any PlaceNaming
    let recents = RecentSearchesStore()
    /// 로그인 세션(Supabase) — 로그인 시트는 `auth.loginRequest`로 띄운다.
    let auth: AuthService
    /// 계정 저장 목록 (+ v1.3 이전 기기 로컬 저장 `library.legacy`).
    let library: SavedLibrary
    let kakao: any KakaoLoginProviding
    let account: AccountActions
    /// 앱 전체 토스트(로그인 직후 "저장했어요" → "기기에 저장했던 N개를…"). 차례대로 보여준다.
    var toast: HZToast?
    @ObservationIgnored private var toastQueue: [String] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    let home: HomeViewModel
    let map: MapViewModel
    var showsOnboarding: Bool
    var tab: Tab = .nearby
    var nearbyPath = NavigationPath()
    var mapPath = NavigationPath()
    var savedPath = NavigationPath()

    init() {
        KakaoLoginProvider.initializeSDK()
        auth = AppEnvironment.makeAuthService()
        let accountService = AppEnvironment.makeAccountService()
        library = SavedLibrary(auth: auth, account: accountService, legacy: SavedSpotsStore())
        kakao = AppEnvironment.makeKakaoLogin()
        account = AccountActions(library: library, account: accountService, kakao: kakao)
        // 위치명은 기기 지오코더만 쓴다 — 좌표를 서버로 보내지 않는다(#37).
        naming = GeocoderPlaceNaming()
        home = HomeViewModel(service: service, location: location, naming: naming, saved: library)
        // 스크린리더가 켜져 있으면 시트를 펼친 채 시작한다(목록이 지도의 대안, S2 접근성).
        map = MapViewModel(
            service: service, location: location, naming: naming,
            startsExpanded: UIAccessibility.isVoiceOverRunning)
        showsOnboarding = OnboardingViewModel.shouldShow(permission: location.permission)
        #if DEBUG
            DebugLaunch.apply(to: self)
        #endif
    }

    /// 이미 선택된 탭을 다시 누르면 첫 화면으로.
    func select(_ newTab: Tab) {
        if newTab == tab {
            switch newTab {
            case .nearby: nearbyPath = NavigationPath()
            case .map: mapPath = NavigationPath()
            case .saved: savedPath = NavigationPath()
            }
        }
        tab = newTab
    }

    /// S1b "지도로 보기" → 지도 탭으로 필터를 넘긴다.
    func showMap(_ filter: HomeListFilter) {
        tab = .map
        Task { await map.apply(filter) }
    }

    /// S2 "목록으로 보기" → 주변 탭에서 S1b를 그 필터로 (다른 동네를 다시 찾았으면 그 지도 중심 기준).
    func showList(_ request: MapListRequest) {
        tab = .nearby
        nearbyPath.append(Route.list(request.filter, origin: request.origin, placeName: request.placeName))
    }

    func goHome() {
        nearbyPath = NavigationPath()
        tab = .nearby
    }

    /// 탈퇴 완료 → 탭을 처음 상태로 되돌리고 주변 탭 홈(S1)으로.
    func resetAfterAccountDeletion() {
        nearbyPath = NavigationPath()
        mapPath = NavigationPath()
        savedPath = NavigationPath()
        tab = .nearby
    }

    /// 로그인 성공 뒤(시트는 이미 닫힘): 기기 저장 옮기기 → 대기 동작 → 토스트들.
    func didSignIn(_ request: LoginRequest) async {
        showToasts(await library.completeLogin(request))
    }

    /// 토스트를 차례대로(각 2.5초) 보여준다.
    func showToasts(_ messages: [String]) {
        toastQueue += messages
        guard toastTask == nil else { return }
        toastTask = Task { [weak self] in
            while let self, !self.toastQueue.isEmpty {
                let next = HZToast(self.toastQueue.removeFirst())
                self.toast = next
                try? await Task.sleep(for: next.duration + .milliseconds(300))
            }
            self?.toastTask = nil
        }
    }

    /// 위치를 알면 실제 위치 (저장 거리 계산용). 서울시청 기준이면 nil.
    var knownCoordinate: Coordinate? {
        home.isUsingFallbackLocation ? nil : home.coordinate
    }
}

struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.openURL) private var openURL

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
                tabs.transition(.opacity)
            }
        }
        .animation(HZMotion.base, value: app.showsOnboarding)
        .hzToast($app.toast)
        .sheet(item: Binding(get: { app.auth.loginRequest }, set: { app.auth.loginRequest = $0 })) { request in
            LoginSheet(
                viewModel: LoginViewModel(
                    request: request, auth: app.auth, kakao: app.kakao, onSignedIn: app.didSignIn))
        }
        .onOpenURL { url in _ = KakaoLoginProvider.handle(url) }
        .task { await app.library.start() }
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { app.tab }, set: { app.select($0) })) {
            NavigationStack(path: $app.nearbyPath) {
                HomeView(
                    viewModel: app.home, banner: banner,
                    onSearch: { app.nearbyPath.append(AppModel.Route.search) },
                    onOpenList: { app.nearbyPath.append(AppModel.Route.list($0)) },
                    onShowMap: { app.tab = .map }
                )
                .destinations(app: app, root: self)
            }
            .tabItem { Label("주변", systemImage: "location.circle") }
            .tag(AppModel.Tab.nearby)

            NavigationStack(path: $app.mapPath) {
                NearbyMapScreen(
                    viewModel: app.map, banner: banner,
                    onSearch: { app.mapPath.append(AppModel.Route.search) },
                    onShowList: app.showList
                )
                .destinations(app: app, root: self)
            }
            .tabItem { Label("지도", systemImage: "map") }
            .tag(AppModel.Tab.map)

            NavigationStack(path: $app.savedPath) {
                SavedView(
                    viewModel: SavedViewModel(library: app.library, origin: app.knownCoordinate),
                    onBrowse: app.goHome,
                    onSettings: { app.savedPath.append(AppModel.Route.settings) }
                )
                .destinations(app: app, root: self)
            }
            .tabItem { Label("저장", systemImage: "bookmark") }
            .tag(AppModel.Tab.saved)
        }
    }

    /// 위치 꺼짐 배너: 한 번도 묻지 않았으면 "허용하기"(권한 창), 아니면 "설정"(설정 앱).
    var banner: LocationBannerConfig {
        if app.location.permission == .notDetermined {
            return LocationBannerConfig(actionTitle: "허용하기") {
                Task {
                    if await app.location.requestWhenInUse().isGranted { await app.home.reload() }
                }
            }
        }
        return LocationBannerConfig(actionTitle: "설정") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }

    @ViewBuilder func destination(_ route: AppModel.Route) -> some View {
        switch route {
        case .search:
            SearchView(
                viewModel: SearchViewModel(
                    service: app.service, recents: app.recents, origin: app.home.coordinate ?? .seoulCityHall),
                initialQuery: DebugLaunch.searchQuery)
        case .settings:
            SettingsView(
                viewModel: SettingsViewModel(
                    permissions: app.location, appVersion: AppEnvironment.appVersion, build: AppEnvironment.build,
                    osVersion: UIDevice.current.systemVersion, account: app.account),
                onAccountDeleted: app.resetAfterAccountDeletion)
        case .spot(let id):
            detail(id: id, initial: nil)
        case .list(let filter, let origin, let placeName):
            NearbyView(
                viewModel: NearbyViewModel(
                    service: app.service, location: app.location, filter: filter, origin: origin ?? app.home.coordinate,
                    isUsingFallbackLocation: origin == nil && app.home.isUsingFallbackLocation),
                placeName: placeName ?? app.home.placeName ?? "내 주변", banner: banner,
                onSearch: { app.nearbyPath.append(AppModel.Route.search) },
                onShowMap: app.showMap)
        }
    }

    func detail(id: String, initial: Spot?) -> some View {
        SpotDetailView(
            viewModel: SpotDetailViewModel(
                id: id, initial: initial, service: app.service, saved: app.library,
                usesFallbackLocation: app.home.isUsingFallbackLocation),
            onGoHome: app.goHome)
    }
}

extension View {
    /// 각 탭의 NavigationStack에 같은 목적지를 등록한다.
    fileprivate func destinations(app: AppModel, root: RootView) -> some View {
        navigationDestination(for: Spot.self) { spot in root.detail(id: spot.id, initial: spot) }
            .navigationDestination(for: AppModel.Route.self) { route in root.destination(route) }
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

    /// API 주소. 스킴 환경 변수 `HEREZI_API_BASE_URL`이 있으면 그것(시뮬레이터에서 실서버로 확인할 때),
    /// 없으면 Info.plist `HereziAPIBaseURL`(project.yml 빌드 설정별).
    static func apiBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = environment["HEREZI_API_BASE_URL"], let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return APIClient.baseURL()
    }

    /// 근처·지도·검색은 지역 데이터 파일(Caches에 저장) + 기기 계산, 상세만 `GET /v1/spots/{id}` (#37).
    static func makeSpotsService() -> any SpotsService {
        if usesFakeAPI() {
            return FakeSpotsService(spots: SampleSpots.demo)
        }
        let client = APIClient(baseURL: apiBaseURL())
        let repository = RegionSpotsRepository(
            region: "seoul", fetcher: LiveRegionSpotsSource(client: client), cache: .appCaches())
        return LocalSpotsService(repository: repository, detail: LiveSpotDetailService(client: client))
    }

    /// Debug `-HZFakeAuth kakao|apple|none`: 가짜 세션(서버·SDK 없이)으로 시작 — 스크린샷·UI 테스트용.
    static var fakeAuthProvider: String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: "HZFakeAuth")
        #else
            nil
        #endif
    }

    /// Supabase 설정(Info.plist ← Config/Secrets.xcconfig). 샘플 모드에서 설정이 없으면 가짜 인증을 쓴다.
    @MainActor
    static func makeAuthService() -> AuthService {
        if let fake = fakeAuthProvider {
            let session = AuthProvider(rawValue: fake).map { FakeAuthBackend.session(provider: $0) }
            return AuthService(backend: FakeAuthBackend(), storage: InMemorySessionStore(session))
        }
        let keychain = KeychainSessionStore()
        keychain.clearIfFreshInstall()
        let config = SupabaseAuthBackend.Config.from()
        if config == nil && usesFakeAPI() {
            return AuthService(backend: FakeAuthBackend(), storage: keychain)
        }
        return AuthService(backend: SupabaseAuthBackend(config: config), storage: keychain)
    }

    static func makeAccountService() -> any AccountService {
        if usesFakeAPI() {
            #if DEBUG
                let seeded = UserDefaults.standard.bool(forKey: "HZSeedAccount")
                return FakeAccountService(spots: SampleSpots.demo, savedIDs: seeded ? SampleSpots.demo.map(\.id) : [])
            #else
                return FakeAccountService(spots: SampleSpots.demo)
            #endif
        }
        return LiveAccountService(client: APIClient(baseURL: apiBaseURL()))
    }

    /// 카카오 키가 없거나 가짜 인증이면 가짜 카카오 로그인(샘플 모드 개발용).
    @MainActor
    static func makeKakaoLogin() -> any KakaoLoginProviding {
        if fakeAuthProvider != nil || (KakaoLoginProvider.nativeAppKey == nil && usesFakeAPI()) {
            return FakeKakaoLogin()
        }
        return KakaoLoginProvider()
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
/// - `-HZScreen onboarding|home|list|map|map-selected|map-moved|search|saved|settings|detail|detail-ended|login`
/// - `-HZSearchQuery <검색어>`: 검색 화면을 열자마자 조회
/// - `-HZSeedSaved YES`: 샘플 볼거리를 기기 로컬 저장(v1.3 이전 저장)에 넣는다 — 첫 로그인 옮기기 확인용
/// - `-HZFakeAuth kakao|apple|none`: 가짜 세션으로 시작(로그인 상태 화면 확인용)
/// - `-HZSeedAccount YES`: (샘플 모드) 계정 저장 목록에 샘플 볼거리를 넣는다
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
                app.library.legacy.save(spot, at: Date().addingTimeInterval(-Double(offset) * 3_600))
            }
        }
        if let query = searchQuery {
            app.recents.add("빛초롱")
            app.recents.add(query)
        }
        guard let screen else { return }
        app.showsOnboarding = screen == "onboarding"
        switch screen {
        case "search": app.nearbyPath.append(AppModel.Route.search)
        case "list": app.nearbyPath.append(AppModel.Route.list(HomeListFilter(when: .week)))
        case "map": app.tab = .map
        case "map-selected":
            app.tab = .map
            Task {
                await app.map.start()
                app.map.select("sample-1")
            }
        case "map-moved":
            app.tab = .map
            Task {
                await app.map.start()
                try? await Task.sleep(for: .seconds(2))
                #if DEBUG
                    app.map.debugPan(to: Coordinate(latitude: 37.5760, longitude: 126.9800))
                #endif
            }
        case "saved": app.tab = .saved
        case "settings":
            app.tab = .saved
            app.savedPath.append(AppModel.Route.settings)
        case "detail": app.nearbyPath.append(AppModel.Route.spot(id: "sample-1"))
        case "detail-ended": app.nearbyPath.append(AppModel.Route.spot(id: SampleSpots.endedID))
        case "login":
            app.nearbyPath.append(AppModel.Route.spot(id: "sample-1"))
            Task {
                try? await Task.sleep(for: .seconds(1))
                app.auth.requestLogin(.save)
            }
        default: break
        }
    }
}
