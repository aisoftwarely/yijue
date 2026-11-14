import SwiftUI

struct RecordEditorView: View {
    @EnvironmentObject private var store: SleepStore
    @Environment(\.dismiss) private var dismiss

    let record: SleepRecord?

    @State private var bed: Date
    @State private var wake: Date
    @State private var showDeleteConfirm = false

    init(record: SleepRecord?) {
        self.record = record

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
                } header: {
                    Text("时间")
                } footer: {
                    if let message = validationMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else if let duration = validDuration {
                        Text("这一晚：\(SleepCalendar.durationText(duration))")
                    } else {
                        Text("起床时间要晚于入睡时间，时长在 1–16 小时之间。")
                    }
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
            .navigationTitle(record == nil ? "补记一晚" : "修正记录")
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
        }
    }

    private var validDuration: TimeInterval? {
        guard wake > bed else { return nil }
        let duration = wake.timeIntervalSince(bed)
        guard duration >= 3600, duration <= 16 * 3600 else { return nil }
        return duration
    }

    private var validationMessage: String? {
        guard wake > bed else { return "起床时间要晚于入睡时间。" }
        let duration = wake.timeIntervalSince(bed)
        if duration < 3600 { return "时长太短，至少要 1 小时。" }
        if duration > 16 * 3600 { return "时长太长，最多 16 小时。" }
        return nil
    }

    private func save() {
        guard validDuration != nil else { return }
        store.saveManual(bed: bed, wake: wake, nightKey: record?.nightKey)
        dismiss()
    }
}

#Preview {
    RecordEditorView(record: nil)
        .environmentObject(SleepStore.shared)
}
