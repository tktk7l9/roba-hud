import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

/// Owns battery monitoring, history persistence, and notifications
/// (zmk-battery-center feature set folded into the HUD).
@MainActor
@Observable
final class BatteryCenter {
    var levels = BatteryLevels()
    var history = BatteryHistory()
    var state: BatteryMonitor.State = .idle
    var showSheet = false

    var notificationsEnabled: Bool = Prefs.batteryNotificationsEnabled {
        didSet {
            Prefs.batteryNotificationsEnabled = notificationsEnabled
            if notificationsEnabled { Notifier.requestAuthorization() }
        }
    }
    var disconnectNotificationsEnabled: Bool = Prefs.disconnectNotificationsEnabled {
        didSet {
            Prefs.disconnectNotificationsEnabled = disconnectNotificationsEnabled
            if disconnectNotificationsEnabled { Notifier.requestAuthorization() }
        }
    }
    var threshold: Int = Prefs.batteryNotifyThreshold {
        didSet {
            Prefs.batteryNotifyThreshold = threshold
            policy.threshold = threshold
        }
    }

    @ObservationIgnored private var policy = BatteryNotificationPolicy()
    @ObservationIgnored private let monitor = BatteryMonitor()
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    static var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoBaHUD/battery-history.json")
    }

    func start() {
        policy.threshold = threshold
        loadHistory()
        if notificationsEnabled || disconnectNotificationsEnabled {
            Notifier.requestAuthorization()
        }
        monitor.onUpdate = { [weak self] role, level in
            Task { @MainActor in self?.handleUpdate(role: role, level: level) }
        }
        monitor.onState = { [weak self] state in
            Task { @MainActor in self?.handleState(state) }
        }
        monitor.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.monitor.refresh() }
        }
    }

    private func handleUpdate(role: BatteryRole, level: Int) {
        levels.set(role: role, level: level, at: Date())
        history.append(levels: levels.levels, at: Date())
        scheduleSave()
        if notificationsEnabled, policy.shouldNotify(role: role, level: level) {
            Notifier.post(title: "roBa バッテリー低下",
                          body: "\(role.displayName)手側の残量が \(level)% です")
        }
    }

    private func handleState(_ newState: BatteryMonitor.State) {
        let wasConnected = state == .connected
        state = newState
        if disconnectNotificationsEnabled {
            if wasConnected, newState == .disconnected {
                Notifier.post(title: "roBa 切断", body: "キーボードとの接続が切れました")
            } else if !wasConnected, newState == .connected {
                Notifier.post(title: "roBa 接続", body: "キーボードに接続しました")
            }
        }
    }

    func clearHistory() {
        history.samples.removeAll()
        scheduleSave()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let loaded = try? JSONDecoder().decode(BatteryHistory.self, from: data) else { return }
        history = loaded
        history.prune(now: Date())
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        do {
            let dir = Self.historyURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: Self.historyURL, options: .atomic)
        } catch {
            // History is best-effort.
        }
    }
}

/// UserNotifications wrapper. Only functional from the packaged .app
/// (UNUserNotificationCenter requires a real bundle).
enum Notifier {
    static var available: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else {
            NSLog("notification (unbundled): %@ — %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Launch-at-login toggle via SMAppService (packaged app only).
enum LoginItem {
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var enabled: Bool {
        available && SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        guard available else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("login item toggle failed: %@", "\(error)")
        }
    }
}
