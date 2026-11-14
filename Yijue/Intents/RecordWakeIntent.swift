import AppIntents
import Foundation

struct RecordWakeIntent: AppIntent {
    static var title: LocalizedStringResource { "记录起床" }

    func perform() async throws -> some IntentResult {
        SleepRepository.shared.recordEvent(kind: .wake, at: Date(), source: .shortcut)
        return .result()
    }
}
