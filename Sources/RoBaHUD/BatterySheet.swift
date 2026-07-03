import Charts
import SwiftUI

/// Compact battery chips for the HUD header. Click opens the detail sheet.
struct BatteryChips: View {
    var battery: BatteryCenter

    var body: some View {
        Button {
            battery.showSheet = true
        } label: {
            HStack(spacing: 6) {
                chip(role: .central)
                chip(role: .peripheral(0))
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func chip(role: BatteryRole) -> some View {
        let level = battery.levels.level(of: role)
        return HStack(spacing: 2) {
            Image(systemName: symbol(for: level))
                .font(.system(size: 10))
            Text(level.map { "\(role.displayName)\($0)%" } ?? "\(role.displayName)—")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(color(for: level))
    }

    private func symbol(for level: Int?) -> String {
        guard let level else { return "battery.0" }
        switch level {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    private func color(for level: Int?) -> Color {
        guard let level else { return .secondary }
        switch BatterySeverity.of(level: level) {
        case .ok: return .secondary
        case .low: return .orange
        case .critical: return .red
        }
    }

    private var helpText: String {
        switch battery.state {
        case .unauthorized: "Bluetooth 権限がありません（システム設定 → プライバシー → Bluetooth）"
        case .bluetoothOff: "Bluetooth がオフです"
        case .searching: "roBa を探しています…"
        default: "バッテリー残量（クリックで履歴）"
        }
    }
}

/// Battery history graph + notification / startup settings.
struct BatterySheet: View {
    @Bindable var battery: BatteryCenter
    @State private var rangeDays: Double = 7
    @State private var launchAtLogin = LoginItem.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("バッテリー").font(.headline)
                Spacer()
                Button("閉じる") { battery.showSheet = false }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 16) {
                currentLevel(role: .central)
                currentLevel(role: .peripheral(0))
                Spacer()
                if let updated = battery.levels.updatedAt {
                    Text("更新 \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("期間", selection: $rangeDays) {
                Text("24時間").tag(1.0)
                Text("7日").tag(7.0)
                Text("30日").tag(30.0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            chart

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("バッテリー低下を通知", isOn: $battery.notificationsEnabled)
                HStack {
                    Text("しきい値")
                    Picker("", selection: $battery.threshold) {
                        ForEach([10, 15, 20, 30], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .frame(width: 80)
                    .disabled(!battery.notificationsEnabled)
                }
                Toggle("接続/切断を通知", isOn: $battery.disconnectNotificationsEnabled)
                Toggle("メニューバーに残量を表示", isOn: $battery.menuBarEnabled)
                if LoginItem.available {
                    Toggle("ログイン時に起動", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in LoginItem.set(on) }
                }
            }
            .font(.system(size: 12))

            HStack {
                Spacer()
                Button("履歴をクリア", role: .destructive) { battery.clearHistory() }
                    .font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func currentLevel(role: BatteryRole) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(role.displayName)手側")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(battery.levels.level(of: role).map { "\($0)%" } ?? "—")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(levelColor(role: role))
        }
    }

    private func levelColor(role: BatteryRole) -> Color {
        guard let level = battery.levels.level(of: role) else { return .secondary }
        switch BatterySeverity.of(level: level) {
        case .ok: return .primary
        case .low: return .orange
        case .critical: return .red
        }
    }

    @ViewBuilder
    private var chart: some View {
        let now = Date()
        let roles = battery.history.knownRoles
        if roles.isEmpty {
            Text("履歴はまだありません。接続中に自動で記録されます。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart {
                ForEach(roles, id: \.key) { role in
                    ForEach(battery.history.series(role: role, days: rangeDays, now: now), id: \.at) { point in
                        LineMark(
                            x: .value("時刻", point.at),
                            y: .value("残量", point.level),
                            series: .value("半分", role.displayName)
                        )
                        .foregroundStyle(by: .value("半分", "\(role.displayName)手側"))
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartForegroundStyleScale(["右手側": Color.blue, "左手側": Color.orange])
            .frame(height: 140)
        }
    }
}
