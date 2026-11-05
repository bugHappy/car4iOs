import SwiftUI

/// 设置页,对应 Android 的 SetFragment
struct SettingsView: View {
    @StateObject private var config = BLEManager.shared.config

    var body: some View {
        NavigationStack {
            Form {
                Section("距离判断(dBm)") {
                    Stepper("靠近阈值: \(config.rssiPosThreshold)",
                            value: $config.rssiPosThreshold, in: -100 ... -40)
                    Stepper("远离阈值: \(config.rssiNegThreshold)",
                            value: $config.rssiNegThreshold, in: -110 ... -60)
                    Text("RSSI 高于靠近阈值判定为靠近,低于远离阈值判定为远离")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("自动化") {
                    Toggle("靠近自动解锁", isOn: $config.autoUnlock)
                    Toggle("远离自动锁车", isOn: $config.autoLock)
                }

                Section("按键码") {
                    KeyField(title: "关锁键", value: $config.lockKey)
                    KeyField(title: "开锁键", value: $config.unlockKey)
                    KeyField(title: "尾箱键", value: $config.trunkKey)
                    KeyField(title: "车窗键", value: $config.windowKey)
                }
            }
            .navigationTitle("设置")
        }
    }
}

private struct KeyField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}

#Preview {
    SettingsView()
}
