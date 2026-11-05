import SwiftUI

/// 主界面,对应 Android 的 MainActivity + 底部导航(MyCar / Set / Notifications)
struct ContentView: View {
    var body: some View {
        TabView {
            MyCarView()
                .tabItem { Label("我的车", systemImage: "car.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
            LogView()
                .tabItem { Label("日志", systemImage: "list.bullet.rectangle") }
        }
    }
}

#Preview {
    ContentView()
}
