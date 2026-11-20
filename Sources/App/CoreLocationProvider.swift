import CoreLocation
import Domain

/// `LocationProviding` + `LocationPermissionProviding` backed by CoreLocation (when-in-use).
/// 권한 창은 S0의 "위치 허용하기"에서만 띄운다 — 위치 조회 자체는 권한이 없으면 바로 실패(→ 서울시청).
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, LocationPermissionProviding, CLLocationManagerDelegate {
    enum LocationError: Error {
        case denied
        case timedOut
    }

    private let manager = CLLocationManager()
    private let timeout: Duration
    private var pendingRequests: [CheckedContinuation<LocationPermission, Never>] = []

    init(timeout: Duration = .seconds(10)) {
        self.timeout = timeout
        super.init()
        manager.delegate = self
    }

    var permission: LocationPermission {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            manager.accuracyAuthorization == .reducedAccuracy ? .approximate : .authorized
        default: .denied
        }
    }

    func requestWhenInUse() async -> LocationPermission {
        guard manager.authorizationStatus == .notDetermined else { return permission }
        return await withCheckedContinuation { continuation in
            pendingRequests.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 델리게이트는 매니저를 만든 스레드(메인)에서 불린다.
        MainActor.assumeIsolated { resolvePendingRequests() }
    }

    private func resolvePendingRequests() {
        guard manager.authorizationStatus != .notDetermined, !pendingRequests.isEmpty else { return }
        let result = permission
        let waiting = pendingRequests
        pendingRequests = []
        for continuation in waiting { continuation.resume(returning: result) }
    }

    func currentCoordinate() async throws -> Coordinate {
        guard permission.isGranted else { throw LocationError.denied }
        let timeout = self.timeout
        return try await withThrowingTaskGroup(of: Coordinate.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return Coordinate(
                            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    }
                }
                throw LocationError.timedOut
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw LocationError.timedOut }
            return first
        }
    }
}
