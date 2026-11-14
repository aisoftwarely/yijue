import Foundation

enum SleepEventKind: String, Codable {
    case bedtime
    case wake
}

enum SleepSource: String, Codable {
    case motion
    case shortcut
    case manual

    var priority: Int {
        switch self {
        case .motion: return 0
        case .shortcut: return 1
        case .manual: return 2
        }
    }

    var label: String {
        switch self {
        case .motion: return "静止推测"
        case .shortcut: return "睡眠专注"
        case .manual: return "手动"
        }
    }
}

enum SleepConfidence: String, Codable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

struct SleepEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: SleepEventKind
    var at: Date
    var source: SleepSource
}

struct SleepRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var nightKey: String
    var bedTime: Date?
    var wakeTime: Date?
    var bedSource: SleepSource?
    var wakeSource: SleepSource?
    var confidence: SleepConfidence?
    var reviewed: Bool?
    var userEdited: Bool?
    var createdAt: Date = Date()
    var updatedAt: Date?

    init(nightKey: String) {
        self.nightKey = nightKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, nightKey, bedTime, wakeTime, bedSource, wakeSource
        case confidence, reviewed, userEdited, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        nightKey = (try? c.decode(String.self, forKey: .nightKey)) ?? ""
        bedTime = try? c.decodeIfPresent(Date.self, forKey: .bedTime)
        wakeTime = try? c.decodeIfPresent(Date.self, forKey: .wakeTime)
        bedSource = try? c.decodeIfPresent(SleepSource.self, forKey: .bedSource)
        wakeSource = try? c.decodeIfPresent(SleepSource.self, forKey: .wakeSource)
        confidence = try? c.decodeIfPresent(SleepConfidence.self, forKey: .confidence)
        reviewed = try? c.decodeIfPresent(Bool.self, forKey: .reviewed)
        userEdited = try? c.decodeIfPresent(Bool.self, forKey: .userEdited)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    var isComplete: Bool {
        guard let bed = bedTime, let wake = wakeTime else { return false }
        return wake > bed
    }

    var duration: TimeInterval? {
        guard let bed = bedTime, let wake = wakeTime, wake > bed else { return nil }
        return wake.timeIntervalSince(bed)
    }

    var isEditableByAutomation: Bool {
        userEdited != true && reviewed != true
    }

    var originLabel: String {
        let sources = [bedSource, wakeSource].compactMap { $0 }
        guard let first = sources.first else { return "未知" }
        if sources.allSatisfy({ $0 == first }) {
            return first == .motion ? "自动 · 静止推测" : first.label
        }
        return "混合来源"
    }

    var confidenceLabel: String? {
        guard let confidence, bedSource == .motion || wakeSource == .motion else { return nil }
        return "置信度\(confidence.label)"
    }
}

struct MotionCandidateSnapshot: Codable, Equatable {
    var start: Date
    var end: Date
    var confidence: SleepConfidence
    var quietRatio: Double
    var gapRatio: Double
    var stationaryRatio: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct MotionDecision: Codable, Equatable {
    var fingerprint: String
    var candidate: MotionCandidateSnapshot?
    var decidedAt: Date

    init(fingerprint: String, candidate: MotionCandidateSnapshot?, decidedAt: Date = Date()) {
        self.fingerprint = fingerprint
        self.candidate = candidate
        self.decidedAt = decidedAt
    }

    private enum CodingKeys: String, CodingKey {
        case fingerprint, candidate, decidedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fingerprint = (try? c.decode(String.self, forKey: .fingerprint)) ?? ""
        candidate = try? c.decodeIfPresent(MotionCandidateSnapshot.self, forKey: .candidate)
        decidedAt = (try? c.decode(Date.self, forKey: .decidedAt)) ?? Date()
    }
}

struct MotionState: Codable {
    var lastQueryAt: Date?
    var decisions: [String: MotionDecision] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case lastQueryAt, decisions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastQueryAt = try? c.decodeIfPresent(Date.self, forKey: .lastQueryAt)
        decisions = (try? c.decode([String: MotionDecision].self, forKey: .decisions)) ?? [:]
    }
}

struct SleepPersisted: Codable {
    var version: Int = 1
    var records: [SleepRecord] = []
    var events: [SleepEvent] = []
    var settings: SleepSettings = SleepSettings()
    var motion: MotionState = MotionState()
    var ignoredNightKeys: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, records, events, settings, motion, ignoredNightKeys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        records = (try? c.decode([SleepRecord].self, forKey: .records)) ?? []
        events = (try? c.decode([SleepEvent].self, forKey: .events)) ?? []
        settings = (try? c.decode(SleepSettings.self, forKey: .settings)) ?? SleepSettings()
        motion = (try? c.decode(MotionState.self, forKey: .motion)) ?? MotionState()
        ignoredNightKeys = (try? c.decode([String].self, forKey: .ignoredNightKeys)) ?? []
    }
}
