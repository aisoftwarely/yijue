import Foundation

struct SleepSettings: Codable, Equatable {
    var goalMinutes: Int = 450                    // 7 小时 30 分
    var minInferredMinutes: Int = 180             // 静止推测最短 3 小时
    var bedtimeReminderEnabled: Bool = false
    var bedtimeReminderMinutes: Int = 22 * 60 + 30
    var wakeAlarmEnabled: Bool = false
    var wakeAlarmMinutes: Int = 7 * 60
    var wakeAlarmWeekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]   // Calendar: 1 = 周日
    var motionInferenceEnabled: Bool = true
    var nightWindowStartMinutes: Int = 20 * 60
    var nightWindowEndMinutes: Int = 12 * 60
    var useNotificationFallback: Bool = true
    var setupAcknowledged: Bool = false
    var morningSummaryEnabled: Bool = true       // 起床后 30 分钟
    var weeklySummaryEnabled: Bool = true        // 周一早上
    var monthlySummaryEnabled: Bool = true       // 每月 1 号早上

    init() {}

    private enum CodingKeys: String, CodingKey {
        case goalMinutes, minInferredMinutes
        case bedtimeReminderEnabled, bedtimeReminderMinutes
        case wakeAlarmEnabled, wakeAlarmMinutes, wakeAlarmWeekdays
        case motionInferenceEnabled
        case nightWindowStartMinutes, nightWindowEndMinutes
        case useNotificationFallback, setupAcknowledged
        case morningSummaryEnabled, weeklySummaryEnabled, monthlySummaryEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalMinutes = (try? c.decode(Int.self, forKey: .goalMinutes)) ?? 450
        minInferredMinutes = (try? c.decode(Int.self, forKey: .minInferredMinutes)) ?? 180
        bedtimeReminderEnabled = (try? c.decode(Bool.self, forKey: .bedtimeReminderEnabled)) ?? false
        bedtimeReminderMinutes = (try? c.decode(Int.self, forKey: .bedtimeReminderMinutes)) ?? 22 * 60 + 30
        wakeAlarmEnabled = (try? c.decode(Bool.self, forKey: .wakeAlarmEnabled)) ?? false
        wakeAlarmMinutes = (try? c.decode(Int.self, forKey: .wakeAlarmMinutes)) ?? 7 * 60
        wakeAlarmWeekdays = (try? c.decode([Int].self, forKey: .wakeAlarmWeekdays)) ?? [1, 2, 3, 4, 5, 6, 7]
        motionInferenceEnabled = (try? c.decode(Bool.self, forKey: .motionInferenceEnabled)) ?? true
        nightWindowStartMinutes = (try? c.decode(Int.self, forKey: .nightWindowStartMinutes)) ?? 20 * 60
        nightWindowEndMinutes = (try? c.decode(Int.self, forKey: .nightWindowEndMinutes)) ?? 12 * 60
        useNotificationFallback = (try? c.decode(Bool.self, forKey: .useNotificationFallback)) ?? true
        setupAcknowledged = (try? c.decode(Bool.self, forKey: .setupAcknowledged)) ?? false
        morningSummaryEnabled = (try? c.decode(Bool.self, forKey: .morningSummaryEnabled)) ?? true
        weeklySummaryEnabled = (try? c.decode(Bool.self, forKey: .weeklySummaryEnabled)) ?? true
        monthlySummaryEnabled = (try? c.decode(Bool.self, forKey: .monthlySummaryEnabled)) ?? true
    }

    var wakeAlarmMode: WakeAlarmRepeatMode {
        get {
            let set = Set(wakeAlarmWeekdays)
            if set == Set(1...7) { return .everyday }
            if set == Set([2, 3, 4, 5, 6]) { return .weekdays }
            if set == Set([1, 7]) { return .weekends }
            return .custom
        }
        set {
            switch newValue {
            case .everyday: wakeAlarmWeekdays = [1, 2, 3, 4, 5, 6, 7]
            case .weekdays: wakeAlarmWeekdays = [2, 3, 4, 5, 6]
            case .weekends: wakeAlarmWeekdays = [1, 7]
            case .custom: break
            }
        }
    }
}

enum WakeAlarmRepeatMode: String, CaseIterable, Identifiable {
    case everyday
    case weekdays
    case weekends
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: return "每天"
        case .weekdays: return "工作日"
        case .weekends: return "周末"
        case .custom: return "自定义"
        }
    }
}
