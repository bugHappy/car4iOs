import Foundation

/// 车辆配置,对应 Android 版 ESP_Config(SharedPreferences → UserDefaults)
/// 键名与 Android 版保持一致,方便双端对照
final class ESPConfig: ObservableObject {

    /// 当前锁车状态(运行时状态,不持久化)
    @Published var isLock = false

    @Published var rssiPosThreshold: Int { didSet { defaults.set(rssiPosThreshold, forKey: "ESP32_RSSI_POS_THRESHOLD") } }
    @Published var rssiNegThreshold: Int { didSet { defaults.set(rssiNegThreshold, forKey: "ESP32_RSSI_NEG_THRESHOLD") } }
    @Published var autoLock: Bool { didSet { defaults.set(autoLock, forKey: "AUTO_LOCK") } }
    @Published var autoUnlock: Bool { didSet { defaults.set(autoUnlock, forKey: "AUTO_UNLOCK") } }

    @Published var lockKey: Int { didSet { defaults.set(lockKey, forKey: "LOCK_KEY") } }
    @Published var unlockKey: Int { didSet { defaults.set(unlockKey, forKey: "UNLOCK_KEY") } }
    @Published var trunkKey: Int { didSet { defaults.set(trunkKey, forKey: "TRUNK_KEY") } }
    @Published var windowKey: Int { didSet { defaults.set(windowKey, forKey: "WINDOW_KEY") } }

    private let defaults = UserDefaults.standard

    init() {
        let d = defaults
        rssiPosThreshold = d.object(forKey: "ESP32_RSSI_POS_THRESHOLD") as? Int ?? -75
        rssiNegThreshold = d.object(forKey: "ESP32_RSSI_NEG_THRESHOLD") as? Int ?? -85
        autoLock   = d.object(forKey: "AUTO_LOCK") as? Bool ?? true
        autoUnlock = d.object(forKey: "AUTO_UNLOCK") as? Bool ?? true
        lockKey   = d.object(forKey: "LOCK_KEY") as? Int ?? 0
        unlockKey = d.object(forKey: "UNLOCK_KEY") as? Int ?? 1
        trunkKey  = d.object(forKey: "TRUNK_KEY") as? Int ?? 2
        windowKey = d.object(forKey: "WINDOW_KEY") as? Int ?? 3
    }
}
