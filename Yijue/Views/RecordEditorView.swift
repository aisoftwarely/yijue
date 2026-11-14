import SwiftUI

struct RecordEditorView: View {
    @EnvironmentObject private var store: SleepStore
    @Environment(\.dismiss) private var dismiss

    let record: SleepRecord?
    private let originalBed: Date?
    private let originalWake: Date?

    @State private var bed: Date
    @State private var wake: Date
    @State private var adjustBothEnds = false
    @State private var showDeleteConfirm = false
    @State private var hapticTick = 0

    init(record: SleepRecord?) {
        self.record = record
        self.originalBed = record?.bedTime
        self.originalWake = record?.wakeTime

        let calendar = Calendar.current
        let now = Date()
        let defaultWake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        let defaultBed = calendar.date(byAdding: .minute, value: -450, to: defaultWake)
            ?? defaultWake.addingTimeInterval(-450 * 60)

        let initialBed = record?.bedTime
            ?? record?.wakeTime.flatMap { calendar.date(byAdding: .minute, value: -450, to: $0) }
            ?? defaultBed
        let initialWake = record?.wakeTime
            ?? record?.bedTime.flatMap { calendar.date(byAdding: .minute, value: 450, to: $0) }
            ?? defaultWake

        _bed = State(initialValue: initialBed)
        _wake = State(initialValue: initialWake)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if singleEndMode, let fixedBed = originalBed {
                        LabeledContent("入睡时间", value: fixedEndText(fixedBed))
                        DatePicker(
                            "起床时间",
                            selection: $wake,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else if singleEndMode, let fixedWake = originalWake {
                        DatePicker(
                            "入睡时间",
                            selection: $bed,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        LabeledContent("起床时间", value: fixedEndText(fixedWake))
                    } else {
                        DatePicker(
                            "入睡时间",
                            selection: $bed,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        DatePicker(
                            "起床时间",
                            selection: $wake,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    if record != nil, record?.isComplete != true {
                        Toggle("同时调整已记录的一端", isOn: $adjustBothEnds)
                    }
                } header: {
                    Text("时间")
                } footer: {
                    footerText
                }

                if record != nil {
                    Section {
                        Button("删除这一晚的记录", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } footer: {
                        Text("删除后静止推测不会再把这一晚加回来；手动补记可以重新创建。")
                    }
                }
            }
            .navigationTitle(editorTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(validDuration == nil)
                }
            }
            .alert("删除这一晚？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let record {
                        store.delete(nightKey: record.nightKey)
                    }
                    dismiss()
                }
            } message: {
                Text("删除后无法恢复。")
            }
            .sensoryFeedback(.success, trigger: hapticTick)
        }
    }

    // MARK: - 只补一端

    /// 草稿且只缺一端时，默认只编辑缺的那一端。
    private var singleEndMode: Bool {
        adjustBothEnds == false && ((originalBed == nil) != (originalWake == nil))
    }

    private func fixedEndText(_ date: Date) -> String {
        let clock = SleepCalendar.clockText(for: date)
        guard let key = record?.nightKey else { return clock }
        return "\(SleepCalendar.dayLabel(forKey: key)) \(clock)"
    }

    private var effectiveBed: Date {
        singleEndMode ? (originalBed ?? bed) : bed
    }

    private var effectiveWake: Date {
        singleEndMode ? (originalWake ?? wake) : wake
    }

    private var editorTitle: String {
        guard record != nil else { return "补记一晚" }
        if originalBed == nil, originalWake == nil { return "补记一晚" }
        if originalBed != nil, originalWake == nil { return "补记起床" }
        if originalWake != nil, originalBed == nil { return "补记入睡" }
        return "修正记录"
    }

    @ViewBuilder
    private var footerText: some View {
        if let message = validationMessage {
            Text(message)
                .foregroundStyle(.red)
        } else if let duration = validDuration {
            if singleEndMode {
                Text("只补记缺少的一端，已记录的一端不变。这一晚：\(SleepCalendar.durationText(duration))")
            } else {
                Text("这一晚：\(SleepCalendar.durationText(duration))")
            }
        } else {
            Text("起床时间要晚于入睡时间，时长在 1–16 小时之间。")
        }
    }

    private var validDuration: TimeInterval? {
        guard effectiveWake > effectiveBed else { return nil }
        let duration = effectiveWake.timeIntervalSince(effectiveBed)
        guard duration >= 3600, duration <= 16 * 3600 else { return nil }
        return duration
    }

    private var validationMessage: String? {
        guard effectiveWake > effectiveBed else { return "起床时间要晚于入睡时间。" }
        let duration = effectiveWake.timeIntervalSince(effectiveBed)
        if duration < 3600 { return "时长太短，至少要 1 小时。" }
        if duration > 16 * 3600 { return "时长太长，最多 16 小时。" }
        return nil
    }

    private func save() {
        guard validDuration != nil else { return }
        hapticTick += 1

        if singleEndMode, let record {
            if originalBed != nil {
                store.saveManualSingleEnd(nightKey: record.nightKey, bed: nil, wake: wake)
            } else {
                store.saveManualSingleEnd(nightKey: record.nightKey, bed: bed, wake: nil)
            }
        } else {
            store.saveManual(bed: bed, wake: wake, nightKey: record?.nightKey)
        }
        dismiss()
    }
}

#Preview {
    RecordEditorView(record: nil)
        .environmentObject(SleepStore.shared)
}