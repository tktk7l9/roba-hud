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
        testStats()
        testEditor()
        testGHRunParsing()
        testBatteryModel()
        testBatteryForecast()
        testCheatsheetGenerator()
        testCoverageGaps()
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

        // lastPress reports attributions for stats.
        e = fresh()
        e.handle(.key(page: 7, usage: 0x5F, down: true), at: at(0))
        expect(e.lastPress?.layer == 2 && e.lastPress?.position == 1, "lastPress set on key down")
    }

    // MARK: - Stats

    private static func testStats() {
        var stats = KeyStats()
        stats.record(layer: 0, position: 21)
        stats.record(layer: 0, position: 21)
        stats.record(layer: 2, position: 1)
        expectEqual(stats.count(layer: 0, position: 21), 2, "count accumulates")
        expectEqual(stats.total, 3, "total")
        expectEqual(stats.layerTotals(), [0: 2, 2: 1], "layer totals")
        expectEqual(stats.top(1).first?.position, 21, "top key")

        expectEqual(stats.heat(layer: 0, position: 21), 1.0, "max key heat == 1")
        expect(stats.heat(layer: 2, position: 1) > 0 && stats.heat(layer: 2, position: 1) < 1,
               "lower count heat in (0,1)")
        expectEqual(stats.heat(layer: 5, position: 0), 0, "unused key heat == 0")

        // JSON round-trip.
        if let data = try? JSONEncoder().encode(stats),
           let decoded = try? JSONDecoder().decode(KeyStats.self, from: data) {
            expectEqual(decoded, stats, "stats JSON round-trip")
        } else {
            expect(false, "stats encodes")
        }
    }

    // MARK: - Editor (surgical replacement)

    private static func testEditor() {
        guard let keymap = fixtureKeymap else { return }

        // Grow by 2: the following space run shrinks so &kp W keeps its column.
        do {
            let esc = KeyBinding.kp(Keycode(entry: KeycodeTable.byName["ESC"]!))
            let newSource = try KeymapEditor.replacing(keymap: keymap, layer: 0, position: 0, with: esc)
            expect(newSource.contains("&kp ESC   &kp W"), "grown token absorbs following spaces")

            // Everything except the edited token must be byte-identical:
            // splitting on the two variants must yield identical remainders.
            let strippedOld = Fixtures.keymap.replacingOccurrences(of: "&kp Q     ", with: "")
            let strippedNew = newSource.replacingOccurrences(of: "&kp ESC   ", with: "")
            expectEqual(strippedNew, strippedOld, "rest of file untouched on grow")
        } catch {
            expect(false, "grow edit throws: \(error)")
        }

        // Shrink by 8: the following run grows so &kp BACKSPACE keeps its column.
        do {
            let del = KeyBinding.kp(Keycode(entry: KeycodeTable.byName["DEL"]!))
            let newSource = try KeymapEditor.replacing(keymap: keymap, layer: 0, position: 40, with: del)
            expect(newSource.contains("&kp DEL          &kp BACKSPACE"),
                   "shrunk token pads following spaces")
            let reparsed = try KeymapParser.parse(source: newSource)
            expectEqual(reparsed.layers[0].bindings[40].binding.dtsText, "&kp DEL", "edited slot reparses")
        } catch {
            expect(false, "shrink edit throws: \(error)")
        }

        // A binding whose serialization would corrupt the structure is
        // rejected by the pre-write re-parse (token splits into two).
        let corrupt = KeyBinding.opaque(behavior: "kp Q &kp", params: [])
        expect((try? KeymapEditor.replacing(keymap: keymap, layer: 0, position: 0, with: corrupt)) == nil,
               "structure-corrupting edit rejected before write")

        // Editing a &trans slot on a higher layer works (common case).
        do {
            let f13ish = KeyBinding.kp(Keycode(entry: KeycodeTable.byName["HOME"]!))
            let newSource = try KeymapEditor.replacing(keymap: keymap, layer: 5, position: 0, with: f13ish)
            let reparsed = try KeymapParser.parse(source: newSource)
            expectEqual(reparsed.layers[5].bindings[0].binding.dtsText, "&kp HOME", "trans slot editable")
        } catch {
            expect(false, "trans edit throws: \(error)")
        }
    }

    // MARK: - gh run list JSON

    private static func testGHRunParsing() {
        let json = """
        [
          {"databaseId": 111, "status": "completed", "conclusion": "success",
           "headSha": "aaaa000000000000000000000000000000000000"},
          {"databaseId": 222, "status": "in_progress", "conclusion": null,
           "headSha": "bbbb000000000000000000000000000000000000"},
          {"databaseId": 333, "status": "queued", "conclusion": null,
           "headSha": "cccc000000000000000000000000000000000000"}
        ]
        """
        let done = GitPipeline.matchRun(json: json, sha: "aaaa000000000000000000000000000000000000")
        expectEqual(done?.databaseId, 111, "matches completed run by sha")
        expectEqual(done?.conclusion, "success", "conclusion decoded")

        let running = GitPipeline.matchRun(json: json, sha: "bbbb000000000000000000000000000000000000")
        expectEqual(running?.status, "in_progress", "matches in-progress run")
        expectEqual(running?.conclusion, nil, "null conclusion decodes as nil")

        expect(GitPipeline.matchRun(json: json, sha: "ffff") == nil, "no match for unknown sha")
        expect(GitPipeline.matchRun(json: "not json", sha: "aaaa") == nil, "garbage JSON tolerated")
    }

    // MARK: - Battery model

    private static func testBatteryModel() {
        // CUD → role mapping (ZMK central_bas_proxy.c labels).
        expectEqual(BatteryRole.from(cud: nil), .central, "no CUD → central")
        expectEqual(BatteryRole.from(cud: "Peripheral 0"), .peripheral(0), "CUD Peripheral 0")
        expectEqual(BatteryRole.from(cud: "Peripheral 1"), .peripheral(1), "CUD Peripheral 1")
        expectEqual(BatteryRole.from(cud: "garbage"), .central, "unknown CUD → central")
        expectEqual(BatteryRole.central.displayName, "右", "central = 右 (roBa central is right half)")
        expectEqual(BatteryRole.peripheral(0).displayName, "左", "peripheral 0 = 左")

        expectEqual(BatterySeverity.of(level: 55), .ok, "severity ok")
        expectEqual(BatterySeverity.of(level: 20), .low, "severity low at 20")
        expectEqual(BatterySeverity.of(level: 10), .critical, "severity critical at 10")

        // Notification policy: fire once on crossing, re-arm above threshold+hysteresis.
        var policy = BatteryNotificationPolicy()
        policy.threshold = 20
        policy.hysteresis = 5
        expect(!policy.shouldNotify(role: .central, level: 50), "no notify at 50")
        expect(policy.shouldNotify(role: .central, level: 19), "notify on crossing 20")
        expect(!policy.shouldNotify(role: .central, level: 18), "no refire while low")
        expect(!policy.shouldNotify(role: .central, level: 22), "no re-arm inside hysteresis band")
        expect(!policy.shouldNotify(role: .central, level: 18), "still fired inside band")
        expect(!policy.shouldNotify(role: .central, level: 80), "recharge above band re-arms silently")
        expect(policy.shouldNotify(role: .central, level: 15), "refires after re-arm")
        expect(policy.shouldNotify(role: .peripheral(0), level: 10), "roles tracked independently")

        // History: dedupe, prune, series, roles.
        func at(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }
        var history = BatteryHistory()
        history.append(levels: ["central": 90], at: at(0))
        history.append(levels: ["central": 90], at: at(60))          // duplicate → dropped
        history.append(levels: ["central": 90, "peripheral0": 80], at: at(120))
        expectEqual(history.samples.count, 2, "duplicate sample deduped")

        history.retentionDays = 1
        history.append(levels: ["central": 85, "peripheral0": 80], at: at(2 * 86400))
        expectEqual(history.samples.count, 1, "old samples pruned")

        history = BatteryHistory()
        history.append(levels: ["central": 90], at: at(0))
        history.append(levels: ["central": 80, "peripheral0": 70], at: at(3600))
        let series = history.series(role: .central, days: 1, now: at(3600))
        expectEqual(series.map(\.level), [90, 80], "series levels in order")
        expectEqual(history.series(role: .peripheral(0), days: 1, now: at(3600)).map(\.level), [70],
                    "peripheral series only where present")
        expectEqual(history.knownRoles, [.central, .peripheral(0)], "known roles central-first")

        // Codable round-trip.
        if let data = try? JSONEncoder().encode(history),
           let decoded = try? JSONDecoder().decode(BatteryHistory.self, from: data) {
            expectEqual(decoded, history, "battery history JSON round-trip")
        } else {
            expect(false, "battery history encodes")
        }

        // Levels clamp + update.
        var levels = BatteryLevels()
        levels.set(role: .central, level: 150, at: at(0))
        expectEqual(levels.level(of: .central), 100, "level clamped to 100")
        levels.set(role: .peripheral(0), level: -5, at: at(1))
        expectEqual(levels.level(of: .peripheral(0)), 0, "level clamped to 0")

        // Menu bar label lines (R = central/right, L = peripheral/left).
        var mb = BatteryLevels()
        expectEqual(BatteryMenuBarLabel.lines(levels: mb),
                    [.init(text: "R\t–", severity: nil), .init(text: "L\t–", severity: nil)],
                    "menu bar shows – when unknown")
        mb.set(role: .central, level: 85, at: at(0))
        mb.set(role: .peripheral(0), level: 15, at: at(0))
        expectEqual(BatteryMenuBarLabel.lines(levels: mb),
                    [.init(text: "R\t85%", severity: .ok), .init(text: "L\t15%", severity: .low)],
                    "menu bar lines carry per-line severity")
        expectEqual(BatteryMenuBarLabel.singleLine(levels: mb),
                    [.init(text: "R85", severity: .ok), .init(text: "L15", severity: .low)],
                    "single-line variant drops tabs and %")
        expectEqual(BatteryMenuBarLabel.singleLine(levels: BatteryLevels()).first?.text, "R–",
                    "single-line unknown")

        // Remaining BatteryRole / severity / history branches.
        expectEqual(BatteryRole.from(cud: "Peripheral X"), .peripheral(0), "non-numeric CUD index → 0")
        expectEqual(BatteryRole.peripheral(2).displayName, "P2", "extra peripheral display name")
        expectEqual(BatteryRole.peripheral(2).key, "peripheral2", "peripheral key")
        expectEqual(BatterySeverity.of(level: 21), .ok, "severity ok boundary above low")
        expectEqual(BatterySeverity.of(level: 11), .low, "severity low boundary above critical")

        var h2 = BatteryHistory()
        h2.append(levels: [:], at: at(0))
        expectEqual(h2.samples.count, 0, "empty levels not appended")
        h2.append(levels: ["central": 50, "peripheral1": 40], at: at(0))
        h2.retentionDays = 0.001
        h2.prune(now: at(86400))
        expectEqual(h2.samples.count, 0, "prune removes everything when all stale")
        h2.retentionDays = 30
        h2.append(levels: ["peripheral1": 40, "peripheral0": 41, "central": 50], at: at(86400))
        expectEqual(h2.knownRoles, [.central, .peripheral(0), .peripheral(1)],
                    "known roles sorted, multi-peripheral")
    }

    // MARK: - Battery forecast

    private static func testBatteryForecast() {
        func at(_ hours: Double) -> Date { Date(timeIntervalSinceReferenceDate: hours * 3600) }

        // Steady discharge: 1% per 2h over 24h → 12%/day.
        var series: [(at: Date, level: Int)] = (0...12).map { (at(Double($0) * 2), 100 - $0) }
        let steady = BatteryForecast.estimate(series: series, now: at(24))
        expect(abs((steady?.ratePerDay ?? 0) - 12) < 0.5, "steady discharge ≈12%/day")
        expect(abs((steady?.daysLeft ?? 0) - 78.0 / 12.0) < 0.3, "daysLeft to 10% floor")

        // Charge event cuts the segment: only post-charge slope counts.
        series = [(at(0), 50), (at(3), 48), (at(6), 90), (at(12), 87), (at(18), 84)]
        let postCharge = BatteryForecast.estimate(series: series, now: at(18))
        expect(abs((postCharge?.ratePerDay ?? 0) - 12) < 1.0, "post-charge slope only (≈12%/day)")

        // Too-short segment / flat / sparse → nil.
        expect(BatteryForecast.estimate(series: [(at(0), 90), (at(1), 89)], now: at(1)) == nil,
               "short segment → nil")
        expect(BatteryForecast.estimate(series: (0...12).map { (at(Double($0) * 2), 80) }, now: at(24)) == nil,
               "flat series → nil")
        expect(BatteryForecast.estimate(series: [(at(0), 90)], now: at(0)) == nil, "single point → nil")
        expect(BatteryForecast.estimate(series: [], now: at(0)) == nil, "empty → nil")

        // Same-timestamp points: zero denominator guard (minSpan relaxed).
        expect(BatteryForecast.estimate(series: [(at(0), 90), (at(0), 80)], now: at(0), minSpan: 0) == nil,
               "degenerate timestamps → nil")

        // Below floor → 残り0日.
        series = (0...12).map { (at(Double($0) * 2), 20 - $0) }   // ends at 8 (< floor)
        expectEqual(BatteryForecast.estimate(series: series, now: at(24))?.daysLeft, 0,
                    "below floor → 0 days")

        // Window filter drops old points.
        let old: [(at: Date, level: Int)] = [(at(-24 * 30), 100), (at(-24 * 29), 90)]
        expect(BatteryForecast.estimate(series: old, now: at(0)) == nil, "points outside window ignored")

        // Summaries.
        expectEqual(BatteryForecast.summary(nil), nil, "nil estimate → nil summary")
        expectEqual(BatteryForecast.summary(.init(ratePerDay: 5, daysLeft: nil)), "−5.0%/日",
                    "rate-only summary")
        expectEqual(BatteryForecast.summary(.init(ratePerDay: 12, daysLeft: 6.5)),
                    "−12.0%/日 ・ 残り約7日", "days summary rounds")
        expectEqual(BatteryForecast.summary(.init(ratePerDay: 40, daysLeft: 0.4)),
                    "−40.0%/日 ・ 残り1日未満", "sub-day summary")
    }

    // MARK: - Cheatsheet generator

    private static func testCheatsheetGenerator() {
        guard let keymap = fixtureKeymap,
              let geometry = try? GeometryLoader.load(json: Data(Fixtures.layoutJSON.utf8)) else {
            expect(false, "cheatsheet fixtures load")
            return
        }

        // Short labels across binding kinds.
        expectEqual(CheatsheetGenerator.shortLabel(.transparent), "─", "trans label")
        expectEqual(CheatsheetGenerator.shortLabel(.mo(5)), "▷5", "mo label")
        expectEqual(CheatsheetGenerator.shortLabel(.to(0)), "→0", "to label")
        expectEqual(CheatsheetGenerator.shortLabel(.tog(2)), "⇄2", "tog label")
        expectEqual(CheatsheetGenerator.shortLabel(.mkp(3)), "M3", "mkp label")
        expectEqual(CheatsheetGenerator.shortLabel(.bt(command: "BT_SEL", param: 1)), "BT1", "bt sel label")
        expectEqual(CheatsheetGenerator.shortLabel(.bt(command: "BT_CLR", param: nil)), "BT✕", "bt clr label")
        expectEqual(CheatsheetGenerator.shortLabel(.out("OUT_TOG")), "OUT", "out label")
        expectEqual(CheatsheetGenerator.shortLabel(.capsWord), "CW", "caps word label")
        expectEqual(CheatsheetGenerator.shortLabel(.none), "✕", "none label")
        expectEqual(CheatsheetGenerator.shortLabel(.bootloader), "BOOT", "bootloader label")
        expectEqual(CheatsheetGenerator.shortLabel(.sysReset), "RST", "reset label")
        expectEqual(CheatsheetGenerator.shortLabel(.opaque(behavior: "bt_clr_hold", params: ["0", "0"])),
                    "BTclr*", "custom hold label")
        expectEqual(CheatsheetGenerator.shortLabel(.opaque(behavior: "mystery", params: [])),
                    "mystery", "unknown opaque label")

        // BASE diagram: split separator, hold-tap stars, inner keys.
        let base = CheatsheetGenerator.diagram(layer: keymap.layers[0], geometry: geometry)
        let rows = base.components(separatedBy: "\n")
        expectEqual(rows.count, 4, "diagram has 4 rows")
        expect(rows[0].hasPrefix("Q"), "row0 starts at Q")
        expect(rows[0].contains("│"), "split separator present")
        expect(rows[1].contains("▷5") && rows[1].contains("M3"), "row1 inner keys")
        expect(rows[3].contains("英数*") && rows[3].contains("かな*"), "row3 hold-taps")

        // Splice replaces only the fence contents and the date line.
        let markdown = """
        # title
        > 最終更新: 2026-06-22（手動）
        prose kept

        ## Layer 0 — BASE

        intro kept
        ```
        OLD GRID
        ```
        outro kept

        ## Layer 9 — GHOST
        no fence here
        """
        let spliced = CheatsheetGenerator.splice(markdown: markdown, diagrams: [0: "NEW GRID", 9: "X", 4: "Y"],
                                                 dateLine: "2026-07-03（roba-hud 自動生成）")
        expect(spliced.contains("NEW GRID") && !spliced.contains("OLD GRID"), "fence contents replaced")
        expect(spliced.contains("intro kept") && spliced.contains("outro kept")
               && spliced.contains("prose kept"), "prose preserved")
        expect(spliced.contains("> 最終更新: 2026-07-03（roba-hud 自動生成）"), "date line updated")
        expect(spliced.contains("no fence here"), "layer without fence untouched")

        // regenerate: idempotent (second run returns nil).
        if let once = CheatsheetGenerator.regenerate(markdown: markdown, keymap: keymap,
                                                     geometry: geometry, date: "2026-07-03") {
            expect(CheatsheetGenerator.regenerate(markdown: once, keymap: keymap,
                                                  geometry: geometry, date: "2026-07-03") == nil,
                   "regenerate is idempotent")
        } else {
            expect(false, "regenerate produces output")
        }
    }

    // MARK: - Coverage gap sweep (branches not exercised elsewhere)

    private static func testCoverageGaps() {
        guard let keymap = fixtureKeymap else { return }
        func at(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }

        // KeymapModel: serialization + labels for kinds absent from the fixture.
        expectEqual(KeyBinding.tog(2).dtsText, "&tog 2", "tog serialization")
        expectEqual(KeyBinding.bt(command: "BT_CLR", param: nil).dtsText, "&bt BT_CLR", "bt no-param serialization")
        expectEqual(LabelProvider.label(for: .tog(2), in: keymap).tap, "⇄NUM", "tog label uses layer name")
        expectEqual(LabelProvider.label(for: .mo(9), in: nil).tap, "▷L9", "nil keymap → Ln fallback")
        expectEqual(LabelProvider.label(for: .bt(command: "BT_NXT", param: nil), in: keymap).tap, "BT_NXT", "bt other label")
        expectEqual(LabelProvider.label(for: .bt(command: "BT_CLR", param: nil), in: keymap).tap, "BT✕", "bt clr label")
        expectEqual(LabelProvider.label(for: .out("OUT_TOG"), in: keymap).tap, "OUT", "out label")
        expectEqual(LabelProvider.label(for: KeyBinding.none, in: keymap).tap, "—", "none label")
        expectEqual(LabelProvider.label(for: .bootloader, in: keymap).tap, "BOOT", "bootloader label")
        expectEqual(LabelProvider.label(for: .sysReset, in: keymap).tap, "RST", "reset label")
        expectEqual(LabelProvider.label(for: .opaque(behavior: "zip", params: []), in: keymap).tap, "zip", "opaque label")
        expectEqual(keymap.layerName(99), "L99", "layerName out of range")
        expect(!KeyBinding.opaque(behavior: "x", params: []).isEditable, "opaque not editable")
        expect(KeyBinding.transparent.isEditable, "trans editable")

        // KeycodeTable: malformed expressions and mod lookups.
        expect(KeycodeTable.parseExpression("LS(A") == nil, "unbalanced wrapper rejected")
        expect(KeycodeTable.parseExpression("XX(A)") == nil, "unknown wrapper rejected")
        expect(Mod.fromUsage(0x50) == nil, "non-mod usage → nil")
        expectEqual(Mod.rctl.glyph, "⌃", "right mod glyph")
        expectEqual(Mod.rsft.displayRank, 2, "right shift rank")
        expectEqual(Mod.ralt.usage, 0xE6, "ralt usage")
        expectEqual(Mod.rgui.glyph, "⌘", "rgui glyph")

        // Parser: comment/string/error branches.
        let commented = Array("a /* b\nc */ d \"e//f\" // g\nh")
        let blanked = KeymapParser.blankComments(commented)
        expectEqual(String(blanked), "a     \n     d \"e//f\"     \nh", "block/line/string comment rules")
        expect((try? KeymapParser.interpret(token: "&kp LS(A")) == nil, "unbalanced parens throw")
        expect((try? KeymapParser.interpret(token: "kp A")) == nil, "missing & throws")
        if case .opaque = try! KeymapParser.interpret(token: "&mkp MB9") {} else { expect(false, "MB9 → opaque") }
        if case .opaque = try! KeymapParser.interpret(token: "&mo x") {} else { expect(false, "mo non-int → opaque") }
        if case .opaque = try! KeymapParser.interpret(token: "&out A B") {} else { expect(false, "out arity → opaque") }
        if case .opaque = try! KeymapParser.interpret(token: "&bt A B C D") {} else { expect(false, "bt arity → opaque") }
        if case .opaque = try! KeymapParser.interpret(token: "&lt X TAB") {} else { expect(false, "lt non-int → opaque") }

        let miniKeymap = """
        / {
            keymap {
                compatible = "zmk,keymap";
                first {
                    bindings = <&kp A &kp B>;
                };
                second_layer {
                    bindings = <&trans &trans>;
                };
            };
        };
        """
        if let mini = try? KeymapParser.parse(source: miniKeymap) {
            expectEqual(mini.layers.map(\.name), ["first", "second_layer"], "node-name fallback")
            expectEqual(mini.mouseLayer, 4, "automouse default when absent")
            expectEqual(mini.scrollLayer, 5, "scroll default when absent")
            expectEqual(mini.effective(layer: 1, position: 0).dtsText, "&kp A", "mini fallthrough")
        } else {
            expect(false, "mini keymap parses")
        }
        // Unterminated bindings vector → that layer is skipped → no layers.
        expect((try? KeymapParser.parse(source: "keymap { l { bindings = <&kp A ; }; };")) == nil,
               "unterminated bindings rejected")
        // Mismatched binding counts across layers.
        expect((try? KeymapParser.parse(source: """
            keymap { a { bindings = <&kp A>; }; b { bindings = <&kp A &kp B>; }; };
            """)) == nil, "uneven layer sizes rejected")
        // intProperty: first candidate without <…> is skipped, second wins.
        expectEqual(KeymapParser.intProperty("foo", in: Array("foo = 4; foo = <7>;")), 7,
                    "intProperty skips non-angle form")
        expect(KeymapParser.intProperty("foo", in: Array("bar = <1>;")) == nil, "intProperty absent")
        // Braces inside strings don't confuse the brace matcher.
        if let brace = try? KeymapParser.parse(source: """
            keymap { l { display-name = "B{A}SE"; bindings = <&kp A>; }; };
            """) {
            expectEqual(brace.layers[0].name, "B{A}SE", "brace inside display-name")
        } else {
            expect(false, "braced display-name parses")
        }

        // Geometry: fallback + error paths.
        expect((try? GeometryLoader.load(json: Data("nope".utf8))) == nil, "garbage layout json throws")
        expect((try? GeometryLoader.load(json: Data(#"{"layouts":{}}"#.utf8))) == nil, "empty layouts throws")
        if let alt = try? GeometryLoader.load(json: Data(
            #"{"layouts":{"other":{"layout":[{"row":0,"col":0,"x":0,"y":0}]}}}"#.utf8)) {
            expectEqual(alt.count, 1, "non-default layout name accepted")
        } else {
            expect(false, "alt layout loads")
        }

        // Editor: explicit error paths.
        expect((try? KeymapEditor.replacing(keymap: keymap, layer: 9, position: 0,
                                            with: .transparent)) == nil, "out-of-range layer rejected")
        expect((try? KeymapEditor.apply(keymap: keymap, layer: 0, position: 0,
                                        with: .transparent)) == nil, "apply without fileURL rejected")
        // Serialization that parses to a different binding is caught.
        expect((try? KeymapEditor.replacing(keymap: keymap, layer: 0, position: 0,
                                            with: .opaque(behavior: "trans", params: []))) == nil,
               "slot readback mismatch rejected")
        // Structure-truncating serialization hits the flat-list guard.
        expect((try? KeymapEditor.replacing(
            keymap: keymap, layer: 0, position: 0,
            with: .opaque(behavior: "trans &trans", params: []))) == nil,
               "token multiplication rejected")
        // replaceToken edges: end-of-line (no padding) and zero-run.
        expectEqual(KeymapEditor.replaceToken(source: "x &kp A\ny", range: 2..<7, newText: "&trans"),
                    "x &trans\ny", "line-end replacement unpadded")
        expectEqual(KeymapEditor.replaceToken(source: "&kp A>", range: 0..<5, newText: "&none"),
                    "&none>", "zero-run replacement")

        // Inference engine: remaining branches.
        var e = InferenceEngine(keymap: keymap)
        e.handle(.connection(true), at: at(0))                     // no-op event
        e.handle(.key(page: 7, usage: 0x04, down: false), at: at(0))  // release of unattributed key
        expectEqual(e.displayed, 0, "no-op events leave BASE")

        // Bare chord usage with no mods down: relaxed pool, most specific wins.
        e = InferenceEngine(keymap: keymap)
        e.handle(.key(page: 7, usage: 0x21, down: true), at: at(0))   // N4 alone
        expectEqual(e.displayed, 3, "orphan chord usage still maps to FUNC")
        expectEqual(e.highlighted, [32], "most specific chord wins when relaxed")

        // Release of a key attributed to a stale layer (keyLayer moved on).
        e = InferenceEngine(keymap: keymap)
        e.handle(.key(page: 7, usage: 0x5F, down: true), at: at(0))   // KP7 → NUM
        e.handle(.key(page: 7, usage: 0x04, down: true), at: at(0.1)) // A → BASE snap
        expectEqual(e.displayed, 0, "letter snaps base even while NUM key held")
        e.handle(.key(page: 7, usage: 0x5F, down: false), at: at(0.2))
        expectEqual(e.displayed, 0, "stale-layer release keeps BASE")

        // Modifier commit + release clears its highlight.
        e = InferenceEngine(keymap: keymap)
        e.handle(.key(page: 7, usage: 0xE0, down: true), at: at(0))
        e.tick(at: at(0.05))
        expectEqual(e.highlighted, [40], "committed mod lights hold face")
        e.handle(.key(page: 7, usage: 0xE0, down: false), at: at(0.1))
        expectEqual(e.highlighted, [], "mod release clears highlight")
        e.tick(at: at(5))
        expect(!e.needsTick, "engine settles (no pending state)")

        // reload keeps working after a keymap swap.
        e.reload(keymap: keymap)
        e.handle(.key(page: 7, usage: 0x5F, down: true), at: at(10))
        expectEqual(e.displayed, 2, "engine works after reload")

        // KeyStats: malformed keys are ignored by aggregations.
        var stats = KeyStats()
        stats.counts["garbage"] = 5
        stats.counts["1.2.3"] = 5
        stats.record(layer: 0, position: 1)
        expectEqual(stats.layerTotals(), [0: 1], "malformed keys ignored in layer totals")
        expectEqual(stats.top(10).count, 1, "malformed keys ignored in top")

        // Geometry Identifiable id.
        if let keys = try? GeometryLoader.load(json: Data(Fixtures.layoutJSON.utf8)) {
            expectEqual(keys[7].id, 7, "geometry id == index")
        }

        // ParseError renders its message.
        expectEqual("\(ParseError(message: "xyz"))", "xyz", "ParseError description")

        // Unclosed brace: matchBrace bails, parse fails.
        expect((try? KeymapParser.parse(source: "keymap { unclosed")) == nil, "unclosed brace rejected")

        // Non-string display-name falls back to the node name.
        if let odd = try? KeymapParser.parse(source: """
            keymap { lay { display-name = 5; bindings = <&kp A>; }; };
            """) {
            expectEqual(odd.layers[0].name, "lay", "non-string display-name falls back")
        } else {
            expect(false, "odd display-name parses")
        }

        // interpret: kinds absent from the fixture keymap.
        if case .tog(let n) = try! KeymapParser.interpret(token: "&tog 2") {
            expectEqual(n, 2, "tog parses")
        } else { expect(false, "&tog 2 parses") }
        if case KeyBinding.none = try! KeymapParser.interpret(token: "&none") {}
        else { expect(false, "&none parses") }
        if case .opaque = try! KeymapParser.interpret(token: "&tog x") {}
        else { expect(false, "tog non-int → opaque") }

        // Labels reached only via the UI path elsewhere.
        expectEqual(LabelProvider.label(for: .to(0), in: keymap).tap, "→BASE", "to label")
        expectEqual(LabelProvider.label(for: .mkp(1), in: keymap).tap, "M1", "mkp label")
        expectEqual(LabelProvider.label(for: .capsWord, in: keymap).tap, "CW", "caps word ui label")
        let trans = LabelProvider.label(for: .transparent, in: keymap)
        expect(trans.tap == "▽" && trans.dimmed, "transparent label dimmed")

        // Sub-expression fallbacks (?? / ternary else branches).
        var mh = BatteryHistory()
        mh.append(levels: ["peripheralX": 10], at: at(0))
        expectEqual(mh.knownRoles, [.peripheral(0)], "malformed peripheral key → index 0")
        expectEqual(CheatsheetGenerator.shortLabel(.bt(command: "BT_SEL", param: nil)), "BT0",
                    "bt sel without param label")
        expectEqual(KeyStats().maxCount, 0, "empty stats maxCount")

        // Engine: usages with no candidates, and comparator/stale branches.
        var e2 = InferenceEngine(keymap: keymap)
        e2.handle(.key(page: 7, usage: 0x64, down: true), at: at(0))   // unmapped usage
        expectEqual(e2.displayed, 0, "unmapped usage ignored")
        e2.handle(.key(page: 7, usage: 0xE6, down: true), at: at(0))   // RALT: no binding uses it
        e2.tick(at: at(0.1))
        expectEqual(e2.highlighted, [], "mod without candidates commits to nothing")

        e2 = InferenceEngine(keymap: keymap)
        e2.handle(.key(page: 7, usage: 0xE1, down: true), at: at(0))   // ⇧
        e2.handle(.key(page: 7, usage: 0x2D, down: true), at: at(0.01)) // MINUS → "_"
        expectEqual(e2.displayed, 1, "shift+minus reads as SYMBOL _")
        expectEqual(e2.highlighted, [11], "tie between SYMBOL slots resolved deterministically")

        e2 = InferenceEngine(keymap: keymap)
        e2.handle(.key(page: 7, usage: 0x5F, down: true), at: at(0))
        e2.handle(.key(page: 7, usage: 0x5F, down: false), at: at(0.1))
        e2.handle(.connection(false), at: at(9))                        // evidence long expired
        expectEqual(e2.displayed, 0, "stale key evidence falls through to BASE")

        // Parser: child-node fallthrough when a brace never closes in range,
        // and bindings-keyword guards.
        expect(KeymapParser.findChildNode(in: Array("x { y"), range: 0..<5) == nil,
               "unclosed child node skipped")
        if let odd2 = try? KeymapParser.parse(source: """
            keymap { l { bindings2 = 1; bindings = 5; bindings = <&kp A>; }; };
            """) {
            expectEqual(odd2.layers[0].bindings.count, 1, "bindings keyword guards retry")
        } else {
            expect(false, "bindings guard source parses")
        }
        if let meta = try? KeymapParser.parse(source: """
            keymap { meta { foo = 1; }; l { bindings = <&kp A>; }; };
            """) {
            expectEqual(meta.layers.count, 1, "child node without bindings skipped")
        } else {
            expect(false, "meta child source parses")
        }
        if case .opaque = try! KeymapParser.interpret(token: "&mo") {} else { expect(false, "&mo bare → opaque") }
        if case .opaque = try! KeymapParser.interpret(token: "&mt LCTRL NOKEY") {} else { expect(false, "mt bad tap → opaque") }
        if case .opaque = try! KeymapParser.interpret(token: "&to x") {} else { expect(false, "to non-int → opaque") }
        if case .bt(let cmd2, let param2) = try! KeymapParser.interpret(token: "&bt BT_CLR") {
            expectEqual(cmd2, "BT_CLR", "bare bt command parses")
            expectEqual(param2, nil, "bare bt has no param")
        } else { expect(false, "&bt BT_CLR parses") }

        // Editor apply(): full success path against a temp copy.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roba-hud-selftest-\(UUID().uuidString).keymap")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            try Data(Fixtures.keymap.utf8).write(to: tempURL)
            let onDisk = try KeymapParser.parse(source: Fixtures.keymap, fileURL: tempURL)
            let esc = KeyBinding.kp(Keycode(entry: KeycodeTable.byName["ESC"]!))
            let written = try KeymapEditor.apply(keymap: onDisk, layer: 0, position: 0, with: esc)
            let readBack = try String(contentsOf: tempURL, encoding: .utf8)
            expectEqual(readBack, written, "apply writes exactly the validated source")
            let reparsed = try KeymapParser.parse(source: readBack)
            expectEqual(reparsed.layers[0].bindings[0].binding.dtsText, "&kp ESC", "applied edit persists")
        } catch {
            expect(false, "apply round-trip failed: \(error)")
        }
    }
}
