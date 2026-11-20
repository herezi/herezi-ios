import Foundation

/// Pure, locale-fixed (ko_KR, Asia/Seoul) formatting shared by all features.
public enum SpotFormatting {
    static let seoul = TimeZone(identifier: "Asia/Seoul") ?? .current
    static let korean = Locale(identifier: "ko_KR")

    /// DESIGN §6.1: 1km 미만 "350m"(10m 단위 반올림), 10km 미만 "1.2km"(소수 1자리), 그 이상 "12km".
    public static func distance(meters: Int?) -> String? {
        guard let meters else { return nil }
        let rounded = Int((Double(meters) / 10).rounded()) * 10
        if rounded < 1000 { return "\(rounded)m" }
        let km = Double(meters) / 1000
        if (km * 10).rounded() / 10 >= 10 { return "\(Int(km.rounded()))km" }
        return String(format: "%.1fkm", km)
    }

    /// 스크린리더용 거리: "350미터", "1.2킬로미터".
    public static func spokenDistance(meters: Int?) -> String? {
        guard let text = distance(meters: meters) else { return nil }
        if text.hasSuffix("km") { return String(text.dropLast(2)) + "킬로미터" }
        return String(text.dropLast(1)) + "미터"
    }

    /// 카드의 기간 줄 (DESIGN §6.1, KST).
    /// - 오늘 시작·오늘 끝: "오늘 18:00 – 22:00"
    /// - 진행 중이고 오늘 끝: "오늘까지" (`emphasized` — text.primary SemiBold)
    /// - 여러 날: "11.20(금) – 12.14(일)", 해가 다르면 "2026.12.20 – 2027.01.04"
    /// - `endsAt` 없음: "11.20(금)부터"
    public static func cardPeriod(start: Date, end: Date?, now: Date) -> (text: String, emphasized: Bool) {
        let calendar = seoulCalendar
        guard let end else { return ("\(dayWithWeekday(start, calendar: calendar))부터", false) }
        if calendar.isDate(start, inSameDayAs: end) {
            if calendar.isDate(start, inSameDayAs: now) {
                guard hasTime(start, calendar: calendar) || hasTime(end, calendar: calendar) else {
                    return ("오늘", false)
                }
                return ("오늘 \(time(start, calendar: calendar)) – \(time(end, calendar: calendar))", false)
            }
            return (dayWithWeekday(start, calendar: calendar), false)
        }
        if start <= now, calendar.isDate(end, inSameDayAs: now) { return ("오늘까지", true) }
        if calendar.component(.year, from: start) != calendar.component(.year, from: end) {
            return ("\(fullDate(start, calendar: calendar)) – \(fullDate(end, calendar: calendar))", false)
        }
        return ("\(dayWithWeekday(start, calendar: calendar)) – \(dayWithWeekday(end, calendar: calendar))", false)
    }

    /// 스크린리더용 기간: "11월 20일부터 12월 14일까지", "11월 20일부터".
    public static func spokenPeriod(start: Date, end: Date?) -> String {
        let calendar = seoulCalendar
        guard let end else { return "\(monthDay(start, calendar: calendar))부터" }
        if calendar.isDate(start, inSameDayAs: end) { return monthDay(start, calendar: calendar) }
        return "\(monthDay(start, calendar: calendar))부터 \(monthDay(end, calendar: calendar))까지"
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

    static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        calendar.locale = korean
        return calendar
    }

    /// "11.20(금)"
    static func dayWithWeekday(_ date: Date, calendar: Calendar) -> String {
        "\(shortDate(date, calendar: calendar))(\(weekday(date, calendar: calendar)))"
    }

    /// "2026.12.20"
    static func fullDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "11월 20일"
    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
    }

    /// "18:00"
    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 00:00이 아니면 시각 정보가 있다고 본다.
    static func hasTime(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0
    }

    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%d.%02d", parts.month ?? 0, parts.day ?? 0)
    }

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        let index = calendar.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}
