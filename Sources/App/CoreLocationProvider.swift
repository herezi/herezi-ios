import CoreLocation
import Domain

/// `LocationProviding` backed by CoreLocation (when-in-use). Gives up after `timeout`.
@MainActor
final class CoreLocationProvider: LocationProviding {
    enum LocationError: Error {
        case denied
        case timedOut
    }

    private let manager = CLLocationManager()
    private let timeout: Duration

    init(timeout: Duration = .seconds(10)) {
        self.timeout = timeout
    }

    func currentCoordinate() async throws -> Coordinate {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
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
