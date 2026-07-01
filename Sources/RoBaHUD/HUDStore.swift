import Foundation
import Observation

/// Central app state: keymap + geometry, displayed layer, live highlights.
@MainActor
@Observable
final class HUDStore {
    var keymap: Keymap?
    var geometry: [KeyGeometry] = []
    var layoutBounds = LayoutBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)
    var loadError: String?

    /// The layer currently rendered.
    var displayedLayer = 0
    /// Manual pin: while set, inference (M3) must not change displayedLayer.
    var pinnedLayer: Int?

    /// Positions (0-based binding indices) currently lit, on the displayed layer.
    var highlighted: Set<Int> = []

    var opacity: Double = Prefs.opacity {
        didSet { Prefs.opacity = opacity }
    }

    init() {}

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
        } catch {
            loadError = "keymap 読込失敗: \(error)"
        }
    }

    func selectLayer(_ index: Int) {
        guard let keymap, keymap.layers.indices.contains(index) else { return }
        displayedLayer = index
        pinnedLayer = pinnedLayer == nil ? nil : index
    }

    func togglePin() {
        pinnedLayer = pinnedLayer == nil ? displayedLayer : nil
    }
}
