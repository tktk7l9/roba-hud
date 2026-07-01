import Foundation

/// All heuristics in one place. Times in seconds.
struct InferenceTuning {
    /// Mirrors CONFIG_ZMK_POINTING_...AUTOMOUSE_TIMEOUT_MS=700 in the firmware.
    var mouseDecay: TimeInterval = 0.7
    /// Scroll requires an invisible hold (&mo 5 / 英数); the wheel stream is
    /// the only evidence, so decay quickly after it stops.
    var scrollDecay: TimeInterval = 0.4
    /// How long keyboard-derived layer evidence outlives the last key release.
    var layerDecay: TimeInterval = 1.0
    /// Modifier downs younger than this may still be consumed by a chord
    /// (implicit-shift suppression) and are not yet attributed to a key.
    var chordWindow: TimeInterval = 0.04
}

/// Maps incoming HID usages back to keymap positions.
/// Layers are invisible on the host side; every entry is *evidence* that its
/// layer is active. &trans slots are indexed only where they resolve (base),
/// so evidence always points at an explicit binding.
struct ReverseIndex {
    struct Candidate {
        let layer: Int
        let position: Int
        let isHoldFace: Bool
        /// Modifier usages (0xE0–0xE7) this binding sends alongside the base
        /// usage — from LS()-style wrappers and shifted aliases like PERCENT.
        let implicitModUsages: Set<UInt32>
    }

    private var map: [UInt64: [Candidate]] = [:]

    static func key(page: UInt32, usage: UInt32) -> UInt64 {
        UInt64(page) << 32 | UInt64(usage)
    }

    init(keymap: Keymap) {
        func add(_ page: UInt32, _ usage: UInt32, _ candidate: Candidate) {
            map[Self.key(page: page, usage: usage), default: []].append(candidate)
        }
        func modUsages(_ mods: [Mod]) -> Set<UInt32> { Set(mods.map(\.usage)) }
        func addKeycode(_ code: Keycode, layer: Int, position: Int, isHold: Bool) {
            add(code.entry.page, code.entry.usage,
                Candidate(layer: layer, position: position, isHoldFace: isHold,
                          implicitModUsages: modUsages(code.effectiveMods)))
        }

        for layer in keymap.layers {
            for (position, parsed) in layer.bindings.enumerated() {
                switch parsed.binding {
                case .kp(let code):
                    addKeycode(code, layer: layer.index, position: position, isHold: false)
                case .lt(_, let tap):
                    addKeycode(tap, layer: layer.index, position: position, isHold: false)
                case .mt(let hold, let tap):
                    addKeycode(tap, layer: layer.index, position: position, isHold: false)
                    addKeycode(hold, layer: layer.index, position: position, isHold: true)
                case .mkp(let n):
                    add(0x09, UInt32(n),
                        Candidate(layer: layer.index, position: position,
                                  isHoldFace: false, implicitModUsages: []))
                default:
                    break   // mo/to/bt/out/… emit no HID
                }
            }
        }
    }

    func candidates(page: UInt32, usage: UInt32) -> [Candidate] {
        map[Self.key(page: page, usage: usage)] ?? []
    }
}

/// Pure state machine: HID events (+ injected clock) in, displayed layer and
/// per-position highlights out. No timers of its own — the owner calls
/// `tick(at:)` while `needsTick` is true.
struct InferenceEngine {
    var tuning = InferenceTuning()
    /// While set, the displayed layer never changes (manual pin).
    var pinned: Int?

    private var index: ReverseIndex
    private var mouseLayer = 4
    private var scrollLayer = 5
    private(set) var displayed = 0

    /// usageKey → (layer, position) for currently held keys.
    private var attributions: [UInt64: (layer: Int, position: Int)] = [:]
    /// Raw modifier usages currently reported down.
    private var downMods: Set<UInt32> = []
    /// Modifier downs awaiting chord attribution (usage → down time).
    private var pendingMods: [UInt32: Date] = [:]
    /// Modifiers consumed as part of a chord (suppressed until release).
    private var consumedMods: Set<UInt32> = []

    /// Most recent key-down attribution, for the owner to consume (stats).
    var lastPress: (layer: Int, position: Int)?

    private var lastMotion: Date?
    private var lastScroll: Date?
    /// Layer suggested by the most recent key evidence.
    private var keyLayer = 0
    /// Key evidence remains valid until this deadline once all its keys are up.
    private var keyEvidenceUntil: Date?

    init(keymap: Keymap) {
        index = ReverseIndex(keymap: keymap)
        mouseLayer = keymap.mouseLayer
        scrollLayer = keymap.scrollLayer
    }

    mutating func reload(keymap: Keymap) {
        index = ReverseIndex(keymap: keymap)
        mouseLayer = keymap.mouseLayer
        scrollLayer = keymap.scrollLayer
        attributions.removeAll()
    }

    /// Positions to light on the currently displayed layer.
    var highlighted: Set<Int> {
        Set(attributions.values.filter { $0.layer == displayed }.map(\.position))
    }

    var needsTick: Bool {
        !pendingMods.isEmpty || lastMotion != nil || lastScroll != nil
            || keyEvidenceUntil != nil || !attributions.isEmpty
    }

    // MARK: - Event intake

    mutating func handle(_ event: HIDEvent, at now: Date) {
        switch event {
        case .key(let page, let usage, let down):
            if page == 0x07, (0xE0...0xE7).contains(usage) {
                handleModifier(usage: usage, down: down, at: now)
            } else if down {
                handleKeyDown(page: page, usage: usage, at: now)
            } else {
                handleKeyUp(page: page, usage: usage, at: now)
            }
        case .button(let number, let down):
            if down {
                handleKeyDown(page: 0x09, usage: UInt32(number), at: now)
            } else {
                handleKeyUp(page: 0x09, usage: UInt32(number), at: now)
            }
        case .pointerMotion:
            lastMotion = now
        case .scroll:
            lastScroll = now
        case .connection:
            break
        }
        commitExpiredPendingMods(at: now)
        refreshDisplayed(at: now)
    }

    mutating func tick(at now: Date) {
        commitExpiredPendingMods(at: now)
        // Drop expired transient signals so needsTick can settle to false.
        if let lm = lastMotion, now.timeIntervalSince(lm) > tuning.mouseDecay { lastMotion = nil }
        if let ls = lastScroll, now.timeIntervalSince(ls) > tuning.scrollDecay { lastScroll = nil }
        // Key evidence only expires once no key attributed to that layer is
        // still held (a held NUM arrow keeps NUM alive indefinitely).
        if let ku = keyEvidenceUntil, now >= ku,
           !attributions.values.contains(where: { $0.layer == keyLayer }) {
            keyEvidenceUntil = nil
            keyLayer = 0
        }
        refreshDisplayed(at: now)
    }

    // MARK: - Keys

    private mutating func handleKeyDown(page: UInt32, usage: UInt32, at now: Date) {
        guard let chosen = choose(candidates: index.candidates(page: page, usage: usage), at: now) else { return }
        attributions[ReverseIndex.key(page: page, usage: usage)] = (chosen.layer, chosen.position)
        lastPress = (chosen.layer, chosen.position)
        // Chord attribution: implicit mods of the chosen binding belong to it,
        // not to some standalone modifier key — swallow their pending entries.
        for mod in chosen.implicitModUsages where pendingMods[mod] != nil || downMods.contains(mod) {
            pendingMods.removeValue(forKey: mod)
            consumedMods.insert(mod)
            attributions.removeValue(forKey: ReverseIndex.key(page: 0x07, usage: mod))
        }
        keyLayer = chosen.layer
        keyEvidenceUntil = now.addingTimeInterval(tuning.layerDecay)
    }

    private mutating func handleKeyUp(page: UInt32, usage: UInt32, at now: Date) {
        let key = ReverseIndex.key(page: page, usage: usage)
        guard let released = attributions.removeValue(forKey: key) else { return }
        if released.layer == keyLayer {
            keyEvidenceUntil = now.addingTimeInterval(tuning.layerDecay)
        }
    }

    private mutating func handleModifier(usage: UInt32, down: Bool, at now: Date) {
        if down {
            downMods.insert(usage)
            pendingMods[usage] = now
        } else {
            downMods.remove(usage)
            pendingMods.removeValue(forKey: usage)
            consumedMods.remove(usage)
            handleKeyUp(page: 0x07, usage: usage, at: now)
        }
    }

    /// Pending modifiers older than the chord window were pressed for their
    /// own sake (mt holds, explicit &kp mods): attribute them like keys.
    private mutating func commitExpiredPendingMods(at now: Date) {
        for (usage, downAt) in pendingMods where now.timeIntervalSince(downAt) >= tuning.chordWindow {
            pendingMods.removeValue(forKey: usage)
            guard !consumedMods.contains(usage) else { continue }
            guard let chosen = choose(candidates: index.candidates(page: 0x07, usage: usage), at: now) else { continue }
            attributions[ReverseIndex.key(page: 0x07, usage: usage)] = (chosen.layer, chosen.position)
            keyLayer = chosen.layer
            keyEvidenceUntil = now.addingTimeInterval(tuning.layerDecay)
        }
    }

    /// Candidate selection: (1) implicit mods must be covered by the mods
    /// actually down (relaxed if nothing matches), (2) most-specific chord
    /// wins, (3) the currently displayed layer wins, (4) lowest layer.
    private func choose(candidates: [ReverseIndex.Candidate], at now: Date) -> ReverseIndex.Candidate? {
        guard !candidates.isEmpty else { return nil }
        let matching = candidates.filter { $0.implicitModUsages.isSubset(of: downMods) }
        let pool = matching.isEmpty ? candidates : matching
        let maxSpecificity = pool.map { $0.implicitModUsages.count }.max() ?? 0
        let specific = pool.filter { $0.implicitModUsages.count == maxSpecificity }
        let current = effectiveDisplayed(at: now)
        if let onCurrent = specific.first(where: { $0.layer == current }) {
            return onCurrent
        }
        return specific.min { $0.layer < $1.layer }
    }

    // MARK: - Displayed layer

    /// What the display *should* be right now, from current evidence.
    /// Priority: pin > scroll stream > pointer stream > key evidence > base.
    private func effectiveDisplayed(at now: Date) -> Int {
        if let pinned { return pinned }
        if let ls = lastScroll, now.timeIntervalSince(ls) <= tuning.scrollDecay { return scrollLayer }
        if let lm = lastMotion, now.timeIntervalSince(lm) <= tuning.mouseDecay { return mouseLayer }
        if keyLayer != 0 {
            if attributions.values.contains(where: { $0.layer == keyLayer }) { return keyLayer }
            if let until = keyEvidenceUntil, now < until { return keyLayer }
        }
        return 0
    }

    private mutating func refreshDisplayed(at now: Date) {
        displayed = effectiveDisplayed(at: now)
    }
}
