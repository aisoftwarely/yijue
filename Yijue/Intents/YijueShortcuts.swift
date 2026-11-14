import AppIntents

struct YijueShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordBedtimeIntent(),
            phrases: ["用\(.applicationName)记录入睡"],
            shortTitle: "记录入睡",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: RecordWakeIntent(),
            phrases: ["用\(.applicationName)记录起床"],
            shortTitle: "记录起床",
            systemImageName: "sunrise.fill"
        )
    }
}
