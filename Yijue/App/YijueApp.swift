import SwiftUI

@main
struct YijueApp: App {
    @StateObject private var store = SleepStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.accentColor)
                .onOpenURL { url in
                    handle(url)
                }
                .task {
                    await store.refreshSchedules()
                    await store.runMotionDetection(force: false)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.refresh()
                    Task {
                        await store.refreshSchedules()
                        await store.runMotionDetection(force: false)
                    }
                }
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "yijue" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: { $0.name == "kind" })?.value
            ?? url.pathComponents.last
        let kind: SleepEventKind?
        switch value {
        case "bedtime": kind = .bedtime
        case "wake": kind = .wake
        default: kind = nil
        }
        guard let kind else { return }
        _ = store.recordEvent(kind: kind, source: .manual)
    }
}
