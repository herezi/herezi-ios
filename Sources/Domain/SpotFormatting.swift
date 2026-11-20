import Foundation

/// Pure, locale-fixed (ko_KR, Asia/Seoul) formatting shared by all features.
public enum SpotFormatting {
    static let seoul = TimeZone(identifier: "Asia/Seoul") ?? .current
    static let korean = Locale(identifier: "ko_KR")

    /// "350m", "1.2km".
    public static func distance(meters: Int?) -> String? {
        guard let meters else { return nil }
        if meters < 1000 { return "\(meters)m" }
        let km = Double(meters) / 1000
        return String(format: "%.1fkm", km)
    }

    /// "11.20 (금)" for single day, "11.20 – 11.24" for a range. Times are shown in Seoul time.
    public static func dateRange(start: Date, end: Date?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let startText = shortDate(start, calendar: calendar)
        guard let end, !calendar.isDate(start, inSameDayAs: end) else {
            return "\(startText) (\(weekday(start, calendar: calendar)))"
        }
        return "\(startText) – \(shortDate(end, calendar: calendar))"
    }

    /// 갱신 시각의 상대 표현: "방금", "5분 전", "3시간 전", "2일 전". 30일이 넘으면 날짜("11.20")로.
    /// 시계가 어긋나 미래 시각이 오면 "방금"으로 본다.
    public static func relativeTime(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "방금"
        case ..<3_600: return "\(seconds / 60)분 전"
        case ..<86_400: return "\(seconds / 3_600)시간 전"
        case ..<(30 * 86_400): return "\(seconds / 86_400)일 전"
        default:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = seoul
            return shortDate(date, calendar: calendar)
        }
    }

    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%d.%02d", parts.month ?? 0, parts.day ?? 0)
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        let index = calendar.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}
