import CoreLocation
import Domain

/// `PlaceNaming` with CLGeocoder: "구 동" (예: "중구 태평로1가"). 실패하면 nil → 화면은 "내 주변".
/// 서버 역지오코딩(`ServerPlaceNaming`)이 실패했을 때의 대체다. Apple 역지오코딩은 서울에서 구를 빼는 일이 많다("태평로1가").
@MainActor
final class GeocoderPlaceNaming: PlaceNaming {
    private let geocoder = CLGeocoder()

    func placeName(for coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard
            let placemark = try? await geocoder.reverseGeocodeLocation(
                location, preferredLocale: Locale(identifier: "ko_KR")
            ).first
        else { return nil }
        // 시·도 단위는 빼고 구·동만 남긴다.
        let parts = [placemark.subAdministrativeArea, placemark.locality, placemark.subLocality]
            .compactMap { $0 }
            .filter { !$0.hasSuffix("시") && !$0.hasSuffix("도") }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        let name = unique.suffix(2).joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}
