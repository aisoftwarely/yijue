import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("今晚", systemImage: "moon.stars.fill")
                }

            StatsView()
                .tabItem {
                    Label("统计", systemImage: "chart.bar.xaxis")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SleepStore.shared)
}
