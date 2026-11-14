import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class SleepStore: ObservableObject {
    static let shared = SleepStore()

    @Published private(set) var records: [SleepRecord] = []
    @Published private(set) var events: [SleepEvent] = []
    @Published private(set) var motionState: MotionState = MotionState()

    @Published var settings: SleepSettings = SleepSettings() {
        didSet {
            guard !isApplyingSnapshot, settings != oldValue else { return }
            SleepRepository.shared.saveSettings(settings)
        }
    }

    @Published private(set) var notificationDenied = false
    @Published private(set) var scheduledReminderCount = 0
    @Published private(set) var wakeAlarmMode: WakeAlarmMode = .off
    @Published private(set) var wakeAlarmDetail = ""
    @Published private(set) var motionAuthorizationLabel = "未询问"
    @Published private(set) var motionAvailable = false
    @Published private(set) var lastRefreshAt: Date?

    private var isApplyingSnapshot = false
    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .sleepStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    // MARK: - 派生数据

    var sortedRecords: [SleepRecord] {
        records.sorted { $0.nightKey > $1.nightKey }
    }

    var latestRecord: SleepRecord? {
        sortedRecords.first
    }

    var latestDraft: SleepRecord? {
        sortedRecords.first { !$0.isComplete }
    }

    var lastShortcutEventAt: Date? {
        events
            .filter { $0.source == .shortcut }
            .map(\.at)
            .max()
    }

    var shortcutEventsLast7Days: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return events.filter { $0.source == .shortcut && $0.at >= cutoff }.count
    }

    var hasShortcutEvent: Bool {
        lastShortcutEventAt != nil
    }

    var lastNightRecord: SleepRecord? {
        let key = SleepCalendar.nightKey(for: Date())
        return records.first { $0.nightKey == key }
            ?? records.first { $0.nightKey == SleepCalendar.nightKey(for: Date().addingTimeInterval(-24 * 3600)) }
            ?? latestRecord
    }

    var goalInterval: TimeInterval { TimeInterval(settings.goalMinutes * 60) }

    func meetsGoal(_ record: SleepRecord?) -> Bool {
        guard let duration = record?.duration else { return false }
        return duration >= goalInterval
    }

    // MARK: - 写入

    @discardableResult
    func recordEvent(kind: SleepEventKind, source: SleepSource, at date: Date = Date()) -> Bool {
        let changed = SleepRepository.shared.recordEvent(kind: kind, at: date, source: source)
        refresh()
        return changed
    }

    @discardableResult
    func saveManual(bed: Date, wake: Date, nightKey: String? = nil) -> SleepRecord? {
        let record = SleepRepository.shared.saveManual(bed: bed, wake: wake, nightKey: nightKey)
        refresh()
        return record
    }

    func delete(nightKey: String) {
        SleepRepository.shared.delete(nightKey: nightKey)
        refresh()
    }

    func confirmMotion(nightKey: String) {
        SleepRepository.shared.confirmMotion(nightKey: nightKey)
        refresh()
    }

    func clearAll() {
        SleepRepository.shared.clearAll()
        refresh()
    }

    func saveSettings(_ newSettings: SleepSettings) {
        settings = newSettings
        SleepRepository.shared.saveSettings(newSettings)
    }

    // MARK: - 刷新

    func refresh() {
        let snapshot = SleepRepository.shared.snapshot()
        isApplyingSnapshot = true
        records = snapshot.records
        events = snapshot.events
        motionState = snapshot.motion
        settings = snapshot.settings
        isApplyingSnapshot = false
        motionAvailable = MotionSleepDetector.shared.isAvailable
        motionAuthorizationLabel = MotionSleepDetector.shared.authorizationLabel
        lastRefreshAt = Date()
    }

    // MARK: - 排程与推测

    func refreshSchedules() async {
        let status = await ReminderScheduler.shared.authorizationStatus()
        let reminderCount = await ReminderScheduler.shared.reschedule(settings: settings)
        let alarmResult = await WakeAlarmScheduler.shared.reschedule(settings: settings)

        notificationDenied = (status == .denied)
        scheduledReminderCount = reminderCount
        wakeAlarmMode = alarmResult.mode
        wakeAlarmDetail = alarmResult.detail
    }

    func runMotionDetection(force: Bool) async {
        guard settings.motionInferenceEnabled else { return }
        _ = await MotionSleepDetector.shared.detectRecent(
            repository: SleepRepository.shared,
            settings: settings,
            force: force
        )
        refresh()
    }
}
