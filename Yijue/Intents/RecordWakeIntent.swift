import AppIntents
import Foundation

struct RecordWakeIntent: AppIntent {
    static var title: LocalizedStringResource { "记录起床" }

    func perform() async throws -> some IntentResult {
        SleepRepository.shared.recordEvent(kind: .wake, at: Date(), source: .shortcut)

        // 起床时顺便对账：手机静止到几点、是不是关了专注还在睡
        let snapshot = SleepRepository.shared.snapshot()
        if snapshot.settings.motionInferenceEnabled {
            _ = await MotionSleepDetector.shared.detectRecent(
                repository: SleepRepository.shared,
                settings: snapshot.settings,
                force: false,
                includeOpenLastNight: true
            )
        }

        // 起床 30 分钟后推送昨晚睡了多久
        let updated = SleepRepository.shared.snapshot()
        await MorningSummaryScheduler.shared.reschedule(
            settings: updated.settings,
            records: updated.records
        )
        return .result()
    }
}
