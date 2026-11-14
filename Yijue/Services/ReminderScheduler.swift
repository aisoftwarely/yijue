import Foundation
import UserNotifications

final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "sleep.bedtime"
    private let bedtimeIdentifier = "sleep.bedtime"

    private let messages = [
        "今晚也早点休息。",
        "把手机放下，准备睡了。",
        "睡够一点，明天精神会好很多。"
    ]

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 只清理睡前提醒自己的通知，不动起床闹钟和小结。
    func reschedule(settings: SleepSettings) async -> Int {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        guard settings.bedtimeReminderEnabled else { return 0 }

        let content = UNMutableNotificationContent()
        content.title = "该准备睡了"
        content.body = messages.randomElement() ?? "今晚也早点休息。"
        content.sound = .default

        var components = DateComponents()
        components.hour = settings.bedtimeReminderMinutes / 60
        components.minute = settings.bedtimeReminderMinutes % 60

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: bedtimeIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
        return 1
    }

    /// 1 分钟后的测试通知，用来确认权限和排程都正常。
    func scheduleTest() async -> String {
        let content = UNMutableNotificationContent()
        content.title = "测试通知"
        content.body = "能看到这条，说明通知权限和排程都正常。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(prefix).test",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return "已排一条 1 分钟后的测试通知，锁屏等一下。"
        } catch {
            return "测试通知排程失败：\(error.localizedDescription)"
        }
    }

    func nextBedtimeDate(settings: SleepSettings, now: Date = Date()) -> Date? {
        guard settings.bedtimeReminderEnabled else { return nil }
        var components = DateComponents()
        components.hour = settings.bedtimeReminderMinutes / 60
        components.minute = settings.bedtimeReminderMinutes % 60
        return Calendar.current.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        )
    }
}
