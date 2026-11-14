import Foundation

enum SleepCalendar {
    static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// 中午 12 点为日界：12:00 之后算当天，12:00 之前算前一天。
    static func nightKey(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let base = calendar.startOfDay(for: date)
        let evening = hour < 12
            ? calendar.date(byAdding: .day, value: -1, to: base) ?? base
            : base
        return keyFormatter.string(from: evening)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        guard let date = keyFormatter.date(from: key) else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func window(
        forKey key: String,
        startMinutes: Int,
        endMinutes: Int,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard let base = date(fromKey: key, calendar: calendar) else { return nil }
        guard
            let start = calendar.date(byAdding: .minute, value: startMinutes, to: base),
            let nextDay = calendar.date(byAdding: .day, value: 1, to: base),
            let end = calendar.date(byAdding: .minute, value: endMinutes, to: nextDay)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 以午夜为界的带符号分钟：18:00 之后为负，00:00 之后为正，便于跨零点画图。
    static func signedMinutes(_ date: Date, calendar: Calendar = .current) -> Int {
        let minutes = minutesOfDay(date, calendar: calendar)
        return minutes >= 12 * 60 ? minutes - 24 * 60 : minutes
    }

    static func clockText(minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    static func clockText(for date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(minutes) 分"
    }

    static func shortDurationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    static func dayLabel(forKey key: String) -> String {
        guard let date = date(fromKey: key) else { return key }
        return shortDayFormatter.string(from: date)
    }

    static func weekdayLabel(forKey key: String) -> String {
        guard let date = date(fromKey: key) else { return "" }
        return weekdayFormatter.string(from: date)
    }

    static func dayTitle(forKey key: String) -> String {
        guard let date = date(fromKey: key) else { return key }
        return "\(shortDayFormatter.string(from: date)) \(weekdayFormatter.string(from: date))"
    }
}
