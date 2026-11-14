import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: SleepStore

    @State private var showEditor = false
    @State private var editorRecord: SleepRecord?
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    lastNightCard
                    actionRow
                    statusCard
                    weekCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("一觉")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRecord = nil
                        showEditor = true
                    } label: {
                        Label("补记一晚", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                RecordEditorView(record: editorRecord)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSetup) {
                AutomationSetupView()
                    .environmentObject(store)
            }
            .task {
                await store.refreshSchedules()
            }
        }
    }

    // MARK: - 最近一晚

    @ViewBuilder
    private var lastNightCard: some View {
        if let record = store.lastNightRecord {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(SleepCalendar.dayTitle(forKey: record.nightKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(record.originLabel)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.13), in: Capsule())
                    }

                    if record.isComplete, let bed = record.bedTime, let wake = record.wakeTime, let duration = record.duration {
                        Text(SleepCalendar.durationText(duration))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.primary)

                        HStack(spacing: 8) {
                            Label(SleepCalendar.clockText(for: bed), systemImage: "moon.fill")
                            Image(systemName: "arrow.right")
                                .font(.caption)
                            Label(SleepCalendar.clockText(for: wake), systemImage: "sunrise.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            if let confidence = record.confidenceLabel {
                                Text(confidence)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if store.meetsGoal(record) {
                                Label("达标", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            if record.bedSource?.isFromMotion == true || record.wakeSource?.isFromMotion == true {
                                if record.reviewed != true {
                                    Button("确认") {
                                        store.confirmMotion(nightKey: record.nightKey)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                            }
                            Button("修正") {
                                editorRecord = record
                                showEditor = true
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }

                        if let suggestion = store.suggestion(for: record) {
                            reconcileBanner(suggestion)
                        }
                    } else {
                        draftContent(record)
                    }
                }
            }
        } else {
            card {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                    Text("还没有睡眠记录")
                        .font(.headline)
                    Text("设置快捷指令自动化后，睡眠专注开、关时会自动记录。也可以先手动补记一晚。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        editorRecord = nil
                        showEditor = true
                    } label: {
                        Label("补记一晚", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func draftContent(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let bed = record.bedTime, record.wakeTime == nil {
                Text("\(SleepCalendar.clockText(for: bed)) 已记录入睡")
                    .font(.title2.weight(.semibold))
                Text("等起床记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        _ = store.recordEvent(kind: .wake, source: .manual)
                    } label: {
                        Label("我现在醒了", systemImage: "sunrise.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("补记起床时间") {
                        editorRecord = record
                        showEditor = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if let wake = record.wakeTime, record.bedTime == nil {
                Text("\(SleepCalendar.clockText(for: wake)) 已记录起床")
                    .font(.title2.weight(.semibold))
                Text("缺少入睡时间，补一下昨晚是几点睡的")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("补记入睡时间") {
                    editorRecord = record
                    showEditor = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("记录不完整")
                    .font(.headline)
                Button("补记") {
                    editorRecord = record
                    showEditor = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - 对账提示

    private func reconcileBanner(_ suggestion: SleepReconcileSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("和手机静止时间对不上", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            if let bed = suggestion.bed {
                Text("开着睡眠模式但还在玩手机：手机到 \(SleepCalendar.clockText(for: bed)) 才静止不动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let wake = suggestion.wake {
                Text("睡眠模式关掉后还在睡：手机到 \(SleepCalendar.clockText(for: wake)) 才恢复活动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                store.applySuggestion(suggestion)
            } label: {
                Label("按手机时间更正", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color.orange.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    // MARK: - 手动记录

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                _ = store.recordEvent(kind: .bedtime, source: .manual)
            } label: {
                Label("记录入睡", systemImage: "moon.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                _ = store.recordEvent(kind: .wake, source: .manual)
            } label: {
                Label("记录起床", systemImage: "sunrise.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - 自动记录状态

    private var statusCard: some View {
        Button {
            showSetup = true
        } label: {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("自动记录")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    statusLine(icon: "bolt.badge.clock", title: "快捷指令", value: shortcutStatus)
                    statusLine(icon: "figure.walk.motion", title: "静止推测", value: motionStatus)
                    statusLine(icon: "alarm", title: "起床闹钟", value: alarmStatus)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var shortcutStatus: String {
        if let date = store.lastShortcutEventAt {
            return "已生效 · 最近 \(SleepCalendar.clockText(for: date))"
        }
        return store.settings.setupAcknowledged ? "没收到事件，检查自动化" : "未设置"
    }

    private var motionStatus: String {
        guard store.settings.motionInferenceEnabled else { return "已关闭" }
        guard store.motionAvailable else { return "不可用" }
        return store.motionAuthorizationLabel
    }

    private var alarmStatus: String {
        store.wakeAlarmMode.label
    }

    private func statusLine(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.footnote)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 最近 7 晚

    private var weekCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近 7 晚")
                    .font(.subheadline.weight(.semibold))

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weekPoints) { point in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(barColor(for: point))
                                .frame(height: barHeight(for: point))
                            Text(SleepCalendar.weekdayLabel(forKey: point.key))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84, alignment: .bottom)
            }
        }
    }

    private var weekPoints: [NightPoint] {
        SleepStatistics.points(records: store.records, period: .week)
    }

    private var maxWeekDuration: TimeInterval {
        max(1, weekPoints.compactMap(\.duration).max() ?? 1)
    }

    private func barHeight(for point: NightPoint) -> CGFloat {
        guard let duration = point.duration else { return 5 }
        let ratio = min(1, duration / maxWeekDuration)
        return max(6, 58 * ratio)
    }

    private func barColor(for point: NightPoint) -> Color {
        guard let record = point.record else { return Color(.systemFill) }
        return store.meetsGoal(record) ? Color.accentColor : Color.accentColor.opacity(0.3)
    }

    // MARK: - 卡片样式

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

#Preview {
    HomeView()
        .environmentObject(SleepStore.shared)
}
