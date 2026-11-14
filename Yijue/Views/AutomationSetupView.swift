import SwiftUI

struct AutomationSetupView: View {
    @EnvironmentObject private var store: SleepStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("当前状态") {
                    LabeledContent("快捷指令", value: shortcutStatus)
                    LabeledContent("最近事件", value: lastEventText)
                    LabeledContent("静止推测", value: motionStatus)
                    LabeledContent("起床闹钟", value: store.wakeAlarmMode.label)
                }

                Section {
                    stepRow("1", "打开「快捷指令」，底部点「自动化」，右上角点「+」")
                    stepRow("2", "触发器选「睡眠专注」→「已开启」→ 选「立即运行」")
                    stepRow("3", "添加操作，搜索「一觉」，选「记录入睡」，点完成")
                    stepRow("4", "再建一个：睡眠专注「已关闭」→「记录起床」")
                    stepRow("5", "回到这里，点下面的「我已完成设置」")
                } header: {
                    Text("一次性设置（约 3 分钟）")
                } footer: {
                    Text("iOS 不允许 App 读取自动化列表，所以只能根据有没有收到事件判断是否生效。")
                }

                Section {
                    Button {
                        if let url = URL(string: "shortcuts://") {
                            openURL(url)
                        }
                    } label: {
                        Label("打开快捷指令", systemImage: "arrow.up.forward.app")
                    }

                    Button(store.settings.setupAcknowledged ? "已完成设置 ✓" : "我已完成设置") {
                        store.settings.setupAcknowledged = true
                    }
                }

                Section("搜不到「一觉」的动作？") {
                    Text("1. 先完整打开一次本 App，再重启手机；\n2. 还不行就删除 App 重装，或切换一次系统语言；\n3. 也可以先用「打开 URL」兜底：yijue://event?kind=bedtime 和 yijue://event?kind=wake。")
                        .font(.footnote)
                }

                Section("静止推测怎么工作") {
                    Text("App 读取手机最近 7 天的运动历史，把夜里长时间静止的时段推测为睡眠，并和睡眠专注时间对账：开专注后还玩手机、关专注后继续赖床，首页会提示按手机时间更正。手机放得远、戴表睡觉时可能不准；推测出来的记录可以在首页确认或修正。")
                        .font(.footnote)
                }
            }
            .navigationTitle("自动记录")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var shortcutStatus: String {
        if store.hasShortcutEvent { return "已生效" }
        return store.settings.setupAcknowledged ? "等待第一次事件" : "未设置"
    }

    private var lastEventText: String {
        guard let date = store.lastShortcutEventAt else { return "—" }
        return SleepCalendar.clockText(for: date)
    }

    private var motionStatus: String {
        guard store.settings.motionInferenceEnabled else { return "已关闭" }
        guard store.motionAvailable else { return "不可用" }
        return store.motionAuthorizationLabel
    }

    private func stepRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    AutomationSetupView()
        .environmentObject(SleepStore.shared)
}
