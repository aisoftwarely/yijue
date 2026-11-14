import Foundation

/// 睡眠专注时间 vs 手机静止时段：把两套信号对齐，冲突时给出建议。
enum SleepReconciler {
    /// 两端差异超过 40 分钟才算冲突。
    static let threshold: TimeInterval = 40 * 60
    /// 起床时间最多向后放宽 3 小时，避免手机整夜放在家里导致误延。
    static let maxWakeExtension: TimeInterval = 3 * 3600
    static let maxDuration: TimeInterval = 14 * 3600

    static func suggestion(
        for record: SleepRecord,
        candidate: MotionCandidateSnapshot?
    ) -> SleepReconcileSuggestion? {
        guard record.isEditableByAutomation,
              let candidate,
              candidate.confidence != .low,
              candidate.duration >= 3 * 3600
        else { return nil }

        var suggestion = SleepReconcileSuggestion(
            nightKey: record.nightKey,
            bed: nil,
            wake: nil,
            confidence: candidate.confidence
        )

        // 开睡眠模式后还玩了很久手机：入睡时间应推迟到手机静止的那一刻。
        if let bed = record.bedTime,
           record.bedSource?.isFromMotion != true,
           candidate.start.timeIntervalSince(bed) >= threshold,
           candidate.start < (record.wakeTime ?? .distantFuture) {
            suggestion.bed = candidate.start
        }

        // 关了睡眠模式继续赖床：手机一直静止，起床时间应顺延。
        if let wake = record.wakeTime,
           record.wakeSource?.isFromMotion != true,
           candidate.end.timeIntervalSince(wake) >= threshold,
           candidate.end.timeIntervalSince(wake) <= maxWakeExtension,
           candidate.end.timeIntervalSince(record.bedTime ?? candidate.start) <= maxDuration {
            suggestion.wake = candidate.end
        }

        return suggestion.isEmpty ? nil : suggestion
    }
}
