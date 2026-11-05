import Foundation
import CoreMotion

/// 加速度运动检测,对应 Android 版 AccelerometerSensor
/// 注意单位差异:Android SensorManager 为 m/s²(阈值 10 ≈ 重力 9.8 附近),
/// CoreMotion 单位为 g,对应阈值约 1.02g
final class MotionManager: ObservableObject {
    static let shared = MotionManager()

    private let manager = CMMotionManager()

    /// 是否有运动(静止超过 50 秒视为 false),对应 Android 的 isMoving
    @Published private(set) var isMoving = true

    private var lastMoveTime = Date()

    private init() {}

    func start() {
        guard manager.isAccelerometerAvailable else {
            print("加速度传感器不可用")
            return
        }
        manager.accelerometerUpdateInterval = 5.0 // 对应 Android 的 5000000μs 采样间隔
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            if magnitude > 1.02 {
                // 有运动,重置计时
                self.lastMoveTime = Date()
                self.isMoving = true
            } else if self.isMoving, Date().timeIntervalSince(self.lastMoveTime) > 50 {
                // 静止超过 50 秒
                self.isMoving = false
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
    }
}
