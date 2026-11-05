import SwiftUI

@main
struct MyCarApp: App {

    init() {
        // 启动运动检测(对应 Android 的 AccelerometerSensor)
        MotionManager.shared.start()
        // 触发 BLEManager 单例初始化,centralManagerDidUpdateState 会自动开始扫描调度
        _ = BLEManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
