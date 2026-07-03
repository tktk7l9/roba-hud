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
            controller?.store.battery.flush()
        }
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let store = HUDStore()
    private var panel: HUDPanel?
    private var batteryStatusItem: BatteryStatusItem?

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
        batteryStatusItem = BatteryStatusItem(
            battery: store.battery,
            showPanel: { [weak self] in self?.panel?.orderFrontRegardless() },
            hidePanel: { [weak self] in self?.panel?.orderOut(nil) },
            isPanelVisible: { [weak self] in self?.panel?.isVisible ?? false }
        )
        observeOpacity()
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

/// CLI: parse a keymap file and print a summary (or the error). Exit 0/1.
///   swift run RoBaHUD --parse-check [path]
enum ParseCheck {
    static func run(path: String) -> Int32 {
        do {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let keymap = try KeymapParser.parse(source: source)
            print("OK: \(path)")
            for layer in keymap.layers {
                let opaques = layer.bindings.filter { !$0.binding.isEditable }.count
                print(String(format: "  L%d %-8s %d bindings%@",
                             layer.index, (layer.name as NSString).utf8String!,
                             layer.bindings.count,
                             opaques > 0 ? " (opaque: \(opaques))" : ""))
            }
            return 0
        } catch {
            print("PARSE ERROR: \(error)")
            return 1
        }
    }
}
