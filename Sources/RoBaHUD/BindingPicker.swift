import SwiftUI

/// Popover for assigning a new binding to one key position.
struct BindingPicker: View {
    let store: HUDStore
    let position: Int

    private enum BehaviorKind: String, CaseIterable, Identifiable {
        case kp = "キー入力 (&kp)"
        case lt = "レイヤータップ (&lt)"
        case mt = "モッドタップ (&mt)"
        case mo = "レイヤー押下中 (&mo)"
        case to = "レイヤー移動 (&to)"
        case mkp = "マウスボタン (&mkp)"
        case trans = "透過 (&trans)"
        case none = "無効 (&none)"
        var id: String { rawValue }
    }

    @State private var kind: BehaviorKind = .kp
    @State private var search = ""
    @State private var selectedName: String?
    @State private var wrappers: Set<Mod> = []
    @State private var layer = 1
    @State private var holdMod: Mod = .lctl
    @State private var mouseButton = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("キー割り当て変更 — \(currentDescription)")
                .font(.system(size: 11, weight: .semibold))

            Picker("種類", selection: $kind) {
                ForEach(BehaviorKind.allCases) { k in Text(k.rawValue).tag(k) }
            }
            .labelsHidden()

            switch kind {
            case .kp:
                wrapperToggles
                keycodeList
            case .lt:
                layerPicker
                keycodeList
            case .mt:
                Picker("ホールド", selection: $holdMod) {
                    ForEach(Mod.allCases, id: \.self) { mod in
                        Text("\(mod.glyph) \(standaloneName(mod))").tag(mod)
                    }
                }
                keycodeList
            case .mo, .to:
                layerPicker
            case .mkp:
                Picker("ボタン", selection: $mouseButton) {
                    ForEach(1...5, id: \.self) { n in Text("MB\(n)").tag(n) }
                }
            case .trans, .none:
                EmptyView()
            }

            Divider()
            HStack {
                Text(builtBinding?.dtsText ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("適用") {
                    if let binding = builtBinding {
                        store.applyEdit(position: position, binding: binding)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(builtBinding == nil)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear(perform: prefill)
    }

    // MARK: - Pieces

    private var wrapperToggles: some View {
        HStack(spacing: 6) {
            ForEach([Mod.lctl, .lalt, .lsft, .lgui], id: \.self) { mod in
                Toggle(mod.glyph, isOn: Binding(
                    get: { wrappers.contains(mod) },
                    set: { on in if on { wrappers.insert(mod) } else { wrappers.remove(mod) } }
                ))
                .toggleStyle(.button)
                .font(.system(size: 12))
            }
            Spacer()
        }
    }

    private var layerPicker: some View {
        Picker("レイヤー", selection: $layer) {
            if let keymap = store.keymap {
                ForEach(keymap.layers, id: \.index) { l in
                    Text("\(l.index): \(l.name)").tag(l.index)
                }
            }
        }
    }

    private var keycodeList: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("検索 (例: ESC, かな, F5)", text: $search)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredEntries, id: \.canonicalName) { entry in
                        Button {
                            selectedName = entry.canonicalName
                        } label: {
                            HStack {
                                Text(entry.glyph).frame(width: 44, alignment: .leading)
                                Text(entry.canonicalName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.category.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(selectedName == entry.canonicalName
                                        ? Color.accentColor.opacity(0.25) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private var filteredEntries: [KeycodeEntry] {
        let all = KeycodeTable.entries
        guard !search.isEmpty else { return all }
        let q = search.uppercased()
        return all.filter { entry in
            entry.names.contains { $0.contains(q) } || entry.glyph.contains(search)
        }
    }

    // MARK: - Binding construction

    private var selectedKeycode: Keycode? {
        guard let name = selectedName, let entry = KeycodeTable.byName[name] else { return nil }
        return Keycode(entry: entry, nameUsed: name,
                       wrappers: kind == .kp ? orderedWrappers : [])
    }

    /// Wrapper serialization order: outermost ⌃, then ⌥, ⇧, innermost ⌘…
    /// order is cosmetic; pick display rank for stability.
    private var orderedWrappers: [Mod] {
        wrappers.sorted { $0.displayRank < $1.displayRank }
    }

    private var builtBinding: KeyBinding? {
        switch kind {
        case .kp: selectedKeycode.map { .kp($0) }
        case .lt: selectedKeycode.map { .lt(layer: layer, tap: $0) }
        case .mt: selectedKeycode.map { code in
            .mt(hold: Keycode(entry: KeycodeTable.byName[standaloneName(holdMod)]!), tap: code)
        }
        case .mo: .mo(layer)
        case .to: .to(layer)
        case .mkp: .mkp(mouseButton)
        case .trans: .transparent
        case .none: KeyBinding.none
        }
    }

    private func standaloneName(_ mod: Mod) -> String {
        switch mod {
        case .lctl: "LCTRL"
        case .lsft: "LSHFT"
        case .lalt: "LALT"
        case .lgui: "LGUI"
        case .rctl: "RCTRL"
        case .rsft: "RSHFT"
        case .ralt: "RALT"
        case .rgui: "RGUI"
        }
    }

    private var currentDescription: String {
        guard let keymap = store.keymap else { return "" }
        let binding = keymap.layers[store.displayedLayer].bindings[position].binding
        return "\(keymap.layerName(store.displayedLayer))[\(position)] 現在: \(binding.dtsText)"
    }

    /// Prefill the form from the current binding.
    private func prefill() {
        guard let keymap = store.keymap else { return }
        switch keymap.layers[store.displayedLayer].bindings[position].binding {
        case .kp(let code):
            kind = .kp
            selectedName = code.nameUsed
            wrappers = Set(code.wrappers)
        case .lt(let l, let tap):
            kind = .lt
            layer = l
            selectedName = tap.nameUsed
        case .mt(let hold, let tap):
            kind = .mt
            if let mod = Mod.fromUsage(hold.entry.usage) { holdMod = mod }
            selectedName = tap.nameUsed
        case .mo(let l): kind = .mo; layer = l
        case .to(let l): kind = .to; layer = l
        case .mkp(let n): kind = .mkp; mouseButton = n
        case .transparent: kind = .trans
        case .none: kind = .none
        default: kind = .kp
        }
    }
}
