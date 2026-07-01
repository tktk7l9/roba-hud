import Foundation

/// Physical position of one key, in key units (1u = one keycap), parsed from
/// config/roBa.json (QMK info.json style, KLE rotation semantics: the key at
/// (x, y) is rotated r degrees clockwise around (rx, ry)).
struct KeyGeometry: Identifiable {
    let index: Int
    let row: Int
    let col: Int
    let x, y: Double
    let rotation: Double
    let rx, ry: Double

    var id: Int { index }

    /// Center after rotation, in key units. (For roBa every rotated key's
    /// rotation origin equals its own center, but compute generally.)
    var center: (x: Double, y: Double) {
        let cx = x + 0.5, cy = y + 0.5
        guard rotation != 0 else { return (cx, cy) }
        let rad = rotation * .pi / 180
        let dx = cx - rx, dy = cy - ry
        return (rx + dx * cos(rad) - dy * sin(rad),
                ry + dx * sin(rad) + dy * cos(rad))
    }

    /// The 4 corners after rotation (for bounding-box computation).
    var corners: [(x: Double, y: Double)] {
        let pts = [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]
        guard rotation != 0 else { return pts }
        let rad = rotation * .pi / 180
        return pts.map { p in
            let dx = p.0 - rx, dy = p.1 - ry
            return (rx + dx * cos(rad) - dy * sin(rad),
                    ry + dx * sin(rad) + dy * cos(rad))
        }
    }
}

struct LayoutBounds {
    let minX, minY, maxX, maxY: Double
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
}

enum GeometryLoader {
    struct LayoutFile: Decodable {
        let layouts: [String: LayoutDef]
    }
    struct LayoutDef: Decodable {
        let layout: [RawKey]
    }
    struct RawKey: Decodable {
        let row: Int
        let col: Int
        let x: Double
        let y: Double
        let r: Double?
        let rx: Double?
        let ry: Double?
    }

    static func load(json: Data) throws -> [KeyGeometry] {
        let file = try JSONDecoder().decode(LayoutFile.self, from: json)
        guard let def = file.layouts["default_layout"] ?? file.layouts.values.first else {
            throw ParseError(message: "roBa.json に layout が見つかりません")
        }
        return def.layout.enumerated().map { index, raw in
            KeyGeometry(index: index, row: raw.row, col: raw.col,
                        x: raw.x, y: raw.y,
                        rotation: raw.r ?? 0,
                        rx: raw.rx ?? raw.x + 0.5, ry: raw.ry ?? raw.y + 0.5)
        }
    }

    static func bounds(of keys: [KeyGeometry]) -> LayoutBounds {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for key in keys {
            for corner in key.corners {
                minX = min(minX, corner.x); maxX = max(maxX, corner.x)
                minY = min(minY, corner.y); maxY = max(maxY, corner.y)
            }
        }
        return LayoutBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
