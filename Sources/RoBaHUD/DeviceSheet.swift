import SwiftUI

/// BT profile management: per-profile labels, which profile this Mac is on
/// (auto-learned from the firmware marker, or set manually), live connection
/// state, and where the switch/clear keys live in the keymap.
struct DeviceSheet: View {
    @Bindable var store: HUDStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("デバイス管理").font(.headline)
                Spacer()
                Button("閉じる") { store.showDeviceSheet = false }
                    .keyboardShortcut(.cancelAction)
            }

            let actions = store.keymap.map(BTAction.scan) ?? []
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<ProfileMarker.profileCount, id: \.self) { n in
                    profileRow(n, actions: actions)
                }
            }

            Divider()
            keyGuide(actions)

            Text("「このMac」はプロファイル切替時にファームのマーカーで自動記録されます（要 最新ファーム）。手動で指定する場合は行の「このMacに設定」を使ってください。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func profileRow(_ n: Int, actions: [BTAction]) -> some View {
        let isThisMac = store.thisMacProfile == n
        let connected = isThisMac && store.deviceConnected
        let hasKey = actions.contains { $0.kind == .select(n) }
        return HStack(spacing: 8) {
            Circle()
                .fill(connected ? Color.green : (isThisMac ? Color.accentColor : Color.secondary.opacity(0.3)))
                .frame(width: 8, height: 8)
            Text("BT\(n)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 30, alignment: .leading)
            TextField("未設定", text: Binding(
                get: { store.btLabels[n] ?? "" },
                set: { store.btLabels[n] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(width: 130)
            if isThisMac {
                Text(connected ? "このMac・接続中" : "このMac")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(connected ? .green : Color.accentColor)
                Button("解除") { store.thisMacProfile = nil }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Button("このMacに設定") { store.thisMacProfile = n }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !hasKey {
                Text("キー未割当")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func keyGuide(_ actions: [BTAction]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("キー操作").font(.system(size: 11, weight: .semibold))
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                HStack(spacing: 6) {
                    Text(guideTitle(action.kind))
                        .font(.system(size: 11))
                        .frame(width: 110, alignment: .leading)
                    Text("\(store.keymap?.layerName(action.layer) ?? "L\(action.layer)") レイヤー")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("表示") {
                        store.selectLayer(action.layer)
                        store.showDeviceSheet = false
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            if actions.isEmpty {
                Text("keymap に BT キーが見つかりません")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func guideTitle(_ kind: BTAction.Kind) -> String {
        switch kind {
        case .select(let n): "BT\(n) に切替"
        case .clear: "ボンドクリア（0.5秒ホールド）"
        case .other(let cmd): cmd
        }
    }
}
