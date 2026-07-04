import Foundation

/// Regenerates the layer diagrams inside zmk-config-roBa's CHEATSHEET.md.
///
/// The hand-written prose is preserved: for each `## Layer N …` heading only
/// the first fenced code block after it (the ASCII grid) is replaced, and the
/// `> 最終更新:` line is refreshed. No markers needed.
enum CheatsheetGenerator {

    /// Short label for one binding in the grid.
    static func shortLabel(_ binding: KeyBinding) -> String {
        switch binding {
        case .kp(let code): code.label
        case .lt(_, let tap), .customLt(_, _, let tap): tap.label + "*"
        case .mt(_, let tap): tap.label + "*"
        case .mo(let n), .customMo(_, let n): "▷\(n)"
        case .to(let n): "→\(n)"
        case .tog(let n): "⇄\(n)"
        case .mkp(let n): "M\(n)"
        case .bt(let cmd, let param):
            cmd == "BT_CLR" ? "BT✕" : "BT\(param ?? 0)"
        case .out: "OUT"
        case .capsWord: "CW"
        case .transparent: "─"
        case .none: "✕"
        case .bootloader: "BOOT"
        case .sysReset: "RST"
        case .opaque(let behavior, _): opaqueLabel(behavior)
        }
    }

    private static func opaqueLabel(_ behavior: String) -> String {
        if behavior == "bt_clr_hold" { return "BTclr*" }
        if behavior.hasPrefix("bt_sel_m"), let n = Int(behavior.dropFirst("bt_sel_m".count)) {
            return "BT\(n)"
        }
        return behavior
    }

    /// The ASCII grid for one layer: rows of padded cells, split-halves
    /// separated by "│" (left = cols ≤ 5, right = cols ≥ 8 in roBa.json).
    static func diagram(layer: Layer, geometry: [KeyGeometry]) -> String {
        let byRow = Dictionary(grouping: geometry.indices, by: { geometry[$0].row })
        var lines: [String] = []
        for row in byRow.keys.sorted() {
            let indices = byRow[row]!.sorted { geometry[$0].col < geometry[$1].col }
            var left: [String] = []
            var right: [String] = []
            for index in indices {
                let label = shortLabel(layer.bindings[index].binding)
                if geometry[index].col <= 5 {
                    left.append(label)
                } else {
                    right.append(label)
                }
            }
            let pad = { (cell: String) -> String in
                cell.count >= 5 ? cell : cell + String(repeating: " ", count: 5 - cell.count)
            }
            lines.append((left.map(pad).joined(separator: " ") + "│ "
                          + right.map(pad).joined(separator: " "))
                .trimmingCharacters(in: .whitespaces))
        }
        return lines.joined(separator: "\n")
    }

    /// All layer diagrams keyed by layer index.
    static func diagrams(keymap: Keymap, geometry: [KeyGeometry]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: keymap.layers.map {
            ($0.index, diagram(layer: $0, geometry: geometry))
        })
    }

    /// Splice generated diagrams into the existing markdown. For each layer,
    /// find `## Layer N` and replace the contents of the first ``` fence pair
    /// after it. Unmatched layers are left untouched (best effort).
    static func splice(markdown: String, diagrams: [Int: String], dateLine: String? = nil) -> String {
        var lines = markdown.components(separatedBy: "\n")

        if let dateLine {
            for (i, line) in lines.enumerated() where line.hasPrefix("> 最終更新:") {
                lines[i] = "> 最終更新: \(dateLine)"
                break
            }
        }

        for (layerIndex, diagram) in diagrams.sorted(by: { $0.key < $1.key }) {
            guard let heading = lines.firstIndex(where: {
                $0.hasPrefix("## Layer \(layerIndex) ") || $0 == "## Layer \(layerIndex)"
            }) else { continue }
            guard let open = lines[(heading + 1)...].firstIndex(where: { $0.hasPrefix("```") }),
                  let close = lines[(open + 1)...].firstIndex(where: { $0.hasPrefix("```") }) else {
                continue
            }
            lines.replaceSubrange((open + 1)..<close, with: diagram.components(separatedBy: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    /// Full pipeline: read CHEATSHEET.md, splice, return new content
    /// (nil if unchanged).
    static func regenerate(markdown: String, keymap: Keymap, geometry: [KeyGeometry],
                           date: String) -> String? {
        let updated = splice(markdown: markdown,
                             diagrams: diagrams(keymap: keymap, geometry: geometry),
                             dateLine: "\(date)（roba-hud 自動生成）")
        return updated == markdown ? nil : updated
    }
}
