import Foundation

/// RSSI 滑动窗口分析器,等价移植自 Android 版 RssiAnalyzer
/// 逻辑:窗口均值超过靠近阈值累计 N 次判定为"靠近",低于远离阈值累计 N 次判定为"远离"
final class RssiAnalyzer {

    enum State {
        case unknown      // 初始状态
        case approaching  // 正在靠近
        case movingAway   // 正在远离
    }

    // 可配置参数
    private let windowSize: Int     // 滑动窗口大小(建议 10-20)
    private var posThreshold: Int   // 靠近阈值(如 -75)
    private var negThreshold: Int   // 远离阈值(如 -85)
    private let confirmCount: Int   // 状态切换确认次数(建议 3)

    // 运行时状态
    private var window: [Int] = []
    private var windowSum = 0
    private(set) var currentState: State = .unknown
    private var confirmCounter = 0

    init(windowSize: Int = 10, posThreshold: Int, negThreshold: Int, confirmCount: Int = 3) {
        self.windowSize = windowSize
        self.posThreshold = posThreshold
        self.negThreshold = negThreshold
        self.confirmCount = confirmCount
    }

    /// 添加新的 RSSI 值并触发分析
    func addRssi(_ rssi: Int) {
        if window.count == windowSize {
            windowSum -= window.removeFirst()
            window.append(rssi)
            windowSum += rssi
            analyze()
        } else {
            window.append(rssi)
            windowSum += rssi
        }
    }

    private func analyze() {
        let avg = windowSum / windowSize
        if avg > posThreshold {
            handleThresholdCrossing(target: .approaching)
        } else if avg < negThreshold {
            handleThresholdCrossing(target: .movingAway)
        } else {
            confirmCounter = max(0, confirmCounter - 1)
        }
    }

    private func handleThresholdCrossing(target: State) {
        if currentState != target {
            confirmCounter += 1
            if confirmCounter >= confirmCount {
                currentState = target
                confirmCounter = 0
            }
        } else {
            confirmCounter = 0
        }
    }

    func setThreshold(pos: Int, neg: Int) {
        posThreshold = pos
        negThreshold = neg
    }

    func reset() {
        window.removeAll()
        windowSum = 0
        currentState = .unknown
        confirmCounter = 0
    }
}
