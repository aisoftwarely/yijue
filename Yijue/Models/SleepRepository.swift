import Foundation

extension Notification.Name {
    static let sleepStoreDidChange = Notification.Name("sleepStoreDidChange")
}

/// 数据唯一入口：App Intent、URL scheme、界面都只通过它读写。
final class SleepRepository: @unchecked Sendable {
    static let shared = SleepRepository()

    private let defaults: UserDefaults
    private let storeKey = "sleep.store.v1"
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 读取

    func snapshot() -> SleepPersisted {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    func exportData() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        let state = loadUnlocked()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(state)
    }

    // MARK: - 快捷指令 / 手动事件

    /// 写入一个时间点事件。返回是否真的产生了变化。
    @discardableResult
    func recordEvent(kind: SleepEventKind, at date: Date, source: SleepSource) -> Bool {
        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()

        // 10 分钟内的同类事件视为重复（自动化重复运行、Intent 与 URL 同时配置）
        if state.events.contains(where: {
            $0.kind == kind && abs($0.at.timeIntervalSince(date)) < 600
        }) {
            return false
        }

        state.events.append(SleepEvent(kind: kind, at: date, source: source))
        if state.events.count > 200 {
            state.events = Array(state.events.suffix(200))
        }

        var key = SleepCalendar.nightKey(for: date)
        if kind == .wake {
            // 中午 12 点后的起床事件，如果前一晚只有入睡草稿，归到那一晚
            let existingForToday = state.records.contains(where: { $0.nightKey == key })
            if !existingForToday {
                let drafts = state.records.filter { record in
                    guard let bed = record.bedTime, record.wakeTime == nil else { return false }
                    let interval = date.timeIntervalSince(bed)
                    return interval > 0 && interval < 18 * 3600
                }
                if let draft = drafts.max(by: { ($0.bedTime ?? .distantPast) < ($1.bedTime ?? .distantPast) }) {
                    key = draft.nightKey
                }
            }
        }

        if let index = state.records.firstIndex(where: { $0.nightKey == key }) {
            var record = state.records[index]
            guard record.userEdited != true else {
                saveUnlocked(state)
                return true
            }

            var changed = false
            switch kind {
            case .bedtime:
                if record.bedTime == nil {
                    record.bedTime = date
                    record.bedSource = source
                    changed = true
                } else if record.bedSource == .motion && source.priority > SleepSource.motion.priority {
                    record.bedTime = date
                    record.bedSource = source
                    changed = true
                }
            case .wake:
                if record.wakeTime == nil {
                    record.wakeTime = date
                    record.wakeSource = source
                    changed = true
                } else if record.wakeSource == .motion && source.priority > SleepSource.motion.priority {
                    record.wakeTime = date
                    record.wakeSource = source
                    changed = true
                }
            }

            if changed {
                record.updatedAt = Date()
                state.records[index] = record
            }
            state.ignoredNightKeys.removeAll { $0 == key }
            saveUnlocked(state)
            return changed
        }

        var record = SleepRecord(nightKey: key)
        switch kind {
        case .bedtime:
            record.bedTime = date
            record.bedSource = source
        case .wake:
            record.wakeTime = date
            record.wakeSource = source
        }
        record.updatedAt = Date()
        state.records.append(record)
        state.ignoredNightKeys.removeAll { $0 == key }
        saveUnlocked(state)
        return true
    }

    // MARK: - 手动编辑

    @discardableResult
    func saveManual(bed: Date, wake: Date, nightKey: String?) -> SleepRecord? {
        guard wake > bed else { return nil }

        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()
        let key = nightKey ?? SleepCalendar.nightKey(for: bed)

        var record: SleepRecord
        if let index = state.records.firstIndex(where: { $0.nightKey == key }) {
            record = state.records[index]
            state.records.remove(at: index)
        } else {
            record = SleepRecord(nightKey: key)
        }

        record.bedTime = bed
        record.wakeTime = wake
        record.bedSource = .manual
        record.wakeSource = .manual
        record.confidence = nil
        record.reviewed = true
        record.userEdited = true
        record.updatedAt = Date()

        state.records.append(record)
        state.ignoredNightKeys.removeAll { $0 == key }
        saveUnlocked(state)
        return record
    }

    /// 只补一端（编辑器里的草稿场景）。
    @discardableResult
    func saveManualSingleEnd(nightKey: String, bed: Date?, wake: Date?) -> SleepRecord? {
        if let bed, let wake, wake <= bed { return nil }
        guard bed != nil || wake != nil else { return nil }

        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()
        var record: SleepRecord
        if let index = state.records.firstIndex(where: { $0.nightKey == nightKey }) {
            record = state.records[index]
            state.records.remove(at: index)
        } else {
            record = SleepRecord(nightKey: nightKey)
        }

        if let bed {
            record.bedTime = bed
            record.bedSource = .manual
        }
        if let wake {
            record.wakeTime = wake
            record.wakeSource = .manual
        }
        record.confidence = nil
        record.reviewed = true
        record.userEdited = true
        record.updatedAt = Date()

        state.records.append(record)
        state.ignoredNightKeys.removeAll { $0 == nightKey }
        saveUnlocked(state)
        return record
    }

    func delete(nightKey: String) {
        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()
        state.records.removeAll { $0.nightKey == nightKey }
        if !state.ignoredNightKeys.contains(nightKey) {
            state.ignoredNightKeys.append(nightKey)
        }
        saveUnlocked(state)
    }

    func confirmMotion(nightKey: String) {
        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()
        guard let index = state.records.firstIndex(where: { $0.nightKey == nightKey }) else { return }
        state.records[index].reviewed = true
        state.records[index].updatedAt = Date()
        saveUnlocked(state)
    }

    // MARK: - 设置

    func saveSettings(_ settings: SleepSettings) {
        lock.lock()
        defer { lock.unlock() }
        var state = loadUnlocked()
        state.settings = settings
        saveUnlocked(state)
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock(); notifyChanged() }
        saveUnlocked(SleepPersisted())
    }

    // MARK: - CoreMotion 推测

    func motionDecision(forKey key: String) -> MotionDecision? {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked().motion.decisions[key]
    }

    func setMotionDecision(_ decision: MotionDecision, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        var state = loadUnlocked()
        state.motion.decisions[key] = decision
        saveUnlocked(state)
    }

    func noteMotionQuery(at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        var state = loadUnlocked()
        state.motion.lastQueryAt = date
        saveUnlocked(state)
    }

    /// 把推测结果合进记录。返回是否写入了数据。
    /// - Parameter allowCorrection: 允许用静止时段纠正睡眠专注记下的时间（窗口未结束的当晚不纠正）。
    @discardableResult
    func applyMotionCandidate(
        _ candidate: MotionCandidateSnapshot,
        forKey key: String,
        now: Date,
        allowUpdate: Bool,
        allowCorrection: Bool = true
    ) -> Bool {
        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()
        guard !state.ignoredNightKeys.contains(key) else { return false }

        if let index = state.records.firstIndex(where: { $0.nightKey == key }) {
            var record = state.records[index]
            guard record.isEditableByAutomation else { return false }

            var changed = false

            if record.bedTime == nil {
                record.bedTime = candidate.start
                record.bedSource = .motion
                changed = true
            } else if record.bedSource?.isFromMotion == true, allowUpdate, let bed = record.bedTime {
                if abs(candidate.start.timeIntervalSince(bed)) >= 15 * 60 {
                    record.bedTime = candidate.start
                    changed = true
                }
            } else if allowCorrection,
                      allowUpdate,
                      candidate.confidence != .low,
                      let bed = record.bedTime,
                      candidate.start.timeIntervalSince(bed) >= SleepReconciler.threshold,
                      candidate.start < (record.wakeTime ?? .distantFuture) {
                // 开了睡眠模式又玩手机：记录时间偏早，以手机静止时刻为准
                record.bedTime = candidate.start
                record.bedSource = .reconciled
                changed = true
            }

            if record.wakeTime == nil {
                record.wakeTime = candidate.end
                record.wakeSource = .motion
                changed = true
            } else if record.wakeSource?.isFromMotion == true, allowUpdate, let wake = record.wakeTime {
                if abs(candidate.end.timeIntervalSince(wake)) >= 15 * 60 {
                    record.wakeTime = candidate.end
                    changed = true
                }
            } else if allowCorrection,
                      allowUpdate,
                      candidate.confidence == .high,
                      let wake = record.wakeTime,
                      candidate.end.timeIntervalSince(wake) >= SleepReconciler.threshold,
                      candidate.end.timeIntervalSince(wake) <= SleepReconciler.maxWakeExtension,
                      candidate.end.timeIntervalSince(record.bedTime ?? candidate.start) <= SleepReconciler.maxDuration {
                // 关了睡眠模式继续赖床：手机一直静止，起床时间顺延
                record.wakeTime = candidate.end
                record.wakeSource = .reconciled
                changed = true
            }

            guard changed else { return false }
            if record.bedSource?.isFromMotion == true && record.wakeSource?.isFromMotion == true {
                record.confidence = candidate.confidence
            }
            record.updatedAt = now
            state.records[index] = record
            saveUnlocked(state)
            return true
        }

        var record = SleepRecord(nightKey: key)
        record.bedTime = candidate.start
        record.wakeTime = candidate.end
        record.bedSource = .motion
        record.wakeSource = .motion
        record.confidence = candidate.confidence
        record.updatedAt = now
        state.records.append(record)
        saveUnlocked(state)
        return true
    }

    /// 用户点「按手机记录更正」：把建议的一端或两端改成静止推测的时间。
    @discardableResult
    func applyReconcileSuggestion(nightKey: String, bed: Date?, wake: Date?) -> Bool {
        guard bed != nil || wake != nil else { return false }

        lock.lock()
        defer { lock.unlock(); notifyChanged() }

        var state = loadUnlocked()
        guard let index = state.records.firstIndex(where: { $0.nightKey == nightKey }) else { return false }
        var record = state.records[index]
        guard record.isEditableByAutomation else { return false }

        if let bed {
            record.bedTime = bed
            record.bedSource = .reconciled
        }
        if let wake {
            record.wakeTime = wake
            record.wakeSource = .reconciled
        }
        if let bed = record.bedTime, let wake = record.wakeTime, wake <= bed {
            return false
        }

        record.confidence = state.motion.decisions[nightKey]?.candidate?.confidence ?? record.confidence
        record.updatedAt = Date()
        state.records[index] = record
        saveUnlocked(state)
        return true
    }

    // MARK: - 底层

    private func loadUnlocked() -> SleepPersisted {
        guard
            let data = defaults.data(forKey: storeKey),
            let payload = try? decoder.decode(SleepPersisted.self, from: data)
        else {
            return SleepPersisted()
        }
        return payload
    }

    private func saveUnlocked(_ state: SleepPersisted) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: storeKey)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .sleepStoreDidChange, object: nil)
    }
}
