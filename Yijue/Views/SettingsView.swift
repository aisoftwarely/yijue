import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: SleepStore

    @State private var showClearConfirm = false
    @State private var testResult = ""
    @State private var isDetecting = false
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                goalSection
                reminderSection
                alarmSection
                automationSection
                motionSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .task {
                await store.refreshSchedules()
            }
            .onChange(of: store.settings) { _, _ in
                Task { await store.refreshSchedules() }
            }
            .onChange(of: store.settings.bedtimeReminderEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    _ = await ReminderScheduler.shared.requestAuthorization()
                    await store.refreshSchedules()
                }
            }
            .onChange(of: store.settings.wakeAlarmEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    _ = await ReminderScheduler.shared.requestAuthorization()
                    await store.refreshSchedules()
                }
            }
            .alert("清除所有记录？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    store.clearAll()
                }
            } message: {
                Text("所有睡眠记录和设置都会被删除，无法恢复。")
            }
        }
    }

    // MARK: - 目标

    private var goalSection: some View {
        Section {
            Stepper(value: $store.settings.goalMinutes, in: 300...600, step: 15) {
                Text("每晚目标：\(goalText)")
            }
        } header: {
            Text("睡眠目标")
        } footer: {
            Text("统计里的达标天数和连续达标按这个目标计算。")
        }
    }

    // MARK: - 睡前提醒

    private var reminderSection: some View {
        Section {
            Toggle("睡前提醒", isOn: $store.settings.bedtimeReminderEnabled)

            if store.settings.bedtimeReminderEnabled {
                DatePicker(
                    "提醒时间",
                    selection: timeBinding(\.bedtimeReminderMinutes),
                    displayedComponents: .hourAndMinute
                )
            }

            if store.notificationDenied {
                Button("打开系统设置") { openSystemSettings() }
            }
        } header: {
            Text("睡前提醒")
        } footer: {
            if store.notificationDenied {
                Text("通知权限未开启，提醒不会送达。请到「设置 > 通知 > 一觉」中允许。")
            } else if store.settings.bedtimeReminderEnabled {
                Text("每天 \(reminderTimeText) 提醒一次。建议放在睡眠专注开始之前，避免被专注模式静音。")
            }
        }
    }

    // MARK: - 起床闹钟

    private var alarmSection: some View {
        Section {
            Toggle("起床闹钟", isOn: $store.settings.wakeAlarmEnabled)

            if store.settings.wakeAlarmEnabled {
                DatePicker(
                    "起床时间",
                    selection: timeBinding(\.wakeAlarmMinutes),
                    displayedComponents: .hourAndMinute
                )

                Picker("重复", selection: repeatModeBinding) {
                    Text(WakeAlarmRepeatMode.everyday.title).tag(WakeAlarmRepeatMode.everyday)
                    Text(WakeAlarmRepeatMode.weekdays.title).tag(WakeAlarmRepeatMode.weekdays)
                    Text(WakeAlarmRepeatMode.weekends.title).tag(WakeAlarmRepeatMode.weekends)
                }
            }

            LabeledContent("当前方式", value: store.wakeAlarmMode.label)

            Button {
                Task {
                    isTesting = true
                    let result = await WakeAlarmScheduler.shared.scheduleTest(settings: store.settings)
                    testResult = "\(result.mode.label)：\(result.detail)"
                    isTesting = false
                }
            } label: {
                Text(isTesting ? "正在排程…" : "2 分钟后测试")
            }
            .disabled(isTesting)

            if !testResult.isEmpty {
                Text(testResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("起床闹钟")
        } footer: {
            Text(store.wakeAlarmDetail.isEmpty ? WakeAlarmMode.alarmKit.detail : store.wakeAlarmDetail)
        }
    }

    // MARK: - 自动记录

    private var automationSection: some View {
        Section {
            NavigationLink {
                AutomationSetupView()
                    .environmentObject(store)
            } label: {
                LabeledContent("快捷指令自动化", value: automationStatus)
            }
        } header: {
            Text("自动记录")
        } footer: {
            Text("睡眠专注打开、关闭时，快捷指令会自动调用「一觉」记录时间。")
        }
    }

    // MARK: - 静止推测

    private var motionSection: some View {
        Section {
            Toggle("静止推测（兜底）", isOn: $store.settings.motionInferenceEnabled)
            LabeledContent("运动与健身权限", value: store.motionAuthorizationLabel)

            Button {
                Task {
                    isDetecting = true
                    await store.runMotionDetection(force: true)
                    isDetecting = false
                }
            } label: {
                Text(isDetecting ? "正在检测…" : "重新检测最近 7 天")
            }
            .disabled(isDetecting || !store.settings.motionInferenceEnabled)
        } header: {
            Text("静止推测")
        } footer: {
            Text("手机放在床边、夜里长时间没动，才会被推测为睡眠。Apple 只保留最近 7 天的运动历史；推测结果可以在首页确认或修正。")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            if let text = exportText {
                ShareLink(item: text) {
                    Label("导出数据（JSON）", systemImage: "square.and.arrow.up")
                }
            }

            Button("清除所有记录", role: .destructive) {
                showClearConfirm = true
            }
        } header: {
            Text("数据")
        } footer: {
            Text("导出后可以存到「文件」或发给自己，作为重装前的备份。")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: versionText)
            Text("一觉 · 自用版，不上架 App Store。数据只存在本机；免费证书 7 天有效，Mac 与手机同 Wi-Fi 时会自动续签，到期重装记录也不会丢。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 辅助

    private var goalText: String {
        let minutes = store.settings.goalMinutes
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
    }

    private var reminderTimeText: String {
        SleepCalendar.clockText(minutes: store.settings.bedtimeReminderMinutes)
    }

    private var automationStatus: String {
        if store.hasShortcutEvent { return "已生效" }
        return store.settings.setupAcknowledged ? "等待第一次事件" : "未设置"
    }

    private var exportText: String? {
        guard let data = SleepRepository.shared.exportData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var repeatModeBinding: Binding<WakeAlarmRepeatMode> {
        Binding(
            get: {
                let mode = store.settings.wakeAlarmMode
                return mode == .custom ? .everyday : mode
            },
            set: { store.settings.wakeAlarmMode = $0 }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<SleepSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = store.settings[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.settings[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SleepStore.shared)
}
