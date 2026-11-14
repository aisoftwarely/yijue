import Foundation
import SwiftUI
import UserNotifications

enum WakeAlarmMode: String {
    case alarmKit
    case notification
    case off

    var label: String {
        switch self {
        case .alarmKit: return "系统闹钟"
        case .notification: return "普通通知"
        case .off: return "未开启"
        }
    }

    var detail: String {
        switch self {
        case .alarmKit: return "可穿透静音与专注模式"
        case .notification: return "静音或专注模式下可能不响"
        case .off: return "起床闹钟未开启"
        }
    }
}

struct WakeAlarmResult {
    var mode: WakeAlarmMode
    var detail: String
    var scheduledCount: Int
}

final class WakeAlarmScheduler {
    static let shared = WakeAlarmScheduler()

    private let fallback = NotificationWakeAlarmScheduler()

    func reschedule(settings: SleepSettings) async -> WakeAlarmResult {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), settings.wakeAlarmEnabled {
            let alarmResult = await AlarmKitWakeAlarmScheduler.shared.reschedule(settings: settings)
            if alarmResult.mode == .alarmKit {
                _ = await fallback.reschedule(settings: settings, enabled: false)
                return alarmResult
            }
            if settings.useNotificationFallback {
                let result = await fallback.reschedule(settings: settings, enabled: true)
                return WakeAlarmResult(
                    mode: result.scheduledCount > 0 ? .notification : .off,
                    detail: "系统闹钟不可用（\(alarmResult.detail)），已改用普通通知；静音或专注模式下可能不响。",
                    scheduledCount: result.scheduledCount
                )
            }
            return alarmResult
        }
        #endif

        let result = await fallback.reschedule(settings: settings, enabled: settings.wakeAlarmEnabled)
        if settings.wakeAlarmEnabled && result.scheduledCount > 0 {
            return WakeAlarmResult(mode: .notification, detail: WakeAlarmMode.notification.detail, scheduledCount: result.scheduledCount)
        }
        return WakeAlarmResult(mode: .off, detail: "起床闹钟未开启", scheduledCount: 0)
    }

    /// 2 分钟后的测试。真机验证锁屏/静音/专注下的表现。
    func scheduleTest(settings: SleepSettings) async -> WakeAlarmResult {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let result = await AlarmKitWakeAlarmScheduler.shared.scheduleTest()
            if result.mode == .alarmKit {
                return result
            }
        }
        #endif
        return await fallback.scheduleTest()
    }
}

// MARK: - 通知兜底

final class NotificationWakeAlarmScheduler {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "sleep.wake."

    func reschedule(settings: SleepSettings, enabled: Bool) async -> WakeAlarmResult {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        guard enabled else {
            return WakeAlarmResult(mode: .off, detail: "起床闹钟未开启", scheduledCount: 0)
        }

        let weekdays = settings.wakeAlarmWeekdays.isEmpty ? Array(1...7) : settings.wakeAlarmWeekdays
        var scheduled = 0

        for weekday in weekdays {
            let content = UNMutableNotificationContent()
            content.title = "该起床了"
            content.body = "新的一天开始了。"
            content.sound = .default

            var components = DateComponents()
            components.weekday = weekday
            components.hour = settings.wakeAlarmMinutes / 60
            components.minute = settings.wakeAlarmMinutes % 60

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(weekday)",
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                continue
            }
        }

        return WakeAlarmResult(
            mode: scheduled > 0 ? .notification : .off,
            detail: WakeAlarmMode.notification.detail,
            scheduledCount: scheduled
        )
    }

    func scheduleTest() async -> WakeAlarmResult {
        let content = UNMutableNotificationContent()
        content.title = "起床闹钟测试"
        content.body = "如果你看到这条通知，普通通知兜底可用。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(prefix)test",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return WakeAlarmResult(mode: .notification, detail: "已排一条 2 分钟后的测试通知", scheduledCount: 1)
        } catch {
            return WakeAlarmResult(mode: .off, detail: "测试通知排程失败：\(error.localizedDescription)", scheduledCount: 0)
        }
    }
}

// MARK: - AlarmKit

#if canImport(AlarmKit)
import AlarmKit

struct YijueAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
final class AlarmKitWakeAlarmScheduler {
    static let shared = AlarmKitWakeAlarmScheduler()

    private let alarmIdentifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let testIdentifier = UUID(uuidString: "11111111-2222-3333-4444-666666666666")!

    func reschedule(settings: SleepSettings) async -> WakeAlarmResult {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard case .authorized = state else {
                try? await AlarmManager.shared.cancel(id: alarmIdentifier)
                return WakeAlarmResult(mode: .off, detail: "系统闹钟权限未开启", scheduledCount: 0)
            }

            try? await AlarmManager.shared.cancel(id: alarmIdentifier)

            guard settings.wakeAlarmEnabled else {
                return WakeAlarmResult(mode: .off, detail: "起床闹钟未开启", scheduledCount: 0)
            }

            let attributes = Self.attributes()
            let time = Alarm.Schedule.Relative.Time(
                hour: settings.wakeAlarmMinutes / 60,
                minute: settings.wakeAlarmMinutes % 60
            )
            let weekdays = Self.weekdays(settings.wakeAlarmWeekdays)

            let schedule = Alarm.Schedule.relative(
                Alarm.Schedule.Relative(
                    time: time,
                    repeats: weekdays.isEmpty ? .never : .weekly(weekdays)
                )
            )

            let configuration = AlarmManager.AlarmConfiguration(
                schedule: schedule,
                attributes: attributes
            )

            _ = try await AlarmManager.shared.schedule(id: alarmIdentifier, configuration: configuration)
            return WakeAlarmResult(mode: .alarmKit, detail: WakeAlarmMode.alarmKit.detail, scheduledCount: 1)
        } catch {
            return WakeAlarmResult(
                mode: .off,
                detail: "系统闹钟排程失败：\(error.localizedDescription)",
                scheduledCount: 0
            )
        }
    }

    func scheduleTest() async -> WakeAlarmResult {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard case .authorized = state else {
                return WakeAlarmResult(mode: .off, detail: "系统闹钟权限未开启", scheduledCount: 0)
            }

            try? await AlarmManager.shared.cancel(id: testIdentifier)

            let configuration = AlarmManager.AlarmConfiguration(
                schedule: .fixed(Date().addingTimeInterval(120)),
                attributes: Self.attributes()
            )
            _ = try await AlarmManager.shared.schedule(id: testIdentifier, configuration: configuration)
            return WakeAlarmResult(mode: .alarmKit, detail: "已排一个 2 分钟后的系统闹钟", scheduledCount: 1)
        } catch {
            return WakeAlarmResult(
                mode: .off,
                detail: "系统闹钟测试排程失败：\(error.localizedDescription)",
                scheduledCount: 0
            )
        }
    }

    private static func attributes() -> AlarmAttributes<YijueAlarmMetadata> {
        let stopButton = AlarmButton(
            text: "停止",
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let alert = AlarmPresentation.Alert(
            title: "该起床了",
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)
        return AlarmAttributes(
            presentation: presentation,
            metadata: YijueAlarmMetadata(),
            tintColor: .indigo
        )
    }

    private static func weekdays(_ calendarWeekdays: [Int]) -> [Alarm.Schedule.Weekday] {
        var result: [Alarm.Schedule.Weekday] = []
        for day in calendarWeekdays.sorted() {
            switch day {
            case 1: result.append(.sunday)
            case 2: result.append(.monday)
            case 3: result.append(.tuesday)
            case 4: result.append(.wednesday)
            case 5: result.append(.thursday)
            case 6: result.append(.friday)
            case 7: result.append(.saturday)
            default: break
            }
        }
        return result
    }
}
#endif
