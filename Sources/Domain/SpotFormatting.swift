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
                let startTime = time(start, calendar: calendar)
                let endTime = time(end, calendar: calendar)
                return (startTime == endTime ? "오늘 \(startTime)" : "오늘 \(startTime) – \(endTime)", false)
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

    // MARK: 상세 (S3)

    /// 상세 기간 값: "11월 20일(금) – 12월 14일(일)", 하루면 "11월 20일(금)", 끝이 없으면 "11월 20일(금)부터".
    /// 해가 다르면 "2026년 12월 20일(일) – 2027년 1월 4일(월)".
    public static func detailPeriod(start: Date, end: Date?) -> String {
        let calendar = seoulCalendar
        func day(_ date: Date, year: Bool) -> String {
            let prefix = year ? "\(calendar.component(.year, from: date))년 " : ""
            return "\(prefix)\(monthDay(date, calendar: calendar))(\(weekday(date, calendar: calendar)))"
        }
        guard let end else { return "\(day(start, year: false))부터" }
        if calendar.isDate(start, inSameDayAs: end) { return day(start, year: false) }
        let differentYear = calendar.component(.year, from: start) != calendar.component(.year, from: end)
        return "\(day(start, year: differentYear)) – \(day(end, year: differentYear))"
    }

    /// 상세 기간 보조 문구: 진행 중이고 오늘 끝나면 "오늘까지".
    public static func detailPeriodNote(start: Date, end: Date?, now: Date) -> String? {
        let calendar = seoulCalendar
        guard let end, start <= now, end >= now, calendar.isDate(end, inSameDayAs: now) else { return nil }
        return "오늘까지"
    }

    /// 시간 행: 시작·끝 시각이 00:00이 아닐 때만. 여러 날 "매일 17:00 – 22:00", 하루 "18:00 – 22:00",
    /// 끝이 없으면 "18:00부터".
    public static func timeRange(start: Date, end: Date?) -> String? {
        let calendar = seoulCalendar
        guard let end else {
            return hasTime(start, calendar: calendar) ? "\(time(start, calendar: calendar))부터" : nil
        }
        guard hasTime(start, calendar: calendar) || hasTime(end, calendar: calendar) else { return nil }
        let startTime = time(start, calendar: calendar)
        let endTime = time(end, calendar: calendar)
        let range = startTime == endTime ? startTime : "\(startTime) – \(endTime)"
        return calendar.isDate(start, inSameDayAs: end) ? range : "매일 \(range)"
    }

    /// 종료 안내: "11월 17일에 끝난 볼거리예요." 끝난 날을 모르면 "끝난 볼거리예요."
    public static func endedNotice(end: Date?) -> String {
        guard let end else { return "끝난 볼거리예요." }
        return "\(monthDay(end, calendar: seoulCalendar))에 끝난 볼거리예요."
    }

    /// 갱신 시각 (DESIGN §8): 1시간 안 "N분 전 갱신"(1분 미만 "방금 갱신"), 24시간 안 "N시간 전 갱신",
    /// 그 이상 "11월 18일 갱신".
    public static func fetchedText(_ fetchedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(fetchedAt)))
        switch seconds {
        case ..<60: return "방금 갱신"
        case ..<3_600: return "\(seconds / 60)분 전 갱신"
        case ..<86_400: return "\(seconds / 3_600)시간 전 갱신"
        default: return "\(monthDay(fetchedAt, calendar: seoulCalendar)) 갱신"
        }
    }

    /// 스크린리더용 절대 시각: "11월 20일 오전 9시 12분".
    public static func spokenDateTime(_ date: Date) -> String {
        let calendar = seoulCalendar
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let ampm = hour < 12 ? "오전" : "오후"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let minute = (parts.minute ?? 0) == 0 ? "" : " \(parts.minute ?? 0)분"
        return "\(monthDay(date, calendar: calendar)) \(ampm) \(hour12)시\(minute)"
    }

    /// 출처 이름 (DESIGN §8). 모르는 값은 그대로.
    public static func sourceName(_ source: String) -> String {
        switch source {
        case "tourapi": "한국관광공사"
        case "kopis": "KOPIS 공연예술통합전산망"
        case "seoul_culture": "서울 열린데이터광장"
        default: source
        }
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
