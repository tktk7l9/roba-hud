import Foundation

/// Dependency-free assertion runner (works headless / without XCTest):
///   swift run RoBaHUD --selftest
enum SelfTest {
    private static var failures = 0
    private static var count = 0

    private static func expect(_ condition: Bool, _ name: String,
                               file: String = #file, line: Int = #line) {
        count += 1
        if !condition {
            failures += 1
            print("FAIL: \(name)  (\((file as NSString).lastPathComponent):\(line))")
        }
    }

    private static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ name: String,
                                                  file: String = #file, line: Int = #line) {
        count += 1
        if a != b {
            failures += 1
            print("FAIL: \(name)  (\((file as NSString).lastPathComponent):\(line))")
            print("      got:      \(a)")
            print("      expected: \(b)")
        }
    }

    static func run() -> Int32 {
        testKeycodeTable()
        testGeometry()
        testParser()
        testRoundTrip()
        testEffectiveResolution()
        testLabels()
        testInference()
        print(failures == 0 ? "selftest OK (\(count) assertions)"
                            : "selftest FAILED: \(failures)/\(count)")
        return failures == 0 ? 0 : 1
    }

    // MARK: - KeycodeTable

    private static func testKeycodeTable() {
        // Canonical names must be unique.
        let canonical = KeycodeTable.entries.map(\.canonicalName)
        expectEqual(canonical.count, Set(canonical).count, "canonical names unique")

        // No duplicate (page, usage) among rows without implicit mods.
        let plain = KeycodeTable.entries.filter { $0.implicitMods.isEmpty }
        let usagePairs = plain.map { "\($0.page):\($0.usage)" }
        expectEqual(usagePairs.count, Set(usagePairs).count, "plain (page,usage) unique")

        expectEqual(KeycodeTable.byName["N4"]?.usage, 0x21, "N4 usage")
        expectEqual(KeycodeTable.byName["KP_NUMBER_7"]?.usage, 0x5F, "KP_NUMBER_7 usage")
        expectEqual(KeycodeTable.byName["LANG1"]?.usage, 0x90, "LANG1 usage")
        expectEqual(KeycodeTable.byName["LANG2"]?.usage, 0x91, "LANG2 usage")
        expectEqual(KeycodeTable.byName["PERCENT"]?.usage, 0x22, "PERCENT base usage (N5)")
        expectEqual(KeycodeTable.byName["PERCENT"]?.implicitMods, [.lsft], "PERCENT implicit shift")
        expectEqual(KeycodeTable.byName["C_VOL_UP"]?.page, 0x0C, "C_VOL_UP consumer page")
        expectEqual(KeycodeTable.byName["LCTRL"]?.usage, 0xE0, "LCTRL usage")

        // Wrapper expression parsing.
        let chord = KeycodeTable.parseExpression("LC(LG(LS(N4)))")
        expectEqual(chord?.wrappers, [.lctl, .lgui, .lsft], "nested wrapper order")
        expectEqual(chord?.entry.canonicalName, "N4", "nested wrapper base")
        expectEqual(chord?.dtsText, "LC(LG(LS(N4)))", "wrapper serialization")
        expectEqual(chord?.label, "⌃⇧⌘4", "chord label in Apple mod order")
        expect(KeycodeTable.parseExpression("NOT_A_KEY") == nil, "unknown keycode rejected")
    }

    // MARK: - Geometry

    private static func testGeometry() {
        guard let keys = try? GeometryLoader.load(json: Data(Fixtures.layoutJSON.utf8)) else {
            expect(false, "layout JSON loads")
            return
        }
        expectEqual(keys.count, 43, "43 keys")

        // Every rotated thumb key rotates around its own center → the center
        // must be unmoved by rotation.
        for key in keys where key.rotation != 0 {
            let c = key.center
            expect(abs(c.x - (key.x + 0.5)) < 1e-9 && abs(c.y - (key.y + 0.5)) < 1e-9,
                   "rotation origin == center for key \(key.index)")
        }
        expectEqual(keys.filter { $0.rotation != 0 }.count, 4, "4 rotated thumb keys")

        let bounds = GeometryLoader.bounds(of: keys)
        expect(bounds.width > 13.0 && bounds.width < 14.0, "plausible width \(bounds.width)")
        expect(bounds.height > 4.0 && bounds.height < 5.5, "plausible height \(bounds.height)")
    }

    // MARK: - Parser

    private static var fixtureKeymap: Keymap? = try? KeymapParser.parse(source: Fixtures.keymap)

    private static func testParser() {
        guard let keymap = fixtureKeymap else {
            expect(false, "fixture keymap parses")
            return
        }
        expectEqual(keymap.layers.map(\.name), ["BASE", "SYMBOL", "NUM", "FUNC", "MOUSE", "SCROLL"], "layer names")
        expectEqual(keymap.layers.map { $0.bindings.count }, Array(repeating: 43, count: 6), "43 bindings per layer")

        let l0 = keymap.layers[0].bindings
        expectEqual(l0[0].binding.dtsText, "&kp Q", "L0[0]")
        if case .lt(let layer, let tap) = l0[39].binding {
            expectEqual(layer, 5, "L0[39] lt layer")
            expectEqual(tap.nameUsed, "LANG2", "L0[39] lt tap")
        } else { expect(false, "L0[39] is lt") }
        if case .mt(let hold, let tap) = l0[40].binding {
            expectEqual(hold.nameUsed, "LCTRL", "L0[40] mt hold")
            expectEqual(tap.nameUsed, "LANG1", "L0[40] mt tap")
        } else { expect(false, "L0[40] is mt") }
        if case .mkp(let n) = l0[16].binding {
            expectEqual(n, 3, "L0[16] middle click")
        } else { expect(false, "L0[16] is mkp") }
        if case .mo(let n) = l0[15].binding {
            expectEqual(n, 5, "L0[15] mo 5")
        } else { expect(false, "L0[15] is mo") }

        let l2 = keymap.layers[2].bindings
        expectEqual(l2[1].binding.dtsText, "&kp KP_NUMBER_7", "NUM alias preserved")
        if case .to(let n) = l2[0].binding { expectEqual(n, 0, "NUM to 0") }
        else { expect(false, "L2[0] is to") }

        let l3 = keymap.layers[3].bindings
        if case .opaque(let behavior, let params) = l3[9].binding {
            expectEqual(behavior, "bt_clr_hold", "custom hold-tap opaque")
            expectEqual(params, ["0", "0"], "opaque params")
        } else { expect(false, "L3[9] is opaque") }
        expectEqual(l3[32].binding.dtsText, "&kp LC(LG(LS(N4)))", "nested chord")
        if case .bt(let cmd, let param) = l3[21].binding {
            expectEqual(cmd, "BT_SEL", "bt command")
            expectEqual(param, 1, "bt param")
        } else { expect(false, "L3[21] is bt") }

        // Comment blanking: same char count, newlines preserved.
        let chars = Array(Fixtures.keymap)
        let blanked = KeymapParser.blankComments(chars)
        expectEqual(blanked.count, chars.count, "blankComments preserves length")
        expectEqual(blanked.filter { $0 == "\n" }.count, chars.filter { $0 == "\n" }.count,
                    "blankComments preserves newlines")
        expect(!String(blanked).contains("誤爆"), "comments actually blanked")

        // Unknown keycode degrades to opaque, structural garbage throws.
        if case .opaque = try! KeymapParser.interpret(token: "&kp NOT_A_KEY") {}
        else { expect(false, "unknown keycode → opaque") }
        expect((try? KeymapParser.parse(source: "no keymap here")) == nil, "garbage source throws")
    }

    // MARK: - Round trip

    private static func testRoundTrip() {
        guard let keymap = fixtureKeymap else { return }
        for layer in keymap.layers {
            for (i, parsed) in layer.bindings.enumerated() {
                if parsed.binding.dtsText != parsed.raw {
                    expect(false, "round-trip L\(layer.index)[\(i)]: \"\(parsed.binding.dtsText)\" != \"\(parsed.raw)\"")
                }
            }
        }
        expect(true, "round-trip sweep completed")

        // Source ranges point at the exact raw token.
        let chars = Array(Fixtures.keymap)
        for layer in keymap.layers {
            for parsed in layer.bindings {
                if String(chars[parsed.charRange]) != parsed.raw {
                    expect(false, "charRange mismatch for \(parsed.raw)")
                }
            }
        }
        expect(true, "charRange sweep completed")
    }

    // MARK: - Effective resolution

    private static func testEffectiveResolution() {
        guard let keymap = fixtureKeymap else { return }
        // SYMBOL[35] is &trans → falls through to BASE[35] = &kp COMMA.
        expectEqual(keymap.effective(layer: 1, position: 35).dtsText, "&kp COMMA", "trans falls to base")
        // Explicit binding is returned as-is.
        expectEqual(keymap.effective(layer: 1, position: 0).dtsText, "&kp PERCENT", "explicit stays")
        // BASE trans-less: effective == own binding.
        expectEqual(keymap.effective(layer: 0, position: 0).dtsText, "&kp Q", "base identity")
    }

    // MARK: - Labels

    private static func testLabels() {
        guard let keymap = fixtureKeymap else { return }
        let lt = LabelProvider.label(for: keymap.layers[0].bindings[39].binding, in: keymap)
        expectEqual(lt.tap, "英数", "lt tap label")
        expectEqual(lt.hold, "▷SCROLL", "lt hold label")

        let mt = LabelProvider.label(for: keymap.layers[0].bindings[40].binding, in: keymap)
        expectEqual(mt.tap, "かな", "mt tap label")
        expectEqual(mt.hold, "⌃", "mt hold label")

        let chord = LabelProvider.label(for: keymap.layers[3].bindings[19].binding, in: keymap)
        expectEqual(chord.tap, "⇧⌘4", "screenshot chord label")
    }

    // MARK: - Inference engine (fake clock scenarios)

    private static func testInference() {
        guard let keymap = fixtureKeymap else { return }
        func at(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }
        func fresh() -> InferenceEngine { InferenceEngine(keymap: keymap) }

        expectEqual(keymap.mouseLayer, 4, "automouse layer parsed")
        expectEqual(keymap.scrollLayer, 5, "scroll layer parsed")

        // KP_N7 (0x5F) exists only on NUM → snap to layer 2, light pos 1.
        var e = fresh()
        e.handle(.key(page: 7, usage: 0x5F, down: true), at: at(0))
        expectEqual(e.displayed, 2, "KP_N7 → NUM")
        expectEqual(e.highlighted, [1], "KP_N7 highlights NUM[1]")

        // ENTER is on BASE and NUM: current layer wins.
        e = fresh()
        e.handle(.key(page: 7, usage: 0x28, down: true), at: at(0))
        expectEqual(e.displayed, 0, "ENTER stays on BASE")
        expectEqual(e.highlighted, [21], "ENTER highlights BASE[21]")

        // Held arrow keeps NUM alive indefinitely; decay starts on release.
        e = fresh()
        e.handle(.key(page: 7, usage: 0x50, down: true), at: at(0))    // LEFT
        expectEqual(e.displayed, 2, "LEFT → NUM")
        e.tick(at: at(3.0))
        expectEqual(e.displayed, 2, "held key keeps NUM past decay")
        e.handle(.key(page: 7, usage: 0x50, down: false), at: at(3.1))
        e.tick(at: at(3.6))
        expectEqual(e.displayed, 2, "NUM lingers within layerDecay")
        e.tick(at: at(4.3))
        expectEqual(e.displayed, 0, "NUM decays to BASE after release")

        // Trackball motion → MOUSE with 700ms decay.
        e = fresh()
        e.handle(.pointerMotion, at: at(0))
        expectEqual(e.displayed, 4, "motion → MOUSE")
        e.tick(at: at(0.6))
        expectEqual(e.displayed, 4, "MOUSE within decay")
        e.tick(at: at(0.75))
        expectEqual(e.displayed, 0, "MOUSE decays after 700ms")

        // Scroll → SCROLL with 400ms decay; scroll outranks motion.
        e = fresh()
        e.handle(.pointerMotion, at: at(0))
        e.handle(.scroll, at: at(0.1))
        expectEqual(e.displayed, 5, "scroll outranks motion")
        e.tick(at: at(0.45))
        e.tick(at: at(0.9))
        expectEqual(e.displayed, 0, "SCROLL decays")

        // MB1 during motion → MOUSE[31]; held button keeps MOUSE (drag).
        e = fresh()
        e.handle(.pointerMotion, at: at(0))
        e.handle(.button(number: 1, down: true), at: at(0.1))
        expectEqual(e.displayed, 4, "click during motion stays MOUSE")
        expectEqual(e.highlighted, [31], "MB1 highlights MOUSE[31]")
        e.tick(at: at(1.5))
        expectEqual(e.displayed, 4, "held MB1 keeps MOUSE past motion decay")
        e.handle(.button(number: 1, down: false), at: at(1.6))
        e.tick(at: at(2.8))
        expectEqual(e.displayed, 0, "MOUSE decays after drag ends")

        // Implicit-shift suppression: ⇧ down + N5 down within the chord
        // window = SYMBOL "%": light SYMBOL[0], not the BASE ⇧ hold face.
        e = fresh()
        e.handle(.key(page: 7, usage: 0xE1, down: true), at: at(0))
        e.handle(.key(page: 7, usage: 0x22, down: true), at: at(0.01))
        expectEqual(e.displayed, 1, "PERCENT → SYMBOL")
        expectEqual(e.highlighted, [0], "PERCENT highlights SYMBOL[0] only")

        // Solo modifier hold commits after the chord window: BASE mt hold face.
        e = fresh()
        e.handle(.key(page: 7, usage: 0xE0, down: true), at: at(0))    // LCTRL
        expectEqual(e.highlighted, [], "mod not attributed within chord window")
        e.tick(at: at(0.05))
        expectEqual(e.displayed, 0, "solo ⌃ stays BASE")
        expectEqual(e.highlighted, [40], "⌃ lights かな hold face BASE[40]")

        // Screenshot chord ⌘⇧4 → FUNC[19] (not the ⌃⌘⇧4 at FUNC[32]).
        e = fresh()
        e.handle(.key(page: 7, usage: 0xE3, down: true), at: at(0))
        e.handle(.key(page: 7, usage: 0xE1, down: true), at: at(0.005))
        e.handle(.key(page: 7, usage: 0x21, down: true), at: at(0.01))
        expectEqual(e.displayed, 3, "⌘⇧4 → FUNC")
        expectEqual(e.highlighted, [19], "⌘⇧4 highlights FUNC[19]")

        // Letters snap back to BASE immediately.
        e = fresh()
        e.handle(.key(page: 7, usage: 0x5F, down: true), at: at(0))
        e.handle(.key(page: 7, usage: 0x5F, down: false), at: at(0.1))
        e.handle(.key(page: 7, usage: 0x04, down: true), at: at(0.2))  // A
        expectEqual(e.displayed, 0, "letter snaps BASE")

        // Pin overrides everything.
        e = fresh()
        e.pinned = 2
        e.handle(.pointerMotion, at: at(0))
        e.handle(.key(page: 7, usage: 0x04, down: true), at: at(0.1))
        expectEqual(e.displayed, 2, "pin wins over all evidence")
    }
}
