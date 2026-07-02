import Foundation

/// Surgical, formatting-preserving edits to the .keymap source.
enum KeymapEditor {

    /// Replace one binding token, compensating the following space run so the
    /// aligned columns after it keep their start positions where possible.
    /// `range` is in Character offsets (as recorded by the parser).
    static func replaceToken(source: String, range: Range<Int>, newText: String) -> String {
        var chars = Array(source)
        let delta = newText.count - (range.upperBound - range.lowerBound)

        var runEnd = range.upperBound
        while runEnd < chars.count, chars[runEnd] == " " { runEnd += 1 }
        let run = runEnd - range.upperBound

        var newRun = run
        let midLine = runEnd < chars.count && chars[runEnd] != "\n"
        if midLine, run > 0, delta != 0 {
            if delta > 0 {
                newRun = max(1, run - delta)     // absorb growth, keep ≥1 space
            } else {
                newRun = run - delta             // pad shrinkage
            }
        }

        chars.replaceSubrange(range.lowerBound..<runEnd,
                              with: Array(newText) + Array(repeating: " ", count: newRun))
        return String(chars)
    }

    /// Build the new source for one binding change, then PROVE it before it
    /// can touch disk: re-parse and require (a) identical layer/binding
    /// structure, (b) the edited slot round-trips to exactly the new binding,
    /// (c) every other slot's raw token is byte-identical.
    static func replacing(keymap: Keymap, layer: Int, position: Int,
                          with newBinding: KeyBinding) throws -> String {
        guard keymap.layers.indices.contains(layer),
              keymap.layers[layer].bindings.indices.contains(position) else {
            throw ParseError(message: "編集対象が範囲外です: L\(layer)[\(position)]")
        }
        let target = keymap.layers[layer].bindings[position]
        let newSource = replaceToken(source: keymap.sourceText,
                                     range: target.charRange,
                                     newText: newBinding.dtsText)

        let reparsed = try KeymapParser.parse(source: newSource, fileURL: keymap.fileURL)
        guard reparsed.layers.count == keymap.layers.count else {
            throw ParseError(message: "編集検証失敗: レイヤー数が変化しました")
        }
        for (li, newLayer) in reparsed.layers.enumerated() {
            let oldLayer = keymap.layers[li]
            guard newLayer.bindings.count == oldLayer.bindings.count else {
                throw ParseError(message: "編集検証失敗: L\(li) の bindings 数が変化しました")
            }
            for (pi, parsed) in newLayer.bindings.enumerated() {
                if li == layer, pi == position {
                    guard parsed.binding == newBinding else {
                        throw ParseError(message: "編集検証失敗: 変更スロットが期待どおり読めません")
                    }
                } else {
                    guard parsed.raw == oldLayer.bindings[pi].raw else {
                        throw ParseError(message: "編集検証失敗: L\(li)[\(pi)] が巻き添え変更されました")
                    }
                }
            }
        }
        return newSource
    }

    /// Validated write: build, verify, then write atomically.
    @discardableResult
    static func apply(keymap: Keymap, layer: Int, position: Int,
                      with newBinding: KeyBinding) throws -> String {
        guard let url = keymap.fileURL else {
            throw ParseError(message: "keymap のファイルパスが不明です")
        }
        let newSource = try replacing(keymap: keymap, layer: layer, position: position, with: newBinding)
        try Data(newSource.utf8).write(to: url, options: .atomic)
        return newSource
    }
}
