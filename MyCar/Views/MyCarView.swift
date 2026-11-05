import SwiftUI

/// 车辆控制主页,对应 Android 的 MyCarFragment
struct MyCarView: View {
    @StateObject private var ble = BLEManager.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 状态区
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ble.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(ble.statusText)
                            .font(.headline)
                    }
                    Text(ble.config.isLock ? "已锁车" : "已解锁")
                        .font(.largeTitle.bold())
                        .foregroundStyle(ble.config.isLock ? .primary : .orange)
                    HStack(spacing: 16) {
                        Label("\(ble.rssi) dBm", systemImage: "antenna.radiowaves.left.and.right")
                        Label(proximityText, systemImage: "figure.walk")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                Spacer()

                // 控制按钮 2x2,对应 Android 的解锁/锁车/尾箱/车窗
                LazyVGrid(columns: columns, spacing: 16) {
                    ControlButton(title: "解锁", icon: "lock.open.fill", tint: .green) {
                        ble.unlockCar()
                    }
                    ControlButton(title: "锁车", icon: "lock.fill", tint: .red) {
                        ble.lockCar()
                    }
                    ControlButton(title: "尾箱", icon: "car.rear.fill", tint: .blue) {
                        ble.trunkCar()
                    }
                    ControlButton(title: "车窗", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down", tint: .purple) {
                        ble.openWindow()
                    }
                }
                .disabled(!ble.isConnected)
                .opacity(ble.isConnected ? 1 : 0.4)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("智能车钥匙")
        }
    }

    private var proximityText: String {
        switch ble.proximity {
        case .approaching: return "靠近中"
        case .movingAway: return "远离中"
        case .unknown:    return "距离未知"
        }
    }
}

private struct ControlButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    MyCarView()
}
