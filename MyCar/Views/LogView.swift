import SwiftUI

/// 日志页,对应 Android 的 NotificationsFragment(原 logTextView 输出)
struct LogView: View {
    @StateObject private var ble = BLEManager.shared

    var body: some View {
        NavigationStack {
            List(ble.logs.indices.reversed(), id: \.self) { index in
                Text(ble.logs[index])
                    .font(.system(.footnote, design: .monospaced))
            }
            .navigationTitle("运行日志")
            .toolbar {
                Button("清空") { ble.logs.removeAll() }
            }
        }
    }
}

#Preview {
    LogView()
}
