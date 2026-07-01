import AppKit
import Foundation
import Observation

/// Central app state: keymap + geometry, HID monitoring, layer inference,
/// live highlights.
@MainActor
@Observable
final class HUDStore {
    var keymap: Keymap?
    var geometry: [KeyGeometry] = []
    var layoutBounds = LayoutBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)
    var loadError: String?

    /// The layer currently rendered.
    var displayedLayer = 0
    /// Manual pin: while set, inference must not change displayedLayer.
    var pinnedLayer: Int? {
        didSet { engine?.pinned = pinnedLayer }
    }

    /// Positions (0-based binding indices) currently lit, on the displayed layer.
    var highlighted: Set<Int> = []

    enum HIDState {
        case off                // not started (no keymap yet)
        case running            // monitor up, waiting for / receiving events
        case permissionNeeded   // TCC denied or open failed
    }
    var hidState: HIDState = .off
    var deviceConnected = false

    var opacity: Double = Prefs.opacity {
        didSet { Prefs.opacity = opacity }
    }

    private var engine: InferenceEngine?
    private var monitor: HIDMonitor?
    private var tickTimer: Timer?

    init() {}

    // MARK: - Loading

    func loadAll() {
        loadGeometry()
        loadKeymap()
    }

    func loadGeometry() {
        do {
            let data = try Data(contentsOf: Prefs.layoutJSONURL)
            let keys = try GeometryLoader.load(json: data)
            geometry = keys
            layoutBounds = GeometryLoader.bounds(of: keys)
        } catch {
            loadError = "レイアウト読込失敗 (\(Prefs.layoutJSONURL.path)): \(error)"
        }
    }

    /// (Re)load the keymap. On failure the last good keymap stays rendered and
    /// the error is surfaced in a banner.
    func loadKeymap() {
        do {
            let url = Prefs.keymapURL
            let source = try String(contentsOf: url, encoding: .utf8)
            let parsed = try KeymapParser.parse(source: source, fileURL: url)
            if !geometry.isEmpty,
               let count = parsed.layers.first?.bindings.count, count != geometry.count {
                throw ParseError(message: "bindings数(\(count))がレイアウトのキー数(\(geometry.count))と一致しません")
            }
            keymap = parsed
            loadError = nil
            if displayedLayer >= parsed.layers.count { displayedLayer = 0 }
            if engine == nil {
                var fresh = InferenceEngine(keymap: parsed)
                fresh.pinned = pinnedLayer
                engine = fresh
            } else {
                engine?.reload(keymap: parsed)
            }
        } catch {
            loadError = "keymap 読込失敗: \(error)"
        }
    }

    // MARK: - Layer selection

    func selectLayer(_ index: Int) {
        guard let keymap, keymap.layers.indices.contains(index) else { return }
        displayedLayer = index
        if pinnedLayer != nil { pinnedLayer = index }
    }

    func togglePin() {
        pinnedLayer = pinnedLayer == nil ? displayedLayer : nil
    }

    // MARK: - HID monitoring

    func startMonitoring() {
        guard monitor == nil, engine != nil else { return }
        if HIDMonitor.Access.current() != .granted {
            HIDMonitor.requestAccess()   // shows the system prompt once
        }
        let m = HIDMonitor()
        m.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleHID(event) }
        }
        m.onOpenFailure = { [weak self] _ in
            Task { @MainActor in self?.hidState = .permissionNeeded }
        }
        m.start()
        monitor = m
        hidState = HIDMonitor.Access.current() == .granted ? .running : .permissionNeeded
    }

    /// After granting the permission in System Settings the TCC grant only
    /// applies to a fresh process: relaunch (packaged app) or plain restart.
    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]
            try? process.run()
        }
        NSApp.terminate(nil)
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    private func handleHID(_ event: HIDEvent) {
        if case .connection(let up) = event {
            deviceConnected = up
        }
        guard var engine else { return }
        engine.handle(event, at: Date())
        applyEngine(engine)
    }

    private func engineTick() {
        guard var engine else { return }
        engine.tick(at: Date())
        applyEngine(engine)
    }

    private func applyEngine(_ updated: InferenceEngine) {
        engine = updated
        if pinnedLayer == nil {
            if displayedLayer != updated.displayed { displayedLayer = updated.displayed }
        }
        let lit = updated.highlighted
        if highlighted != lit { highlighted = lit }
        scheduleTickIfNeeded(updated.needsTick)
    }

    /// A light repeating timer runs only while the engine has decaying state.
    private func scheduleTickIfNeeded(_ needed: Bool) {
        if needed, tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.engineTick() }
            }
        } else if !needed, let timer = tickTimer {
            timer.invalidate()
            tickTimer = nil
        }
    }
}
