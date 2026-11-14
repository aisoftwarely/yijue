import CoreMotion
import CryptoKit
import Foundation

struct MotionSample {
    let date: Date
    let stationary: Bool
    let unknown: Bool
    let confidence: SleepConfidence
}

struct MotionCandidate {
    let start: Date
    let end: Date
    let confidence: SleepConfidence
    let quietRatio: Double
    let gapRatio: Double
    let stationaryRatio: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

private struct MotionInterval {
    let start: Date
    let end: Date
    let isQuiet: Bool
    let isAnchored: Bool
    let isUnknown: Bool
    let confidence: SleepConfidence

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

final class MotionSleepDetector {
    static let shared = MotionSleepDetector()

    private let manager = CMMotionActivityManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    var authorizationStatus: CMAuthorizationStatus {
        CMMotionActivityManager.authorizationStatus()
    }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未询问"
        @unknown default: return "未知"
        }
    }

    /// 查询最近 7 天并补写推测记录。返回写入的夜数。
    @discardableResult
    func detectRecent(
        repository: SleepRepository,
        settings: SleepSettings,
        force: Bool,
        now: Date = Date()
    ) async -> Int {
        guard settings.motionInferenceEnabled, isAvailable else { return 0 }

        let snapshot = repository.snapshot()
        if !force,
           let last = snapshot.motion.lastQueryAt,
           now.timeIntervalSince(last) < 6 * 3600 {
            return 0
        }

        let start = now.addingTimeInterval(-7 * 24 * 3600)
        guard let samples = try? await fetchSamples(from: start, to: now), !samples.isEmpty else {
            return 0
        }
        repository.noteMotionQuery(at: now)

        var written = 0
        let calendar = Calendar.current

        // 最近 7 个「傍晚日期」；今天这一夜窗口还没结束，会被跳过。
        for offset in stride(from: 7, through: 0, by: -1) {
            guard let evening = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = SleepCalendar.keyFormatter.string(from: evening)
            guard
                let window = SleepCalendar.window(
                    forKey: key,
                    startMinutes: settings.nightWindowStartMinutes,
                    endMinutes: settings.nightWindowEndMinutes,
                    calendar: calendar
                ),
                window.end <= now
            else { continue }

            let windowSamples = samples.filter {
                $0.date >= window.start.addingTimeInterval(-3600)
                    && $0.date <= window.end.addingTimeInterval(60)
            }
            guard !windowSamples.isEmpty else { continue }

            let fingerprint = Self.fingerprint(windowSamples)
            if let decision = repository.motionDecision(forKey: key), decision.fingerprint == fingerprint {
                continue
            }

            let candidate = Self.bestCandidate(
                samples: windowSamples,
                window: window,
                minDuration: TimeInterval(settings.minInferredMinutes * 60)
            )

            repository.setMotionDecision(
                MotionDecision(fingerprint: fingerprint, candidate: candidate.map(Self.snapshot)),
                forKey: key
            )

            guard let candidate else { continue }

            let allowUpdate = offset <= 2
            if repository.applyMotionCandidate(
                Self.snapshot(candidate),
                forKey: key,
                now: now,
                allowUpdate: allowUpdate
            ) {
                written += 1
            }
        }

        return written
    }

    // MARK: - CoreMotion 查询

    private func fetchSamples(from: Date, to: Date) async throws -> [MotionSample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[MotionSample], Error>) in
            manager.queryActivityStarting(from: from, to: to, to: queue) { activities, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (activities ?? [])
                    .map { activity in
                        MotionSample(
                            date: activity.startDate,
                            stationary: activity.stationary,
                            unknown: activity.unknown,
                            confidence: Self.confidence(activity.confidence)
                        )
                    }
                    .sorted { $0.date < $1.date }
                continuation.resume(returning: samples)
            }
        }
    }

    private static func confidence(_ value: CMMotionActivityConfidence) -> SleepConfidence {
        switch value {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        @unknown default: return .low
        }
    }

    // MARK: - 纯算法

    static func bestCandidate(
        samples: [MotionSample],
        window: DateInterval,
        minDuration: TimeInterval
    ) -> MotionCandidate? {
        guard !samples.isEmpty else { return nil }

        var intervals: [MotionInterval] = []
        for (index, sample) in samples.enumerated() {
            let rawEnd: Date
            if index + 1 < samples.count {
                rawEnd = samples[index + 1].date
            } else {
                rawEnd = sample.date.addingTimeInterval(5 * 60)
            }
            let start = max(sample.date, window.start)
            let end = min(rawEnd, window.end)
            guard end > start else { continue }
            intervals.append(
                MotionInterval(
                    start: start,
                    end: end,
                    isQuiet: sample.stationary || sample.unknown,
                    isAnchored: sample.stationary,
                    isUnknown: sample.unknown,
                    confidence: sample.confidence
                )
            )
        }
        guard !intervals.isEmpty else { return nil }

        // 合并被 ≤10 分钟活动打断的安静段
        var blocks: [(start: Date, end: Date, items: [MotionInterval])] = []
        for interval in intervals where interval.isQuiet {
            if var last = blocks.last,
               interval.start.timeIntervalSince(last.end) <= 10 * 60 {
                last.end = max(last.end, interval.end)
                last.items.append(interval)
                blocks[blocks.count - 1] = last
            } else {
                blocks.append((interval.start, interval.end, [interval]))
            }
        }
        guard !blocks.isEmpty else { return nil }

        var candidates: [MotionCandidate] = []

        for block in blocks {
            let anchored = block.items.filter(\.isAnchored)
            guard !anchored.isEmpty,
                  let firstAnchor = anchored.min(by: { $0.start < $1.start }),
                  let lastAnchor = anchored.max(by: { $0.end < $1.end }),
                  anchored.contains(where: { $0.duration >= 20 * 60 })
            else { continue }

            let start = max(firstAnchor.start, window.start)
            let end = min(lastAnchor.end.addingTimeInterval(5 * 60), window.end)
            let duration = end.timeIntervalSince(start)
            guard duration >= minDuration, duration <= 14 * 3600 else { continue }

            let overlapping = intervals.filter { $0.end > start && $0.start < end }
            var quietSeconds = 0.0
            var activeSeconds = 0.0
            var anchoredSeconds = 0.0
            var unknownSeconds = 0.0
            var anchoredWeight = 0.0
            var confidentWeight = 0.0

            for interval in overlapping {
                let s = max(interval.start, start)
                let e = min(interval.end, end)
                let seconds = max(0, e.timeIntervalSince(s))
                if interval.isQuiet {
                    quietSeconds += seconds
                } else {
                    activeSeconds += seconds
                }
                if interval.isAnchored {
                    anchoredSeconds += seconds
                    anchoredWeight += seconds
                    if interval.confidence != .low {
                        confidentWeight += seconds
                    }
                }
                if interval.isUnknown {
                    unknownSeconds += seconds
                }
            }

            let total = max(duration, 1)
            let quietRatio = quietSeconds / total
            let gapRatio = activeSeconds / total
            let stationaryRatio = anchoredSeconds / total
            let unknownRatio = unknownSeconds / total
            let confidentRatio = anchoredWeight > 0 ? confidentWeight / anchoredWeight : 0

            var score = 0
            if duration >= 4 * 3600 { score += 1 }
            if stationaryRatio >= 0.5 { score += 1 }
            if gapRatio <= 0.15 { score += 1 }
            if unknownRatio <= 0.3 { score += 1 }
            if confidentRatio >= 0.6 { score += 1 }

            let confidence: SleepConfidence = score >= 4 ? .high : (score >= 2 ? .medium : .low)
            candidates.append(
                MotionCandidate(
                    start: start,
                    end: end,
                    confidence: confidence,
                    quietRatio: quietRatio,
                    gapRatio: gapRatio,
                    stationaryRatio: stationaryRatio
                )
            )
        }

        return candidates.max { $0.duration < $1.duration }
    }

    static func fingerprint(_ samples: [MotionSample]) -> String {
        let joined = samples.map { sample in
            "\(Int(sample.date.timeIntervalSince1970))|\(sample.stationary ? 1 : 0)|\(sample.unknown ? 1 : 0)|\(sample.confidence.rawValue)"
        }.joined(separator: ";")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func snapshot(_ candidate: MotionCandidate) -> MotionCandidateSnapshot {
        MotionCandidateSnapshot(
            start: candidate.start,
            end: candidate.end,
            confidence: candidate.confidence,
            quietRatio: candidate.quietRatio,
            gapRatio: candidate.gapRatio,
            stationaryRatio: candidate.stationaryRatio
        )
    }
}
