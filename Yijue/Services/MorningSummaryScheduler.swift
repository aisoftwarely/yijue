import Foundation
import UserNotifications

/// 每天固定时间推送「昨晚睡了多久」，周一附本周总结、每月 1 号附上月总结。
final class MorningSummaryScheduler {
    static let shared = MorningSummaryScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "summary."
    /// 起床到这个时间之前不推，避免还在睡时被吵醒。
    private let notBeforeWakeDelay: TimeInterval = 5 * 60
    /// 起床超过 3 小时就不再补排当天的小结。
    private let staleWindow: TimeInterval = 3 * 3600
    /// Calendar 的 weekday：2 = 周一。
    private let weeklyWeekday = 2

    /// 收到起床记录后调用；也可在 App 打开时调用，用来补排。
    /// 小结在设置的时间推送（默认 09:30）；如果那时还在睡，就等起床 5 分钟后。
    func reschedule(settings: SleepSettings, records: [SleepRecord], now: Date = Date()) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        let calendar = Calendar.current

        guard settings.morningSummaryEnabled || settings.weeklySummaryEnabled || settings.monthlySummaryEnabled,
              let record = records.first(where: {
                  $0.nightKey == SleepCalendar.nightKey(for: now) && $0.isComplete
              }),
              let wakeAt = record.wakeTime,
              now.timeIntervalSince(wakeAt) <= staleWindow,
              let target = calendar.date(
                  byAdding: .minute,
                  value: settings.morningSummaryMinutes,
                  to: calendar.startOfDay(for: wakeAt)
              )
        else { return }

        // 固定时间推送；如果那时还在睡，就等起床 5 分钟后。
        let fireAt = max(target, wakeAt.addingTimeInterval(notBeforeWakeDelay))
        guard fireAt > now else { return }

        var title = ""
        var bodyLines: [String] = []
        var identifier = "morning"

        if settings.morningSummaryEnabled,
           let bed = record.bedTime,
           let duration = record.duration {
            title = "昨晚睡了 \(SleepCalendar.durationText(duration))"
            bodyLines.append(
                "\(SleepCalendar.clockText(for: bed)) 入睡 · \(SleepCalendar.clockText(for: wakeAt)) 起床"
            )
        }

        if settings.weeklySummaryEnabled,
           calendar.component(.weekday, from: now) == weeklyWeekday,
           let weekly = weeklyStats(records: records, now: now, goalMinutes: settings.goalMinutes) {
            if title.isEmpty {
                title = "本周睡眠总结"
                identifier = "weekly"
            }
            bodyLines.append(
                "最近 7 晚平均 \(SleepCalendar.durationText(weekly.average)) · 达标 \(weekly.met) 天"
            )
        }

        if settings.monthlySummaryEnabled,
           calendar.component(.day, from: now) == 1,
           let monthly = monthlyStats(records: records, now: now, goalMinutes: settings.goalMinutes) {
            if title.isEmpty {
                title = "上月睡眠总结"
                identifier = "monthly"
            }
            bodyLines.append(
                "上月平均 \(SleepCalendar.durationText(monthly.average)) · 达标 \(monthly.met) 天"
            )
        }

        guard !title.isEmpty, !bodyLines.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = bodyLines.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = "sleep.summary"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, fireAt.timeIntervalSince(now)),
            repeats: false
        )
        try? await center.add(
            UNNotificationRequest(identifier: "\(prefix)\(identifier)", content: content, trigger: trigger)
        )
    }

    // MARK: - 统计

    private func weeklyStats(
        records: [SleepRecord],
        now: Date,
        goalMinutes: Int
    ) -> (average: TimeInterval, met: Int)? {
        let relevant = SleepStatistics
            .points(records: records, period: .week, now: now)
            .compactMap(\.record)
        guard let average = SleepStatistics.averageDuration(relevant) else { return nil }
        return (average, SleepStatistics.metGoalCount(relevant, goalMinutes: goalMinutes))
    }

    private func monthlyStats(
        records: [SleepRecord],
        now: Date,
        goalMinutes: Int
    ) -> (average: TimeInterval, met: Int)? {
        let calendar = Calendar.current
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
            let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart)
        else { return nil }

        let relevant = records.filter { record in
            guard record.isComplete,
                  let day = SleepCalendar.date(fromKey: record.nightKey, calendar: calendar)
            else { return false }
            return day >= previousStart && day < monthStart
        }
        guard let average = SleepStatistics.averageDuration(relevant) else { return nil }
        return (average, SleepStatistics.metGoalCount(relevant, goalMinutes: goalMinutes))
    }
}
