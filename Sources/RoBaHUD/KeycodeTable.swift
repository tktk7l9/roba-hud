import Foundation

/// HID modifier bits / ZMK modifier functions (LS(...) etc.) and standalone
/// modifier keycodes (LSHFT etc.).
enum Mod: String, CaseIterable, Equatable {
    case lctl = "LC", lsft = "LS", lalt = "LA", lgui = "LG"
    case rctl = "RC", rsft = "RS", ralt = "RA", rgui = "RG"

    /// HID usage on page 0x07 (0xE0–0xE7).
    var usage: UInt32 {
        switch self {
        case .lctl: 0xE0
        case .lsft: 0xE1
        case .lalt: 0xE2
        case .lgui: 0xE3
        case .rctl: 0xE4
        case .rsft: 0xE5
        case .ralt: 0xE6
        case .rgui: 0xE7
        }
    }

    var glyph: String {
        switch self {
        case .lctl, .rctl: "⌃"
        case .lalt, .ralt: "⌥"
        case .lsft, .rsft: "⇧"
        case .lgui, .rgui: "⌘"
        }
    }

    /// Apple's canonical modifier display order: ⌃ ⌥ ⇧ ⌘.
    var displayRank: Int {
        switch self {
        case .lctl, .rctl: 0
        case .lalt, .ralt: 1
        case .lsft, .rsft: 2
        case .lgui, .rgui: 3
        }
    }

    static func fromUsage(_ usage: UInt32) -> Mod? {
        allCases.first { $0.usage == usage }
    }

    static func wrapper(_ name: String) -> Mod? {
        Mod(rawValue: name)
    }
}

enum KeycodeCategory: String, CaseIterable {
    case letter = "英字"
    case digit = "数字"
    case symbol = "記号"
    case control = "制御"
    case navigation = "移動"
    case function = "F/特殊"
    case keypad = "テンキー"
    case media = "メディア"
    case japanese = "日本語"
    case modifier = "修飾"
}

/// One row of the static ZMK keycode table. `names[0]` is the canonical
/// spelling; the rest are ZMK aliases that parse to the same key.
struct KeycodeEntry {
    let names: [String]
    let page: UInt32          // 0x07 keyboard, 0x0C consumer
    let usage: UInt32
    let implicitMods: [Mod]   // shifted aliases like PERCENT = LS + N5
    let glyph: String
    let category: KeycodeCategory

    var canonicalName: String { names[0] }
}

/// A concrete keycode expression as written in a keymap: an entry plus any
/// explicit modifier wrappers, e.g. LG(LS(N4)) = entry N4, wrappers [LG, LS]
/// (outermost first). `nameUsed` preserves the alias spelling for byte-exact
/// round-trips.
struct Keycode: Equatable {
    let entry: KeycodeEntry
    let nameUsed: String
    let wrappers: [Mod]

    static func == (lhs: Keycode, rhs: Keycode) -> Bool {
        lhs.entry.canonicalName == rhs.entry.canonicalName
            && lhs.nameUsed == rhs.nameUsed
            && lhs.wrappers == rhs.wrappers
    }

    init(entry: KeycodeEntry, nameUsed: String? = nil, wrappers: [Mod] = []) {
        self.entry = entry
        self.nameUsed = nameUsed ?? entry.canonicalName
        self.wrappers = wrappers
    }

    /// All modifiers this keycode implies when sent: explicit wrappers plus
    /// the implicit mods of shifted aliases.
    var effectiveMods: [Mod] { wrappers + entry.implicitMods }

    /// The dts text with wrappers rebuilt outermost-first, e.g. "LG(LS(N4))".
    var dtsText: String {
        var text = nameUsed
        for mod in wrappers.reversed() {
            text = "\(mod.rawValue)(\(text))"
        }
        return text
    }

    /// Display label, e.g. "⌃⇧⌘4" for LC(LG(LS(N4))).
    var label: String {
        let mods = wrappers.sorted { $0.displayRank < $1.displayRank }
        return mods.map(\.glyph).joined() + entry.glyph
    }
}

enum KeycodeTable {
    /// All known entries. Sized for this keymap plus a sensible picker set.
    static let entries: [KeycodeEntry] = {
        var rows: [KeycodeEntry] = []
        func add(_ names: [String], _ page: UInt32, _ usage: UInt32, _ glyph: String,
                 _ category: KeycodeCategory, mods: [Mod] = []) {
            rows.append(KeycodeEntry(names: names, page: page, usage: usage,
                                     implicitMods: mods, glyph: glyph, category: category))
        }

        // Letters A–Z (page 7, 0x04–0x1D)
        for (i, ch) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            add([String(ch)], 0x07, UInt32(0x04 + i), String(ch), .letter)
        }
        // Digits N1–N9, N0 (0x1E–0x27)
        for i in 1...9 {
            add(["N\(i)", "NUMBER_\(i)"], 0x07, UInt32(0x1E + i - 1), "\(i)", .digit)
        }
        add(["N0", "NUMBER_0"], 0x07, 0x27, "0", .digit)

        // Control
        add(["ENTER", "RET", "RETURN"], 0x07, 0x28, "⏎", .control)
        add(["ESC", "ESCAPE"], 0x07, 0x29, "⎋", .control)
        add(["BSPC", "BACKSPACE"], 0x07, 0x2A, "⌫", .control)
        add(["TAB"], 0x07, 0x2B, "⇥", .control)
        add(["SPACE"], 0x07, 0x2C, "␣", .control)
        add(["CAPS", "CAPSLOCK", "CLCK"], 0x07, 0x39, "⇪", .control)

        // Punctuation (unshifted)
        add(["MINUS"], 0x07, 0x2D, "-", .symbol)
        add(["EQUAL"], 0x07, 0x2E, "=", .symbol)
        add(["LBKT", "LEFT_BRACKET"], 0x07, 0x2F, "[", .symbol)
        add(["RBKT", "RIGHT_BRACKET"], 0x07, 0x30, "]", .symbol)
        add(["BSLH", "BACKSLASH"], 0x07, 0x31, "\\", .symbol)
        add(["NON_US_HASH"], 0x07, 0x32, "#", .symbol)
        add(["SEMI", "SEMICOLON"], 0x07, 0x33, ";", .symbol)
        add(["SQT", "APOSTROPHE", "APOS"], 0x07, 0x34, "'", .symbol)
        add(["GRAVE"], 0x07, 0x35, "`", .symbol)
        add(["COMMA"], 0x07, 0x36, ",", .symbol)
        add(["DOT", "PERIOD"], 0x07, 0x37, ".", .symbol)
        add(["FSLH", "SLASH"], 0x07, 0x38, "/", .symbol)

        // Shifted aliases: implicit LSHFT over a base usage.
        add(["EXCL", "EXCLAMATION"], 0x07, 0x1E, "!", .symbol, mods: [.lsft])   // ⇧1
        add(["AT_SIGN", "AT"], 0x07, 0x1F, "@", .symbol, mods: [.lsft])          // ⇧2
        add(["HASH", "POUND"], 0x07, 0x20, "#", .symbol, mods: [.lsft])          // ⇧3
        add(["DOLLAR", "DLLR"], 0x07, 0x21, "$", .symbol, mods: [.lsft])         // ⇧4
        add(["PERCENT", "PRCNT"], 0x07, 0x22, "%", .symbol, mods: [.lsft])       // ⇧5
        add(["CARET"], 0x07, 0x23, "^", .symbol, mods: [.lsft])                  // ⇧6
        add(["AMPERSAND", "AMPS"], 0x07, 0x24, "&", .symbol, mods: [.lsft])      // ⇧7
        add(["ASTERISK", "ASTRK", "STAR"], 0x07, 0x25, "*", .symbol, mods: [.lsft]) // ⇧8
        add(["LEFT_PARENTHESIS", "LPAR"], 0x07, 0x26, "(", .symbol, mods: [.lsft])  // ⇧9
        add(["RIGHT_PARENTHESIS", "RPAR"], 0x07, 0x27, ")", .symbol, mods: [.lsft]) // ⇧0
        add(["UNDER", "UNDERSCORE"], 0x07, 0x2D, "_", .symbol, mods: [.lsft])
        add(["PLUS"], 0x07, 0x2E, "+", .symbol, mods: [.lsft])
        add(["LEFT_BRACE", "LBRC"], 0x07, 0x2F, "{", .symbol, mods: [.lsft])
        add(["RIGHT_BRACE", "RBRC"], 0x07, 0x30, "}", .symbol, mods: [.lsft])
        add(["PIPE"], 0x07, 0x31, "|", .symbol, mods: [.lsft])
        add(["TILDE"], 0x07, 0x35, "~", .symbol, mods: [.lsft])
        add(["COLON"], 0x07, 0x33, ":", .symbol, mods: [.lsft])
        add(["DQT", "DOUBLE_QUOTES"], 0x07, 0x34, "\"", .symbol, mods: [.lsft])
        add(["LESS_THAN", "LT"], 0x07, 0x36, "<", .symbol, mods: [.lsft])
        add(["GREATER_THAN", "GT"], 0x07, 0x37, ">", .symbol, mods: [.lsft])
        add(["QMARK", "QUESTION"], 0x07, 0x38, "?", .symbol, mods: [.lsft])

        // Function keys
        for i in 1...12 {
            add(["F\(i)"], 0x07, UInt32(0x3A + i - 1), "F\(i)", .function)
        }
        add(["PSCRN", "PRINTSCREEN"], 0x07, 0x46, "PrSc", .function)
        add(["INS", "INSERT"], 0x07, 0x49, "Ins", .navigation)

        // Navigation / editing
        add(["HOME"], 0x07, 0x4A, "↖", .navigation)
        add(["PG_UP", "PAGE_UP"], 0x07, 0x4B, "⇞", .navigation)
        add(["DEL", "DELETE"], 0x07, 0x4C, "⌦", .control)
        add(["END"], 0x07, 0x4D, "↘", .navigation)
        add(["PG_DN", "PAGE_DOWN"], 0x07, 0x4E, "⇟", .navigation)
        add(["RIGHT", "RIGHT_ARROW"], 0x07, 0x4F, "→", .navigation)
        add(["LEFT", "LEFT_ARROW"], 0x07, 0x50, "←", .navigation)
        add(["DOWN", "DOWN_ARROW"], 0x07, 0x51, "↓", .navigation)
        add(["UP", "UP_ARROW"], 0x07, 0x52, "↑", .navigation)

        // Keypad
        add(["KP_DIVIDE", "KP_SLASH"], 0x07, 0x54, "/", .keypad)
        add(["KP_MULTIPLY", "KP_ASTERISK"], 0x07, 0x55, "×", .keypad)
        add(["KP_MINUS", "KP_SUBTRACT"], 0x07, 0x56, "−", .keypad)
        add(["KP_PLUS"], 0x07, 0x57, "+", .keypad)
        add(["KP_ENTER"], 0x07, 0x58, "⏎", .keypad)
        for i in 1...9 {
            add(["KP_N\(i)", "KP_NUMBER_\(i)"], 0x07, UInt32(0x59 + i - 1), "\(i)", .keypad)
        }
        add(["KP_N0", "KP_NUMBER_0"], 0x07, 0x62, "0", .keypad)
        add(["KP_DOT"], 0x07, 0x63, ".", .keypad)

        // Japanese IME keys
        add(["LANG1", "INT_KANA"], 0x07, 0x90, "かな", .japanese)
        add(["LANG2", "INT_MUHENKAN"], 0x07, 0x91, "英数", .japanese)

        // Modifiers (standalone keycodes)
        add(["LCTRL", "LEFT_CONTROL", "LCTL"], 0x07, 0xE0, "⌃", .modifier)
        add(["LSHFT", "LEFT_SHIFT", "LSHIFT"], 0x07, 0xE1, "⇧", .modifier)
        add(["LALT", "LEFT_ALT"], 0x07, 0xE2, "⌥", .modifier)
        add(["LGUI", "LEFT_GUI", "LCMD", "LEFT_COMMAND", "LWIN"], 0x07, 0xE3, "⌘", .modifier)
        add(["RCTRL", "RIGHT_CONTROL", "RCTL"], 0x07, 0xE4, "⌃", .modifier)
        add(["RSHFT", "RIGHT_SHIFT", "RSHIFT"], 0x07, 0xE5, "⇧", .modifier)
        add(["RALT", "RIGHT_ALT"], 0x07, 0xE6, "⌥", .modifier)
        add(["RGUI", "RIGHT_GUI", "RCMD", "RIGHT_COMMAND", "RWIN"], 0x07, 0xE7, "⌘", .modifier)

        // Consumer page (media etc.)
        add(["C_VOL_UP", "C_VOLUME_UP"], 0x0C, 0xE9, "Vol+", .media)
        add(["C_VOL_DN", "C_VOLUME_DOWN"], 0x0C, 0xEA, "Vol−", .media)
        add(["C_MUTE"], 0x0C, 0xE2, "Mute", .media)
        add(["C_PP", "C_PLAY_PAUSE"], 0x0C, 0xCD, "⏯", .media)
        add(["C_NEXT"], 0x0C, 0xB5, "⏭", .media)
        add(["C_PREV", "C_PREVIOUS"], 0x0C, 0xB6, "⏮", .media)
        add(["C_BRI_UP", "C_BRIGHTNESS_INC"], 0x0C, 0x6F, "☀+", .media)
        add(["C_BRI_DN", "C_BRIGHTNESS_DEC"], 0x0C, 0x70, "☀−", .media)
        add(["C_PLAY"], 0x0C, 0xB0, "▶", .media)
        add(["C_PAUSE"], 0x0C, 0xB1, "⏸", .media)
        add(["C_STOP"], 0x0C, 0xB7, "⏹", .media)
        add(["C_FF", "C_FAST_FORWARD"], 0x0C, 0xB3, "⏩", .media)
        add(["C_RW", "C_REWIND"], 0x0C, 0xB4, "⏪", .media)

        return rows
    }()

    /// name (canonical or alias) → entry
    static let byName: [String: KeycodeEntry] = {
        var map: [String: KeycodeEntry] = [:]
        for entry in entries {
            for name in entry.names {
                map[name] = entry
            }
        }
        return map
    }()

    /// Parse a dts keycode expression: IDENT or MOD(expr), e.g. LC(LG(LS(N4))).
    /// Returns nil for unknown names (caller degrades the binding to opaque).
    static func parseExpression(_ text: String) -> Keycode? {
        var wrappers: [Mod] = []
        var inner = text.trimmingCharacters(in: .whitespaces)
        while let open = inner.firstIndex(of: "(") {
            let head = String(inner[inner.startIndex..<open])
            guard let mod = Mod.wrapper(head), inner.hasSuffix(")") else { return nil }
            wrappers.append(mod)
            inner = String(inner[inner.index(after: open)..<inner.index(before: inner.endIndex)])
        }
        guard let entry = byName[inner] else { return nil }
        return Keycode(entry: entry, nameUsed: inner, wrappers: wrappers)
    }
}
