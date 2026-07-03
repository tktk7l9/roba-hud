import AppKit
import Foundation

/// Pure label builder for the menu-bar battery display (selftest-able).
enum BatteryMenuBarLabel {
    struct Line: Equatable {
        let text: String                    // "R\t85%" (tab = right-aligned column)
        let severity: BatterySeverity?      // nil = unknown level
    }

    static func lines(levels: BatteryLevels) -> [Line] {
        [line(prefix: "R", level: levels.level(of: .central)),
         line(prefix: "L", level: levels.level(of: .peripheral(0)))]
    }

    private static func line(prefix: String, level: Int?) -> Line {
        guard let level else { return Line(text: "\(prefix)\t–", severity: nil) }
        return Line(text: "\(prefix)\t\(level)%", severity: BatterySeverity.of(level: level))
    }
}

/// NSStatusItem showing both halves' battery levels in the macOS menu bar
/// (zmk-battery-center's tray display). Two-line rendering follows the
/// claude-usage-bar pattern: the attributed string is rasterized to an image
/// so both lines fit and stay vertically centered.
@MainActor
final class BatteryStatusItem: NSObject, NSMenuDelegate {
    private let battery: BatteryCenter
    private let showPanel: () -> Void
    private let hidePanel: () -> Void
    private let isPanelVisible: () -> Bool
    private var statusItem: NSStatusItem?

    var isInstalled: Bool { statusItem != nil }

    init(battery: BatteryCenter,
         showPanel: @escaping () -> Void,
         hidePanel: @escaping () -> Void,
         isPanelVisible: @escaping () -> Bool) {
        self.battery = battery
        self.showPanel = showPanel
        self.hidePanel = hidePanel
        self.isPanelVisible = isPanelVisible
        super.init()
        if battery.menuBarEnabled { install() }
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = battery.levels
            _ = battery.menuBarEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.battery.menuBarEnabled { self.install() } else { self.remove() }
                self.render()
                self.observe()
            }
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.lineBreakMode = .byWordWrapping
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        render()
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: - Rendering

    private static let fontSize: CGFloat = 11
    private static let lineHeight: CGFloat = 11
    private static let verticalNudge: CGFloat = 3.0
    private static var font: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold) }

    private func render() {
        guard let button = statusItem?.button else { return }
        button.image = Self.image(Self.attributed(BatteryMenuBarLabel.lines(levels: battery.levels)))
        button.imagePosition = .imageOnly
    }

    private static func color(for severity: BatterySeverity?) -> NSColor {
        switch severity {
        case .ok: .labelColor
        case .low: .systemOrange
        case .critical: .systemRed
        case nil: .secondaryLabelColor
        }
    }

    private static func attributed(_ lines: [BatteryMenuBarLabel.Line]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = 0
        paragraph.maximumLineHeight = lineHeight
        paragraph.minimumLineHeight = lineHeight
        let labelWidth = ("L" as NSString).size(withAttributes: [.font: font]).width
        let valueWidth = ("100%" as NSString).size(withAttributes: [.font: font]).width
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(labelWidth + 1 + valueWidth))]

        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let text = index == lines.count - 1 ? line.text : line.text + "\n"
            result.append(NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color(for: line.severity),
                .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    /// Rasterize so two 11pt lines center correctly in the ~22pt menu bar
    /// (text titles sit high; images are centered by AppKit).
    private static func image(_ attributed: NSAttributedString) -> NSImage {
        let width = ceil(attributed.size().width)
        let height = NSStatusBar.system.thickness
        let cap = font.capHeight
        let ascent = font.ascender
        let inkTop = (height - (lineHeight + cap)) / 2
        let y0 = inkTop - (ascent - cap) + verticalNudge

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            attributed.draw(in: NSRect(x: 0, y: y0, width: width, height: lineHeight * 2 + 6))
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for role in [BatteryRole.central, .peripheral(0)] {
            let level = battery.levels.level(of: role)
            let item = NSMenuItem(title: "\(role.displayName)手側: \(level.map { "\($0)%" } ?? "—")",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let updated = battery.levels.updatedAt {
            let item = NSMenuItem(title: "更新 \(updated.formatted(date: .omitted, time: .shortened))",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: isPanelVisible() ? "HUD を隠す" : "HUD を表示",
                                action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let detail = NSMenuItem(title: "バッテリー詳細…", action: #selector(openDetail), keyEquivalent: "")
        detail.target = self
        menu.addItem(detail)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func togglePanel() {
        if isPanelVisible() {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @objc private func openDetail() {
        showPanel()
        battery.showSheet = true
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
