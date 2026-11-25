import Foundation

/// 바깥으로 나가는 링크·문구 (공유, 네이버지도, 메일). 화면과 분리해 단위 테스트한다.
public enum SpotLinks {
    /// 운영 메일 (미확정 — 운영 주소가 정해지면 교체).
    public static let supportEmail = "help@herezi.com"
    /// 이용약관·개인정보 처리방침 (임시 GitHub Pages — 도메인 구매 후 교체, herezi-ios#16). S6·S7이 같은 값을 쓴다.
    public static let termsURL = URL(string: "https://herezi.github.io/terms/")!
    public static let privacyURL = URL(string: "https://herezi.github.io/privacy/")!
    static let appName = "com.herezi.app"

    /// 공유 링크. 도메인은 아직 사지 않았고 텍스트 공유에만 쓴다.
    public static func shareURL(for spot: Spot) -> URL {
        URL(string: "https://herezi.com/s/\(escape(spot.id, allowed: .urlPathAllowed))")!
    }

    /// 공유 시트 문구: `{title}\n{기간} · {place_name}\nhttps://herezi.com/s/{id}`
    public static func shareText(for spot: Spot, now: Date = Date()) -> String {
        let period = SpotFormatting.cardPeriod(start: spot.startsAt, end: spot.endsAt, now: now).text
        let second = [period, spot.placeName].compactMap { $0 }.joined(separator: " · ")
        return "\(spot.title)\n\(second)\n\(shareURL(for: spot).absoluteString)"
    }

    /// 길찾기 수단. 2km 이상이면 대중교통.
    public enum RouteMode: String, Sendable {
        case walk
        case publicTransit = "public"

        public static func forDistance(_ meters: Int?) -> RouteMode {
            (meters ?? 0) >= 2_000 ? .publicTransit : .walk
        }
    }

    /// 네이버지도 앱 길찾기: `nmap://route/{walk|public}?dlat&dlng&dname&appname`.
    public static func naverRouteApp(to spot: Spot, mode: RouteMode) -> URL {
        var components = URLComponents()
        components.scheme = "nmap"
        components.host = "route"
        components.path = "/\(mode.rawValue)"
        components.queryItems = [
            URLQueryItem(name: "dlat", value: String(spot.coordinate.latitude)),
            URLQueryItem(name: "dlng", value: String(spot.coordinate.longitude)),
            URLQueryItem(name: "dname", value: destinationName(spot)),
            URLQueryItem(name: "appname", value: appName),
        ]
        return components.url!
    }

    /// 앱이 없을 때 웹 길찾기: `https://map.naver.com/p/directions/-/{lng},{lat},{name}/-/{walk|transit}`.
    public static func naverRouteWeb(to spot: Spot, mode: RouteMode) -> URL {
        let name = escape(destinationName(spot), allowed: .urlPathAllowed.subtracting(CharacterSet(charactersIn: ",/")))
        let target = "\(spot.coordinate.longitude),\(spot.coordinate.latitude),\(name)"
        let webMode = mode == .walk ? "walk" : "transit"
        return URL(string: "https://map.naver.com/p/directions/-/\(target)/-/\(webMode)")!
    }

    /// 네이버지도 앱에서 장소만 표시(끝난 항목): `nmap://place?lat&lng&name&appname`.
    public static func naverPlaceApp(_ spot: Spot) -> URL {
        var components = URLComponents()
        components.scheme = "nmap"
        components.host = "place"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(spot.coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(spot.coordinate.longitude)),
            URLQueryItem(name: "name", value: destinationName(spot)),
            URLQueryItem(name: "appname", value: appName),
        ]
        return components.url!
    }

    /// 앱이 없을 때 웹에서 장소 검색.
    public static func naverPlaceWeb(_ spot: Spot) -> URL {
        let name = escape(destinationName(spot), allowed: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/")))
        return URL(string: "https://map.naver.com/p/search/\(name)")!
    }

    /// 오류 제보 메일. 상세는 제목 `[정보 오류] {id} {title}`, 설정은 `[정보 오류]` + 본문에 앱 버전·OS.
    public static func reportMail(subject: String, body: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        var items = [URLQueryItem(name: "subject", value: subject)]
        if let body { items.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = items
        return components.url!
    }

    public static func reportSubject(for spot: Spot) -> String {
        "[정보 오류] \(spot.id) \(spot.title)"
    }

    private static func destinationName(_ spot: Spot) -> String {
        spot.placeName ?? spot.title
    }

    private static func escape(_ text: String, allowed: CharacterSet) -> String {
        text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
