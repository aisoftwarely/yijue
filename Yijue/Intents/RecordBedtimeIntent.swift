import AppIntents
import Foundation

struct RecordBedtimeIntent: AppIntent {
    static var title: LocalizedStringResource { "记录入睡" }

    func perform() async throws -> some IntentResult {
        SleepRepository.shared.recordEvent(kind: .bedtime, at: Date(), source: .shortcut)
        return .result()
    }
}
