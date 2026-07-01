import SwiftUI

struct HUDView: View {
    @Bindable var store: HUDStore

    var body: some View {
        VStack(spacing: 6) {
            header
            if let error = store.loadError {
                errorBanner(error)
            }
            if store.hidState == .permissionNeeded {
                permissionBanner
            }
            KeyboardView(store: store)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .padding(.top, 4)
        .frame(minWidth: 420, minHeight: 220)
        .sheet(isPresented: $store.showStatsSheet) {
            StatsSheet(store: store)
        }
    }

    /// Input Monitoring is granted per code-signing identity; after allowing
    /// in System Settings the app must be relaunched to pick it up.
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard.badge.exclamationmark")
            Text("打鍵の可視化には「入力モニタリング」権限が必要です")
                .font(.system(size: 11))
            Spacer()
            Button("設定を開く") { store.openInputMonitoringSettings() }
                .font(.system(size: 11))
            Button("再起動") { store.relaunch() }
                .font(.system(size: 11))
        }
        .padding(6)
        .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let keymap = store.keymap {
                ForEach(keymap.layers, id: \.index) { layer in
                    layerPill(layer)
                }
            }
            if store.pinnedLayer != nil {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("レイヤー固定中（推定停止）")
            }
            Spacer()
            connectionDot
            gearMenu
        }
        .padding(.horizontal, 10)
    }

    private func layerPill(_ layer: Layer) -> some View {
        Button {
            if store.displayedLayer == layer.index {
                store.togglePin()
            } else {
                store.displayedLayer = layer.index
                if store.pinnedLayer != nil { store.pinnedLayer = layer.index }
            }
        } label: {
            Text(layer.name)
                .font(.system(size: 11, weight: store.displayedLayer == layer.index ? .bold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(store.displayedLayer == layer.index
                                   ? Color.accentColor.opacity(0.8)
                                   : Color.primary.opacity(0.08))
                )
                .foregroundStyle(store.displayedLayer == layer.index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help("クリックで表示、再クリックで固定/解除")
    }

    private var connectionDot: some View {
        Circle()
            .fill(store.deviceConnected ? Color.green : Color.gray.opacity(0.5))
            .frame(width: 7, height: 7)
            .help(store.deviceConnected ? "roBa 接続中" : "roBa 未接続")
    }

    private var gearMenu: some View {
        Menu {
            Button("キーマップ再読込") { store.loadAll() }
            Divider()
            Toggle("ヒートマップ", isOn: $store.showHeatmap)
            Button("統計…") { store.showStatsSheet = true }
            Divider()
            Picker("不透明度", selection: $store.opacity) {
                Text("100%").tag(1.0)
                Text("90%").tag(0.9)
                Text("80%").tag(0.8)
                Text("65%").tag(0.65)
                Text("50%").tag(0.5)
            }
            Divider()
            Button("終了") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
    }
}
