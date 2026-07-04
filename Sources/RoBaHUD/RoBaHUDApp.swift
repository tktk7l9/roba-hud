import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            exit(SelfTest.run())
        }
        if let idx = args.firstIndex(of: "--parse-check") {
            let path = args.indices.contains(idx + 1) && !args[idx + 1].hasPrefix("-")
                ? args[idx + 1] : Prefs.keymapURL.path
            exit(ParseCheck.run(path: path))
        }
        if args.contains("--hid-dump") {
            exit(HIDDump.run())
        }
        if args.contains("--battery-dump") {
            exit(BatteryDump.run())
        }
        if args.contains("--regen-cheatsheet") {
            exit(CheatsheetCLI.run())
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = PanelController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            controller?.store.statsStore.flush()
            controller?.store.insightsStore.flush()
            controller?.store.battery.flush()
        }
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let store = HUDStore()
    private var panel: HUDPanel?
    private var hostingView: NSView?
    private var batteryStatusItem: BatteryStatusItem?
    private var hotKey: HotKey?

    override init() {
        super.init()
        store.loadAll()
        store.startMonitoring()
        store.startWatching()
        store.battery.start()
        let hosting = NSHostingView(rootView: HUDView(store: store))
        let panel = HUDPanel(contentView: hosting)
        panel.delegate = self
        panel.center()
        // setFrameAutosaveName restores the last frame if one was saved;
        // center() above only matters on first launch.
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hosting
        batteryStatusItem = BatteryStatusItem(
            battery: store.battery,
            showPanel: { [weak self] in self?.panel?.orderFrontRegardless() },
            hidePanel: { [weak self] in self?.panel?.orderOut(nil) },
            isPanelVisible: { [weak self] in self?.panel?.isVisible ?? false },
            isClickThrough: { [weak self] in self?.store.clickThrough ?? false },
            setClickThrough: { [weak self] on in self?.store.setClickThrough(on) }
        )
        // ⌥⌘K: show/hide the HUD from anywhere (no TCC needed — Carbon hotkey).
        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated { self?.togglePanelVisibility() }
        }
        observeOpacity()
        observePanelBehavior()
    }

    func togglePanelVisibility() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Click-through and compact mode need AppKit-side application.
    private func observePanelBehavior() {
        withObservationTracking {
            _ = store.clickThrough
            _ = store.editMode
            _ = store.compactMode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                // Edit mode must stay clickable even with click-through on.
                panel.ignoresMouseEvents = self.store.clickThrough && !self.store.editMode
                // Snap the frame to the new content size when toggling compact.
                if let hosting = self.hostingView {
                    let fitting = hosting.fittingSize
                    if self.store.compactMode {
                        var frame = panel.frame
                        let newHeight = fitting.height + 28   // titlebar allowance
                        frame.origin.y += frame.height - newHeight
                        frame.size = NSSize(width: max(fitting.width, 460), height: newHeight)
                        panel.setFrame(frame, display: true, animate: false)
                    }
                }
                self.observePanelBehavior()
            }
        }
    }

    /// Panel alpha follows the opacity preference.
    private func observeOpacity() {
        withObservationTracking {
            _ = store.opacity
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel?.alphaValue = self.store.opacity
                self.observeOpacity()
            }
        }
    }

    // With the menu-bar battery item installed, closing the panel just hides
    // it (the app stays reachable from the menu bar). Without it, the HUD is
    // the only surface, so closing quits as before.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if batteryStatusItem?.isInstalled == true {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

/// CLI: regenerate the layer diagrams in zmk-config's CHEATSHEET.md.
///   swift run RoBaHUD --regen-cheatsheet
enum CheatsheetCLI {
    static func run() -> Int32 {
        do {
            let source = try String(contentsOf: Prefs.keymapURL, encoding: .utf8)
            let keymap = try KeymapParser.parse(source: source, fileURL: Prefs.keymapURL)
            let geometry = try GeometryLoader.load(json: Data(contentsOf: Prefs.layoutJSONURL))
            let url = URL(fileURLWithPath: Prefs.zmkConfigPath).appendingPathComponent("CHEATSHEET.md")
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let date = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
            guard let updated = CheatsheetGenerator.regenerate(markdown: markdown, keymap: keymap,
                                                               geometry: geometry, date: date) else {
                print("CHEATSHEET.md は最新です")
                return 0
            }
            try Data(updated.utf8).write(to: url, options: .atomic)
            print("regenerated: \(url.path)")
            return 0
        } catch {
            print("ERROR: \(error)")
            return 1
        }
    }
}

/// CLI: parse a keymap file and print a summary (or the error). Exit 0/1.
///   swift run RoBaHUD --parse-check [path]
enum ParseCheck {
    static func run(path: String) -> Int32 {
        do {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let keymap = try KeymapParser.parse(source: source)
            print("OK: \(path)")
            for layer in keymap.layers {
                let locked = layer.bindings.filter { !$0.binding.isEditable }.count
                print(String(format: "  L%d %-8s %d bindings%@",
                             layer.index, (layer.name as NSString).utf8String!,
                             layer.bindings.count,
                             locked > 0 ? " (編集不可: \(locked))" : ""))
            }
            return 0
        } catch {
            print("PARSE ERROR: \(error)")
            return 1
        }
    }
}
