import Foundation
import CoreBluetooth
import Combine

/// BLE 设备管理器(单例)
/// 合并对应 Android 版的 CBLEDevice(BLE 连接/RSSI 分析/车辆控制)
/// 与 MyBLEService(后台扫描调度:已连接则等待,运动中则每 6 秒扫描一次,静止则暂停)
///
/// iOS 差异说明:
/// 1. 后台能力由 `bluetooth-central` 后台模式提供(见 Info.plist),无需前台服务保活
/// 2. 通过 State Restoration(restoreID),App 被系统终止后,车辆广播/断开等蓝牙事件可唤醒 App
///    (用户主动上滑强杀 App 后无法唤醒,需重新打开一次,与国产 Android ROM 行为一致)
/// 3. 后台扫描必须指定 Service UUID,要求 ESP32 固件在广播包中包含 serviceUUID
/// 4. 锁屏/后台时 Timer 会被系统挂起,因此 RSSI 测距由固件心跳驱动:
///    固件需在连接后通过命令特征周期 notify(建议 200~500ms 一次),
///    App 在 didUpdateValue 回调中 readRSSI,前后台均可持续自动解落锁
final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    // MARK: - 与 ESP32 固件的约定(与 Android 版完全一致)
    static let serviceUUID = CBUUID(string: "91486214-AB7F-E39C-5A68-C1F2D4A9B73E")
    static let characteristicUUID = CBUUID(string: "3EB7A9D4-F2C1-685A-9CE3-7FAB14624891")
    static let deviceName = "MyCar"
    private static let restoreID = "com.happy.mycar.central"

    // MARK: - 配置与算法
    let config = ESPConfig()
    private lazy var analyzer = RssiAnalyzer(
        windowSize: 10,
        posThreshold: config.rssiPosThreshold,
        negThreshold: config.rssiNegThreshold,
        confirmCount: 3
    )
    private var configObservers: Set<AnyCancellable> = []

    // MARK: - 对外状态
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false
    @Published private(set) var proximity: RssiAnalyzer.State = .unknown
    @Published private(set) var rssi = 0
    @Published private(set) var statusText = "未连接"
    @Published var logs: [String] = []

    // MARK: - 内部状态
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var scanTimeoutWork: DispatchWorkItem?
    private var rescanWork: DispatchWorkItem?
    private var lastScanTime = Date.distantPast

    private static let scanInterval: TimeInterval = 6   // 对应 Android 的 6 秒扫描间隔
    private static let scanTimeout: TimeInterval = 8    // 单次扫描超时

    private override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
        // 阈值修改时同步到分析器
        config.$rssiPosThreshold
            .combineLatest(config.$rssiNegThreshold)
            .sink { [weak self] thresholds in
                self?.analyzer.setThreshold(pos: thresholds.0, neg: thresholds.1)
            }
            .store(in: &configObservers)
        // config(嵌套 ObservableObject)的变化转发给视图层,保证 UI 自动刷新
        config.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &configObservers)
    }

    // MARK: - 日志
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func log(_ message: String) {
        let line = "\(Self.timeFormatter.string(from: Date()))  \(message)"
        logs.append(line)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        print(line)
    }

    // MARK: - 扫描调度(事件驱动版 while 循环)
    /// 对应 Android MyBLEService 主循环:未连接 + 运动中 → 每 6 秒扫描一次
    func scheduleScan() {
        guard !isConnected, !isScanning, central.state == .poweredOn else { return }
        rescanWork?.cancel()

        // 静止时暂停扫描以省电(对应 Android 的 canScanBLE 判断)
        guard MotionManager.shared.isMoving else {
            log("设备静止,暂停扫描")
            let work = DispatchWorkItem { [weak self] in self?.scheduleScan() }
            rescanWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
            return
        }

        let elapsed = Date().timeIntervalSince(lastScanTime)
        if elapsed >= Self.scanInterval {
            startScan()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.scheduleScan() }
            rescanWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (Self.scanInterval - elapsed), execute: work)
        }
    }

    private func startScan() {
        guard central.state == .poweredOn, !isConnected else { return }
        lastScanTime = Date()
        isScanning = true
        log("开始扫描...")
        // 前后台统一按 Service UUID 扫描(后台模式强制要求;固件需在广播中包含该 UUID)
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        // 超时未找到则停止,交给下一轮调度
        scanTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            self.central.stopScan()
            self.isScanning = false
            self.log("扫描超时,未发现设备")
            self.scheduleScan()
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: work)
    }

    // MARK: - RSSI 测距(心跳驱动,前后台均生效)
    /// 对应 Android 的 updateRSSI 轮询线程。iOS 后台 Timer 会被挂起,
    /// 改为订阅命令特征的 notify:固件周期发心跳包 → didUpdateValue → readRSSI。
    /// 断开后 notify 自动失效,重连时在 didDiscoverCharacteristicsFor 中重新订阅
    private func subscribeHeartbeat() {
        guard let ch = commandCharacteristic, let p = peripheral else { return }
        p.setNotifyValue(true, for: ch)
        log("已订阅心跳,开始持续测距")
    }

    // MARK: - 车辆控制(对应 Android unlockCar/lockCar/trunkCar/openWindow)
    func unlockCar() {
        config.isLock = false
        writeByte(UInt8(clamping: config.unlockKey))
    }

    func lockCar() {
        config.isLock = true
        writeByte(UInt8(clamping: config.lockKey))
    }

    func trunkCar() {
        writeByte(UInt8(clamping: config.trunkKey))
    }

    /// 对应 Android SendCommandToBle:1 字节命令 + 4 字节小端延时
    func openWindow(delay: Int32 = 300) {
        guard let ch = commandCharacteristic, let p = peripheral else { return }
        var data = Data([UInt8(clamping: config.windowKey)])
        var little = delay.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        p.writeValue(data, for: ch, type: .withResponse)
    }

    private func writeByte(_ byte: UInt8) {
        guard let ch = commandCharacteristic, let p = peripheral else {
            log("未连接,无法下发命令")
            return
        }
        p.writeValue(Data([byte]), for: ch, type: .withResponse)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("蓝牙已打开")
            statusText = "未连接"
            scheduleScan()
        case .poweredOff:
            log("蓝牙已关闭,请打开蓝牙以继续使用")
            statusText = "蓝牙已关闭"
            isScanning = false
            isConnected = false
        default:
            statusText = "蓝牙不可用"
        }
    }

    /// State Restoration:App 被系统终止后由蓝牙事件唤醒时回调
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        log("系统唤醒,恢复蓝牙状态")
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = restored.first {
            p.delegate = self
            peripheral = p
            if p.state == .connected {
                isConnected = true
                statusText = "已连接"
                p.discoverServices([Self.serviceUUID])
            } else {
                scheduleScan()
            }
        } else {
            scheduleScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // 双保险:校验设备名(部分固件 ADV 中可能不带 Complete Local Name)
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard p.name == Self.deviceName || advName == Self.deviceName else { return }

        scanTimeoutWork?.cancel()
        central.stopScan()
        isScanning = false
        log("发现设备,正在尝试连接:\(Self.deviceName)")

        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
        statusText = "正在连接..."
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        log("已连接,开始查找服务")
        statusText = "查找服务中"
        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("连接失败:\(error?.localizedDescription ?? "未知错误")")
        statusText = "连接失败"
        peripheral = nil
        scheduleScan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("连接断开")
        isConnected = false
        config.isLock = true // 对应 Android:断开后置为锁车状态
        proximity = .unknown
        analyzer.reset()
        commandCharacteristic = nil
        statusText = "未连接"
        scheduleScan()
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            log("查找服务失败")
            disconnect()
            return
        }
        log("找到服务,查找特征")
        p.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let ch = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            log("未找到合法服务")
            disconnect()
            return
        }
        commandCharacteristic = ch
        isConnected = true
        config.isLock = true
        statusText = "遥控器已连接"
        log("找到合法服务,遥控器已连接")
        subscribeHeartbeat()
    }

    /// 固件心跳包回调:每次心跳触发一次 RSSI 读取(锁屏/后台同样生效)
    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        p.readRSSI()
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        let value = RSSI.intValue
        rssi = value
        analyzer.addRssi(value)
        let state = analyzer.currentState
        if state != proximity {
            proximity = state
            switch state {
            case .approaching: log("靠近车辆,RSSI: \(value)")
            case .movingAway: log("远离车辆,RSSI: \(value)")
            case .unknown: break
            }
        }
        // 与 Android 一致:每次回调都检查触发条件,由 isLock 状态保证幂等
        switch state {
        case .approaching:
            if config.autoUnlock, config.isLock { unlockCar() }
        case .movingAway:
            if config.autoLock, !config.isLock { lockCar() }
        case .unknown:
            break
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            // 对应 Android:写入失败时回滚锁车状态
            config.isLock.toggle()
            log("操作失败:\(error.localizedDescription)")
        } else {
            log("操作成功")
        }
    }
}
