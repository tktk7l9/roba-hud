import Foundation

struct ParseError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Parses ZMK .keymap devicetree files just deeply enough to extract per-layer
/// binding tokens with their exact source spans (for surgical edits).
///
/// Strategy: comments are blanked in place (same character count) so every
/// offset in the blanked text maps 1:1 to the original. All scanning happens
/// on the blanked Character array; recorded ranges index into the original.
enum KeymapParser {

    static func parse(source: String, fileURL: URL? = nil) throws -> Keymap {
        let chars = Array(source)
        let blanked = blankComments(chars)

        guard let keymapBody = findNodeBody(named: "keymap", in: blanked, from: 0) else {
            throw ParseError(message: "keymap ノードが見つかりません")
        }

        var layers: [Layer] = []
        var cursor = keymapBody.lowerBound
        while let node = findChildNode(in: blanked, range: cursor..<keymapBody.upperBound) {
            cursor = node.body.upperBound + 1
            // Skip non-layer children (none today; "compatible" is a property,
            // not a node, so it never matches findChildNode).
            guard let bindingsSpan = findBindingsSpan(in: blanked, range: node.body) else {
                continue
            }
            let name = findDisplayName(in: blanked, chars: chars, range: node.body) ?? node.name
            let bindings = try tokenizeBindings(blanked: blanked, chars: chars, span: bindingsSpan)
            layers.append(Layer(index: layers.count, name: name,
                                nodeName: node.name, bindings: bindings))
        }

        guard !layers.isEmpty else {
            throw ParseError(message: "レイヤーが1つも見つかりません")
        }
        let counts = Set(layers.map { $0.bindings.count })
        guard counts.count == 1 else {
            throw ParseError(message: "レイヤー間で bindings 数が不一致です: \(layers.map { "\($0.name)=\($0.bindings.count)" }.joined(separator: ", "))")
        }
        return Keymap(layers: layers, sourceText: source, fileURL: fileURL,
                      mouseLayer: intProperty("automouse-layer", in: blanked) ?? 4,
                      scrollLayer: intProperty("scroll-layers", in: blanked) ?? 5)
    }

    /// First `name = <N>` int property anywhere in the file (used for the
    /// &trackball automouse/scroll layer numbers).
    static func intProperty(_ name: String, in chars: [Character]) -> Int? {
        let target = Array(name)
        var i = 0
        while i + target.count < chars.count {
            if Array(chars[i..<i + target.count]) == target,
               i == 0 || !isIdentChar(chars[i - 1]) {
                var j = i + target.count
                while j < chars.count, chars[j].isWhitespace || chars[j] == "=" { j += 1 }
                guard j < chars.count, chars[j] == "<" else { i += 1; continue }
                var k = j + 1
                var digits = ""
                while k < chars.count, chars[k] != ">" {
                    if chars[k].isNumber { digits.append(chars[k]) }
                    k += 1
                }
                return Int(digits)
            }
            i += 1
        }
        return nil
    }

    // MARK: - Comments

    /// Replace // line comments and /* block comments */ with spaces,
    /// preserving character counts and newlines (for line integrity).
    static func blankComments(_ chars: [Character]) -> [Character] {
        var out = chars
        var i = 0
        var inLine = false
        var inBlock = false
        var inString = false
        while i < out.count {
            let c = out[i]
            if inLine {
                if c == "\n" { inLine = false } else { out[i] = " " }
            } else if inBlock {
                if c == "*", i + 1 < out.count, out[i + 1] == "/" {
                    out[i] = " "; out[i + 1] = " "
                    i += 1
                    inBlock = false
                } else if c != "\n" {
                    out[i] = " "
                }
            } else if inString {
                if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "/", i + 1 < out.count {
                if out[i + 1] == "/" {
                    out[i] = " "; out[i + 1] = " "
                    i += 1
                    inLine = true
                } else if out[i + 1] == "*" {
                    out[i] = " "; out[i + 1] = " "
                    i += 1
                    inBlock = true
                }
            }
            i += 1
        }
        return out
    }

    // MARK: - Node scanning

    private static func isIdentChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-"
    }

    /// Find `name { ... }` (word-boundary match, optional label `name:` skipped)
    /// and return the body range (inside the braces).
    static func findNodeBody(named name: String, in chars: [Character], from start: Int) -> Range<Int>? {
        let target = Array(name)
        var i = start
        while i + target.count < chars.count {
            if Array(chars[i..<i + target.count]) == target {
                let beforeOK = i == 0 || !isIdentChar(chars[i - 1])
                var j = i + target.count
                // allow "name:" label form? (labels precede node names; here we
                // match the node name itself, so just skip whitespace to '{')
                while j < chars.count, chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" { j += 1 }
                if beforeOK, j < chars.count, chars[j] == "{" {
                    if let close = matchBrace(in: chars, open: j) {
                        return (j + 1)..<close
                    }
                }
            }
            i += 1
        }
        return nil
    }

    /// Find the next `ident {` child node inside `range`; returns its name and
    /// body range. Skips property assignments (`x = ...;`).
    static func findChildNode(in chars: [Character], range: Range<Int>) -> (name: String, body: Range<Int>)? {
        var i = range.lowerBound
        while i < range.upperBound {
            let c = chars[i]
            if isIdentChar(c), i == 0 || !isIdentChar(chars[i - 1]) {
                var j = i
                while j < range.upperBound, isIdentChar(chars[j]) { j += 1 }
                var k = j
                while k < range.upperBound, chars[k] == " " || chars[k] == "\t" || chars[k] == "\n" { k += 1 }
                if k < range.upperBound, chars[k] == "{" {
                    if let close = matchBrace(in: chars, open: k), close < range.upperBound {
                        return (String(chars[i..<j]), (k + 1)..<close)
                    }
                }
                // property or something else: skip to its terminator
                i = j
                continue
            }
            i += 1
        }
        return nil
    }

    /// Given chars[open] == "{", return the index of the matching "}".
    static func matchBrace(in chars: [Character], open: Int) -> Int? {
        var depth = 0
        var i = open
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    // MARK: - Layer contents

    /// Locate `bindings = < ... >` (NOT sensor-bindings) and return the range
    /// between the angle brackets.
    static func findBindingsSpan(in chars: [Character], range: Range<Int>) -> Range<Int>? {
        let target = Array("bindings")
        var i = range.lowerBound
        while i + target.count < range.upperBound {
            if Array(chars[i..<i + target.count]) == target,
               i == 0 || !isIdentChar(chars[i - 1]) {
                var j = i + target.count
                while j < range.upperBound, chars[j].isWhitespace { j += 1 }
                guard j < range.upperBound, chars[j] == "=" else { i += 1; continue }
                j += 1
                while j < range.upperBound, chars[j].isWhitespace { j += 1 }
                guard j < range.upperBound, chars[j] == "<" else { i += 1; continue }
                var k = j + 1
                while k < range.upperBound, chars[k] != ">" { k += 1 }
                guard k < range.upperBound else { return nil }
                return (j + 1)..<k
            }
            i += 1
        }
        return nil
    }

    static func findDisplayName(in blanked: [Character], chars: [Character], range: Range<Int>) -> String? {
        let target = Array("display-name")
        var i = range.lowerBound
        while i + target.count < range.upperBound {
            if Array(blanked[i..<i + target.count]) == target,
               i == 0 || !isIdentChar(blanked[i - 1]) {
                var j = i + target.count
                while j < range.upperBound, blanked[j].isWhitespace || blanked[j] == "=" { j += 1 }
                guard j < range.upperBound, blanked[j] == "\"" else { return nil }
                var k = j + 1
                while k < range.upperBound, chars[k] != "\"" { k += 1 }
                return String(chars[(j + 1)..<k])
            }
            i += 1
        }
        return nil
    }

    /// Split a bindings span into `&behavior param…` tokens. Tokens run from
    /// one `&` to the next; params never contain `&`, so no arity knowledge is
    /// needed for tokenization.
    static func tokenizeBindings(blanked: [Character], chars: [Character], span: Range<Int>) throws -> [ParsedBinding] {
        var result: [ParsedBinding] = []
        var i = span.lowerBound
        while i < span.upperBound {
            guard blanked[i] == "&" else { i += 1; continue }
            var end = i + 1
            while end < span.upperBound, blanked[end] != "&" { end += 1 }
            // trim trailing whitespace
            var last = end - 1
            while last > i, blanked[last].isWhitespace { last -= 1 }
            let range = i..<(last + 1)
            let raw = String(chars[range])
            let binding = try interpret(token: raw)
            result.append(ParsedBinding(binding: binding, charRange: range, raw: raw))
            i = end
        }
        return result
    }

    /// Split one raw token into behavior + params (whitespace-separated,
    /// parens kept balanced) and map to a KeyBinding.
    static func interpret(token: String) throws -> KeyBinding {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for c in token {
            if c.isWhitespace, depth == 0 {
                if !current.isEmpty { parts.append(current); current = "" }
            } else {
                if c == "(" { depth += 1 }
                if c == ")" { depth -= 1 }
                current.append(c)
            }
        }
        if !current.isEmpty { parts.append(current) }
        guard depth == 0 else {
            throw ParseError(message: "括弧が閉じていません: \(token)")
        }
        guard let head = parts.first, head.hasPrefix("&"), head.count > 1 else {
            throw ParseError(message: "不正なバインディング: \(token)")
        }
        let behavior = String(head.dropFirst())
        let params = Array(parts.dropFirst())

        func opaque() -> KeyBinding { .opaque(behavior: behavior, params: params) }
        func intParam(_ index: Int) -> Int? {
            params.indices.contains(index) ? Int(params[index]) : nil
        }

        switch behavior {
        case "kp":
            guard params.count == 1, let code = KeycodeTable.parseExpression(params[0]) else { return opaque() }
            return .kp(code)
        case "lt":
            guard params.count == 2, let layer = intParam(0),
                  let tap = KeycodeTable.parseExpression(params[1]) else { return opaque() }
            return .lt(layer: layer, tap: tap)
        case "mt":
            guard params.count == 2,
                  let hold = KeycodeTable.parseExpression(params[0]),
                  let tap = KeycodeTable.parseExpression(params[1]) else { return opaque() }
            return .mt(hold: hold, tap: tap)
        case "mo":
            guard let n = intParam(0), params.count == 1 else { return opaque() }
            return .mo(n)
        case "to":
            guard let n = intParam(0), params.count == 1 else { return opaque() }
            return .to(n)
        case "tog":
            guard let n = intParam(0), params.count == 1 else { return opaque() }
            return .tog(n)
        case "mkp":
            guard params.count == 1, params[0].hasPrefix("MB"),
                  let n = Int(params[0].dropFirst(2)), (1...5).contains(n) else { return opaque() }
            return .mkp(n)
        case "bt":
            guard (1...2).contains(params.count) else { return opaque() }
            return .bt(command: params[0], param: params.count == 2 ? intParam(1) : nil)
        case "out":
            guard params.count == 1 else { return opaque() }
            return .out(params[0])
        case "caps_word":
            return .capsWord
        case "trans":
            return .transparent
        case "none":
            return .none
        case "bootloader":
            return .bootloader
        case "sys_reset":
            return .sysReset
        default:
            return opaque()
        }
    }
}
