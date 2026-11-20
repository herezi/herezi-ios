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
