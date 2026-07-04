import Foundation

/// Firmware→host BT-profile signaling over invisible keyboard usages — the
/// same proven trick as the layer markers (F21–F24). zmk-config-roBa's
/// bt_sel_mN macros tap K_AGAIN+N (0x79+N) after `&bt BT_SEL N` so the newly
/// active host learns its own profile index; bt_clr_macro taps K_FIND (0x7E)
/// right before clearing so the current host can forget its assignment.
/// None of these usages have macOS virtual keycodes: invisible to every app.
enum ProfileMarker: Equatable {
    case selected(Int)
    case cleared

    /// K_AGAIN … K_PASTE = BT0 … BT4.
    static let selectedBase: UInt32 = 0x79
    /// K_FIND.
    static let clearedUsage: UInt32 = 0x7E
    /// ZMK's default profile count.
    static let profileCount = 5

    static func decode(page: UInt32, usage: UInt32) -> ProfileMarker? {
        guard page == 0x07 else { return nil }
        if usage == clearedUsage { return .cleared }
        if usage >= selectedBase, usage < selectedBase + UInt32(profileCount) {
            return .selected(Int(usage - selectedBase))
        }
        return nil
    }
}

/// A BT control bound in the keymap, for the device sheet's key guide.
struct BTAction: Equatable {
    enum Kind: Equatable {
        case select(Int)
        case clear
        case other(String)
    }

    let layer: Int
    let position: Int
    let kind: Kind

    /// Finds plain `&bt …` bindings plus the marker macros (bt_sel_mN) and
    /// the bt_clr_* behaviors, which parse as opaque.
    static func scan(_ keymap: Keymap) -> [BTAction] {
        var actions: [BTAction] = []
        for layer in keymap.layers {
            for (position, parsed) in layer.bindings.enumerated() {
                guard let kind = classify(parsed.binding) else { continue }
                actions.append(BTAction(layer: layer.index, position: position, kind: kind))
            }
        }
        return actions
    }

    static func classify(_ binding: KeyBinding) -> Kind? {
        switch binding {
        case .bt(let command, let param):
            if command == "BT_SEL", let param { return .select(param) }
            if command == "BT_CLR" { return .clear }
            return .other(command)
        case .opaque(let behavior, _):
            if behavior.hasPrefix("bt_sel_m"), let n = Int(behavior.dropFirst("bt_sel_m".count)) {
                return .select(n)
            }
            if behavior.hasPrefix("bt_clr") { return .clear }
            return nil
        default:
            return nil
        }
    }
}
