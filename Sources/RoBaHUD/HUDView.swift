import SwiftUI

struct HUDView: View {
    @Bindable var store: HUDStore

    var body: some View {
        Group {
            if store.compactMode {
                compactBar
            } else {
                fullBody
            }
        }
        .sheet(isPresented: $store.showStatsSheet) {
            StatsSheet(store: store)
        }
        .sheet(isPresented: $store.showDeviceSheet) {
            DeviceSheet(store: store)
        }
        .sheet(isPresented: $store.showFlashGuide) {
            FlashGuide(store: store)
        }
        .sheet(isPresented: Binding(
            get: { store.battery.showSheet },
            set: { store.battery.showSheet = $0 }
        )) {
            BatterySheet(battery: store.battery)
        }
    }

    private var fullBody: some View {
        VStack(spacing: 6) {
            header
            if let error = store.loadError {
                errorBanner(error)
            }
            if store.hidState == .permissionNeeded {
                permissionBanner
            }
            if let editError = store.editError {
                dismissibleBanner(editError, color: .red) { store.editError = nil }
            }
            if let toast = store.statusToast {
                dismissibleBanner(toast, color: .blue) { store.statusToast = nil }
            }
            if store.gitDiff != nil {
                diffBar
            }
            if store.pipelineState != .idle {
                pipelineRow
            }
            KeyboardView(store: store)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .padding(.top, 4)
        .frame(minWidth: 420, minHeight: 220)
    }

    /// Compact bar: current layer + recent keys + battery, one row.
    private var compactBar: some View {
        HStack(spacing: 8) {
            if store.pinnedLayer != nil {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            if let keymap = store.keymap, keymap.layers.indices.contains(store.displayedLayer) {
                Text(keymap.layers[store.displayedLayer].name)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 5) {
                ForEach(Array(store.recentPresses.enumerated()), id: \.element.id) { index, press in
                    Text(press.text)
                        .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                        .opacity(1.0 - Double(index) * 0.15)
                }
            }
            .frame(minWidth: 120, alignment: .leading)
            Spacer()
            BatteryChips(battery: store.battery)
            connectionDot
            gearMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 460)
    }

    // MARK: - Git / pipeline UI

    private var diffBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.circle.fill").foregroundStyle(.yellow)
                Text("未コミットのキーマップ変更").font(.system(size: 11))
                Button(store.showDiffDetail ? "diffを隠す" : "diff") {
                    store.showDiffDetail.toggle()
                }
                .font(.system(size: 10))
                Spacer()
                Button("元に戻す", role: .destructive) { store.revertEdits() }
                    .font(.system(size: 10))
                Button("Commit & Push") { store.commitAndPush() }
                    .font(.system(size: 10, weight: .semibold))
                    .disabled(store.pipelineState.isRunning)
            }
            if store.showDiffDetail, let diff = store.gitDiff {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()),
                                id: \.offset) { _, line in
                            Text(String(line))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(diffColor(String(line)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(4)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(6)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
    }

    private func diffColor(_ line: String) -> Color {
        if line.hasPrefix("+"), !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-"), !line.hasPrefix("---") { return .red }
        return .secondary
    }

    private var pipelineRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                switch store.pipelineState {
                case .running(let message):
                    ProgressView().controlSize(.small)
                    Text(message).font(.system(size: 11))
                case .succeeded(let message):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(message).font(.system(size: 11))
                    Button("書き込みガイド") { store.showFlashGuide = true }
                        .font(.system(size: 10))
                case .failed(let message):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text(message).font(.system(size: 11)).lineLimit(2)
                case .idle:
                    EmptyView()
                }
                Spacer()
                if !store.pipelineState.isRunning {
                    Button("閉じる") { store.pipelineState = .idle }
                        .font(.system(size: 10))
                }
            }
            if !store.pipelineLog.isEmpty {
                DisclosureGroup {
                    ScrollView {
                        Text(store.pipelineLog.joined(separator: "\n\n"))
                            .font(.system(size: 9, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                } label: {
                    Text("ログ").font(.system(size: 10))
                }
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
    }

    private func dismissibleBanner(_ message: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack {
            Text(message).font(.system(size: 11))
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain)
        }
        .padding(6)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
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
            BatteryChips(battery: store.battery)
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
            Button("デバイス…") { store.showDeviceSheet = true }
            Button("バッテリー…") { store.battery.showSheet = true }
            Divider()
            Toggle("編集モード", isOn: $store.editMode)
            Button("CHEATSHEET再生成") { store.regenerateCheatsheet() }
            Button("SVG再生成 (draw.yml)") { store.triggerDraw() }
            Divider()
            Toggle("コンパクト表示", isOn: $store.compactMode)
            Toggle("クリック透過", isOn: Binding(
                get: { store.clickThrough },
                set: { store.setClickThrough($0) }
            ))
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
