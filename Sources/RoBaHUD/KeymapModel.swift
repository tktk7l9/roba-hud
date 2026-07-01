import Foundation

/// One binding slot in a ZMK keymap layer.
enum KeyBinding: Equatable {
    case kp(Keycode)
    case lt(layer: Int, tap: Keycode)
    case mt(hold: Keycode, tap: Keycode)
    case mo(Int)
    case to(Int)
    case tog(Int)
    case mkp(Int)                       // mouse button 1...5
    case bt(command: String, param: Int?)
    case out(String)
    case capsWord
    case transparent
    case none
    case bootloader
    case sysReset
    /// Anything we don't model (custom behaviors like &bt_clr_hold).
    /// Rendered, never editable.
    case opaque(behavior: String, params: [String])

    /// Canonical dts serialization. For every binding parsed from the current
    /// keymap this reproduces the source token byte-exactly (single internal
    /// spaces — verified by selftest).
    var dtsText: String {
        switch self {
        case .kp(let code): "&kp \(code.dtsText)"
        case .lt(let layer, let tap): "&lt \(layer) \(tap.dtsText)"
        case .mt(let hold, let tap): "&mt \(hold.dtsText) \(tap.dtsText)"
        case .mo(let n): "&mo \(n)"
        case .to(let n): "&to \(n)"
        case .tog(let n): "&tog \(n)"
        case .mkp(let n): "&mkp MB\(n)"
        case .bt(let cmd, let param): param.map { "&bt \(cmd) \($0)" } ?? "&bt \(cmd)"
        case .out(let s): "&out \(s)"
        case .capsWord: "&caps_word"
        case .transparent: "&trans"
        case .none: "&none"
        case .bootloader: "&bootloader"
        case .sysReset: "&sys_reset"
        case .opaque(let behavior, let params):
            (["&\(behavior)"] + params).joined(separator: " ")
        }
    }

    var isEditable: Bool {
        if case .opaque = self { return false }
        return true
    }
}

/// A binding plus where it lives in the source file. `charRange` is the
/// trimmed token span as Character offsets into the original source string.
struct ParsedBinding {
    let binding: KeyBinding
    let charRange: Range<Int>
    let raw: String
}

struct Layer {
    let index: Int
    let name: String            // display-name, fallback node name
    let nodeName: String
    let bindings: [ParsedBinding]
}

struct Keymap {
    let layers: [Layer]
    let sourceText: String
    let fileURL: URL?

    /// Resolve &trans down to the base layer so every (layer, position) has a
    /// concrete binding to label and reverse-index.
    func effective(layer: Int, position: Int) -> KeyBinding {
        var current = layer
        while current >= 0 {
            let binding = layers[current].bindings[position].binding
            if case .transparent = binding, current != 0 {
                current = 0     // roBa has no intermediate fallthrough chain
                continue
            }
            return binding
        }
        return .none
    }

    func layerName(_ index: Int) -> String {
        layers.indices.contains(index) ? layers[index].name : "L\(index)"
    }
}

/// Tap/hold display faces for a keycap.
struct KeyLabel {
    let tap: String
    let hold: String?
    let dimmed: Bool            // &trans / &none render dimmed

    init(_ tap: String, hold: String? = nil, dimmed: Bool = false) {
        self.tap = tap
        self.hold = hold
        self.dimmed = dimmed
    }
}

enum LabelProvider {
    static func label(for binding: KeyBinding, in keymap: Keymap?) -> KeyLabel {
        func layerName(_ n: Int) -> String { keymap?.layerName(n) ?? "L\(n)" }
        switch binding {
        case .kp(let code):
            return KeyLabel(code.label)
        case .lt(let layer, let tap):
            return KeyLabel(tap.label, hold: "▷\(layerName(layer))")
        case .mt(let hold, let tap):
            return KeyLabel(tap.label, hold: hold.label)
        case .mo(let n):
            return KeyLabel("▷\(layerName(n))")
        case .to(let n):
            return KeyLabel("→\(layerName(n))")
        case .tog(let n):
            return KeyLabel("⇄\(layerName(n))")
        case .mkp(let n):
            return KeyLabel("M\(n)")
        case .bt(let cmd, let param):
            if cmd == "BT_SEL", let p = param { return KeyLabel("BT\(p)") }
            if cmd == "BT_CLR" { return KeyLabel("BT✕") }
            return KeyLabel(cmd)
        case .out:
            return KeyLabel("OUT")
        case .capsWord:
            return KeyLabel("CW")
        case .transparent:
            return KeyLabel("▽", dimmed: true)
        case .none:
            return KeyLabel("—", dimmed: true)
        case .bootloader:
            return KeyLabel("BOOT")
        case .sysReset:
            return KeyLabel("RST")
        case .opaque(let behavior, _):
            if behavior == "bt_clr_hold" { return KeyLabel("", hold: "BT✕") }
            return KeyLabel(behavior)
        }
    }
}
