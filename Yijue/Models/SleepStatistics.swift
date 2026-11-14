import Foundation

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "最近 7 晚"
        case .month: return "本月"
        }
    }
}

struct NightPoint: Identifiable {
    let day: Date
    let key: String
    let record: SleepRecord?

    var id: String { key }

    var duration: TimeInterval? { record?.duration }

    var bedSignedMinutes: Int? {
        guard let bed = record?.bedTime else { return nil }
        return SleepCalendar.signedMinutes(bed)
    }

    var wakeMinutes: Int? {
        guard let wake = record?.wakeTime else { return nil }
        return SleepCalendar.minutesOfDay(wake)
    }
}

enum SleepStatistics {
    static func points(
        records: [SleepRecord],
        period: StatsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [NightPoint] {
        var byKey: [String: SleepRecord] = [:]
        for record in records {
            if let existing = byKey[record.nightKey] {
                // 同一夜异常重复时保留更完整的一条
                if (existing.duration ?? 0) < (record.duration ?? 0) {
                    byKey[record.nightKey] = record
                }
            } else {
                byKey[record.nightKey] = record
            }
        }

        switch period {
        case .week:
            var keys: [String] = []
            for offset in stride(from: 6, through: 0, by: -1) {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                keys.append(SleepCalendar.nightKey(for: date, calendar: calendar))
            }
            return keys.map { key in
                NightPoint(
                    day: SleepCalendar.date(fromKey: key, calendar: calendar) ?? now,
                    key: key,
                    record: byKey[key]
                )
            }

        case .month:
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let range = calendar.range(of: .day, in: .month, for: monthStart) else {
                return []
            }
            return range.compactMap { day -> NightPoint? in
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
                let key = SleepCalendar.keyFormatter.string(from: date)
                return NightPoint(day: date, key: key, record: byKey[key])
            }
        }
    }

    static func completedRecords(_ records: [SleepRecord]) -> [SleepRecord] {
        records.filter { $0.isComplete }
    }

    static func averageDuration(_ records: [SleepRecord]) -> TimeInterval? {
        let durations = completedRecords(records).compactMap(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// 循环平均，避免 23:50 与 00:10 平均成 12:00。
    static func averageBedMinutes(_ records: [SleepRecord]) -> Int? {
        let minutes = completedRecords(records).compactMap { record -> Int? in
            guard let bed = record.bedTime else { return nil }
            return SleepCalendar.minutesOfDay(bed)
        }
        guard !minutes.isEmpty else { return nil }

        let angles = minutes.map { Double($0) / 1440.0 * 2 * Double.pi }
        let x = angles.map(cos).reduce(0, +) / Double(angles.count)
        let y = angles.map(sin).reduce(0, +) / Double(angles.count)
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * Double.pi }
        return Int((angle / (2 * Double.pi) * 1440).rounded()) % 1440
    }

    static func averageWakeMinutes(_ records: [SleepRecord]) -> Int? {
        let minutes = completedRecords(records).compactMap { record -> Int? in
            guard let wake = record.wakeTime else { return nil }
            return SleepCalendar.minutesOfDay(wake)
        }
        guard !minutes.isEmpty else { return nil }
        return minutes.reduce(0, +) / minutes.count
    }

    static func metGoalCount(_ records: [SleepRecord], goalMinutes: Int) -> Int {
        completedRecords(records).filter { record in
            guard let duration = record.duration else { return false }
            return duration >= TimeInterval(goalMinutes * 60)
        }.count
    }

    /// 从最近一条完整记录往前数；缺一晚或不足目标都会中断。
    static func streak(records: [SleepRecord], goalMinutes: Int, calendar: Calendar = .current) -> Int {
        let complete = records.filter { $0.isComplete && $0.duration != nil }
        guard let latest = complete.max(by: { $0.nightKey < $1.nightKey }),
              var day = SleepCalendar.date(fromKey: latest.nightKey, calendar: calendar) else {
            return 0
        }

        var byKey: [String: SleepRecord] = [:]
        for record in complete { byKey[record.nightKey] = record }

        var count = 0
        while count < 3650 {
            let key = SleepCalendar.keyFormatter.string(from: day)
            guard let record = byKey[key],
                  let duration = record.duration,
                  duration >= TimeInterval(goalMinutes * 60) else {
                break
            }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
