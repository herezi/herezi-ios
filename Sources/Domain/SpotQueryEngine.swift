import Foundation

// 기기 안 조회 엔진 (herezi-api ADR 0004, 이슈 #37). 앱은 사용자 좌표를 서버로 보내지 않고,
// 받아 둔 지역 데이터에서 거리·반경·기간·카테고리·무료·키워드·지도 영역을 여기서 계산한다.
// 의미는 서버 기준 구현과 같다: herezi-api `internal/domain/when.go`, `spot.go`(Overlaps·Ended·MatchesKeyword),
// `geo.go`(DistanceM), `store/store.go`(SpotFilter.Match), `store/memory`(정렬·페이지).

/// 기간·날짜 계산 기준 시간대(KST). 서버 `domain.Seoul`과 같다.
public enum KST {
    public static let timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone(secondsFromGMT: 9 * 3_600)!

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

extension WhenFilter {
    /// 항목이 겹쳐야 하는 구간 [from, to]. `from`은 now보다 앞서지 않는다 — 끝난 행사는 나오지 않는다.
    /// 서버 `When.Window`를 그대로 옮겼다:
    /// - now: [now, now]
    /// - today: [now, 오늘 23:59:59 KST]
    /// - weekend: [이번(또는 오늘이 주말이면 이번) 토요일 00:00 KST와 now 중 늦은 쪽, 일요일 23:59:59 KST]
    /// - week: [now, now + 7일]
    public func window(now: Date) -> (from: Date, to: Date) {
        let calendar = KST.calendar
        func endOfDay(_ date: Date) -> Date {
            let start = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .second, value: 86_399, to: start) ?? start
        }
        switch self {
        case .now:
            return (now, now)
        case .today:
            return (now, endOfDay(now))
        case .weekend:
            // Calendar.weekday: 일=1 … 토=7. 서버(Go): 일=0 … 토=6.
            let weekday = calendar.component(.weekday, from: now)
            let daysToSaturday: Int
            switch weekday {
            case 7: daysToSaturday = 0
            case 1: daysToSaturday = -1
            default: daysToSaturday = 7 - weekday
            }
            let saturday = calendar.date(byAdding: .day, value: daysToSaturday, to: now) ?? now
            let start = max(calendar.startOfDay(for: saturday), now)
            let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
            return (start, endOfDay(sunday))
        case .week:
            return (now, calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86_400))
        }
    }
}

extension Spot {
    /// `ends_at`이 now보다 앞서면 끝남. `ends_at`이 없으면 끝나지 않은 것으로 본다(서버 `Spot.Ended`).
    /// 지역 데이터의 `is_ended`는 서버의 `generated_at` 기준이라 쓰지 않고 기기 시각으로 다시 계산한다.
    public func hasEnded(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return endsAt < now
    }

    /// [from, to] 안에 한 순간이라도 진행 중인지. `ends_at`이 없으면 `starts_at` 한 순간짜리로 본다(서버 `Spot.Overlaps`).
    public func overlaps(from: Date, to: Date) -> Bool {
        let end = endsAt ?? startsAt
        return !(startsAt > to) && !(end < from)
    }

    /// 제목·장소명·주소 중 하나에 대소문자 무시 부분 일치. 빈 키워드는 모두 일치(서버 `Spot.MatchesKeyword`).
    /// 호출자가 공백을 잘라서 넘긴다. `%`·`_`는 글자 그대로.
    public func matchesKeyword(_ keyword: String) -> Bool {
        guard !keyword.isEmpty else { return true }
        let needle = keyword.lowercased()
        return [title, placeName, address].contains { $0?.lowercased().contains(needle) ?? false }
    }
}

/// 목록·지도·검색 조회를 지역 데이터에서 계산하는 순수 함수 모음.
public enum SpotQueryEngine {
    /// 지구 반지름(미터). 서버 `domain.DistanceM`과 같은 값.
    public static let earthRadiusMeters = 6_371_008.8

    /// 두 좌표 사이 거리(미터, 하버사인). 서버 `domain.DistanceM`과 같은 식.
    public static func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLng = (b.longitude - a.longitude) * rad
        let h =
            sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    /// 공통 필터(서버 `SpotFilter.Match`): 끝나지 않았고, 기간 창과 겹치고, 카테고리·무료 조건을 만족.
    public static func matches(
        _ spot: Spot, window: (from: Date, to: Date), now: Date, categories: Set<SpotCategory>, freeOnly: Bool
    ) -> Bool {
        if spot.hasEnded(at: now) || !spot.overlaps(from: window.from, to: window.to) { return false }
        if !categories.isEmpty && !categories.contains(spot.category) { return false }
        return !freeOnly || spot.isFree == true
    }

    /// 근처 목록·검색 (이전 `GET /v1/spots`). 반경 안 + 필터 + 키워드 → 거리순(같으면 id순) → 페이지.
    /// 커서는 다음 항목의 위치(정수 문자열). 항목의 `distanceMeters`는 기준점에서의 거리(반올림), `isEnded`는 false.
    public static func nearby(_ spots: [Spot], query: SpotQuery, now: Date) -> SpotPage {
        let window = query.when.window(now: now)
        let keyword = query.normalizedKeyword ?? ""
        let radius = Double(query.radiusMeters)
        var hits: [(spot: Spot, distance: Double)] = []
        for spot in spots {
            guard
                matches(
                    spot, window: window, now: now, categories: query.categories, freeOnly: query.freeOnly),
                spot.matchesKeyword(keyword)
            else { continue }
            let distance = distanceMeters(query.coordinate, spot.coordinate)
            if distance > radius { continue }
            hits.append((spot, distance))
        }
        hits.sort { ($0.distance, $0.spot.id) < ($1.distance, $1.spot.id) }
        let offset = query.cursor.flatMap(Int.init).map { max(0, $0) } ?? 0
        guard offset < hits.count else { return SpotPage(items: []) }
        let limit = max(1, query.limit)
        let end = min(hits.count, offset + limit)
        let items = hits[offset..<end].map { hit in
            hit.spot.copy(distanceMeters: .some(Int(hit.distance + 0.5)), isEnded: false)
        }
        return SpotPage(items: items, nextCursor: end < hits.count ? String(end) : nil)
    }

    /// 지도 영역 (이전 `GET /v1/spots/map`). 영역 안 + 필터 → 영역 중심에서 가까운 순(같으면 id순) 최대 `limit`개.
    /// 넘치면 `truncated`. 거리는 붙이지 않는다(서버와 같음 — 화면이 사용자 위치로 따로 계산).
    public static func inBounds(_ spots: [Spot], query: SpotMapQuery, now: Date) -> SpotMap {
        let window = query.when.window(now: now)
        let center = query.bounds.center
        var hits: [(spot: Spot, distance: Double)] = []
        for spot in spots {
            guard query.bounds.contains(spot.coordinate),
                matches(spot, window: window, now: now, categories: query.categories, freeOnly: query.freeOnly)
            else { continue }
            hits.append((spot, distanceMeters(center, spot.coordinate)))
        }
        hits.sort { ($0.distance, $0.spot.id) < ($1.distance, $1.spot.id) }
        let limit = max(1, query.limit)
        let items = hits.prefix(limit).map { $0.spot.isEnded ? $0.spot.copy(isEnded: false) : $0.spot }
        return SpotMap(items: items, truncated: hits.count > limit)
    }
}
