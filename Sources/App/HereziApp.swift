import DesignSystem
import Domain
import FeatureNearby
import FeatureSpotDetail
import Networking
import SwiftUI

/// Composition root: the only place that knows concrete adapters.
@main
struct HereziApp: App {
    @State private var nearby = NearbyViewModel(
        service: AppEnvironment.makeSpotsService(), location: CoreLocationProvider())

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NearbyView(viewModel: nearby)
                    .navigationDestination(for: Spot.self) { spot in
                        SpotDetailView(spot: spot)
                    }
            }
            .tint(Color.hz.ink)
            // M1은 라이트 모드만 (DESIGN §2.2).
            .preferredColorScheme(.light)
        }
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
}
