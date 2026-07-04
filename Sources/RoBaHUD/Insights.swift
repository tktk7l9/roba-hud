import Foundation

/// Content-free usage insights on top of KeyStats: chord frequencies,
/// per-app press counts and repeat bursts, bucketed per day so trends are
/// visible. Only aggregated counts are stored — the raw key stream (what was
/// typed) never touches disk, so nothing here can reconstruct text.
struct InsightsLog: Codable, Equatable {
    struct RunStats: Codable, Equatable {
        /// Bursts of length >= RunTracker.minLength.
        var runs = 0
        /// Total presses inside those bursts.
        var presses = 0
        var maxLength = 0

        mutating func merge(length: Int) {
            runs += 1
            presses += length
            maxLength = max(maxLength, length)
        }
    }

    struct Day: Codable, Equatable {
        /// Chord label ("⇧⌘4") → count. Only physically chorded modifiers
        /// count: a single key that *sends* mods (an LG(LS(N4)) binding)
        /// produces mods and key in the same report and is excluded upstream.
        var chords: [String: Int] = [:]
        /// Frontmost app bundle id → attributed key-down count.
        var apps: [String: Int] = [:]
        /// App bundle id → chord label → count, for app-specific advice.
        var appChords: [String: [String: Int]] = [:]
        /// Run key ("←", "⇧←", "⌫") → burst stats.
        var runs: [String: RunStats] = [:]
        /// Layer index (string key keeps the JSON flat) → press count.
        var layers: [String: Int] = [:]
    }

    var days: [String: Day] = [:]

    private static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    mutating func recordPress(layer: Int, chord: String?, app: String?, day: String) {
        var d = days[day] ?? Day()
        d.layers["\(layer)", default: 0] += 1
        if let app {
            d.apps[app, default: 0] += 1
        }
        if let chord {
            d.chords[chord, default: 0] += 1
            if let app {
                d.appChords[app, default: [:]][chord, default: 0] += 1
            }
        }
        days[day] = d
    }

    mutating func recordRun(key: String, length: Int, day: String) {
        var d = days[day] ?? Day()
        d.runs[key, default: RunStats()].merge(length: length)
        days[day] = d
    }

    /// Drop days older than `keepDays` (yyyy-MM-dd sorts lexicographically;
    /// DST drift is immaterial at this granularity).
    mutating func prune(keepDays: Int = 90, now: Date = Date()) {
        let cutoff = Self.dayKey(for: now.addingTimeInterval(-TimeInterval(keepDays) * 86400))
        days = days.filter { $0.key >= cutoff }
    }

    // MARK: - Aggregation across days (stats sheet / coach)

    /// Chord counts summed over all days, most frequent first. Shift+letter
    /// chords are ordinary typing, not shortcuts — excluded by default.
    func chordTotals(includeTypingShift: Bool = false) -> [(chord: String, count: Int)] {
        var totals: [String: Int] = [:]
        for day in days.values {
            for (chord, count) in day.chords {
                if !includeTypingShift && Self.isTypingShift(chord) { continue }
                totals[chord, default: 0] += count
            }
        }
        return totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (chord: $0.key, count: $0.value) }
    }

    /// Run stats summed over all days, most presses first.
    func runTotals() -> [(key: String, stats: RunStats)] {
        var totals: [String: RunStats] = [:]
        for day in days.values {
            for (key, stats) in day.runs {
                var merged = totals[key] ?? RunStats()
                merged.runs += stats.runs
                merged.presses += stats.presses
                merged.maxLength = max(merged.maxLength, stats.maxLength)
                totals[key] = merged
            }
        }
        return totals.sorted { $0.value.presses != $1.value.presses
            ? $0.value.presses > $1.value.presses : $0.key < $1.key }
            .map { (key: $0.key, stats: $0.value) }
    }

    /// "⇧A" … "⇧Z": capitals typed with a held shift.
    static func isTypingShift(_ chord: String) -> Bool {
        guard chord.count == 2, chord.first == "⇧", let last = chord.last else { return false }
        return last.isLetter && last.isUppercase && last.isASCII
    }
}

/// Label building for insights: (page, usage) → glyph via the keycode table,
/// modifier sets → ⌃⌥⇧⌘ strings (left/right collapsed).
enum InsightsNaming {
    /// Base entries only (no implicit mods), so DOLLAR never shadows N4.
    static let glyphByUsage: [UInt64: String] = {
        var map: [UInt64: String] = [:]
        for entry in KeycodeTable.entries where entry.implicitMods.isEmpty {
            let key = UInt64(entry.page) << 32 | UInt64(entry.usage)
            if map[key] == nil { map[key] = entry.glyph }
        }
        return map
    }()

    static func keyGlyph(page: UInt32, usage: UInt32) -> String? {
        if page == 0x09 { return "MB\(usage)" }
        return glyphByUsage[UInt64(page) << 32 | UInt64(usage)]
    }

    /// Deduped glyphs in Apple's canonical ⌃⌥⇧⌘ order.
    static func modGlyphs(_ mods: Set<UInt32>) -> String {
        var glyphs: [String] = []
        for mod in mods.compactMap(Mod.fromUsage).sorted(by: { $0.displayRank < $1.displayRank })
        where !glyphs.contains(mod.glyph) {
            glyphs.append(mod.glyph)
        }
        return glyphs.joined()
    }

    /// nil when no physically chorded mods or the key is unknown.
    static func chordLabel(page: UInt32, usage: UInt32, mods: Set<UInt32>) -> String? {
        guard !mods.isEmpty, let glyph = keyGlyph(page: page, usage: usage) else { return nil }
        let prefix = modGlyphs(mods)
        guard !prefix.isEmpty else { return nil }
        return prefix + glyph
    }

    /// Keys whose bursts are worth analyzing (navigation / deletion).
    private static let runUsages: Set<UInt32> = [
        0x50, 0x4F, 0x52, 0x51,   // ← → ↑ ↓
        0x2A, 0x4C,               // ⌫ ⌦
        0x2B,                     // ⇥
    ]

    /// nil when the key is not run-tracked. Mods stay in the key ("⌥⌫" bursts
    /// suggest ⌘⌫ the same way "⌫" bursts suggest ⌥⌫).
    static func runKey(page: UInt32, usage: UInt32, mods: Set<UInt32>) -> String? {
        guard page == 0x07, runUsages.contains(usage),
              let glyph = keyGlyph(page: page, usage: usage) else { return nil }
        return modGlyphs(mods) + glyph
    }
}

/// Burst detector: consecutive presses of the same run key with gaps within
/// `maxGap`. Pure state machine — the owner feeds attributed key-downs and
/// expires the pending burst before persisting.
struct RunTracker: Equatable {
    static let minLength = 3
    static let maxGap: TimeInterval = 1.2

    private var key: String?
    private var length = 0
    private var lastAt = Date.distantPast

    /// Feed a key-down (`runKey` nil for untracked keys). Returns a finished
    /// burst when this press ends the previous one.
    mutating func track(runKey: String?, at now: Date) -> (key: String, length: Int)? {
        var finished: (key: String, length: Int)?
        let gapExceeded = now.timeIntervalSince(lastAt) > Self.maxGap
        if let current = key, runKey != current || gapExceeded {
            if length >= Self.minLength { finished = (current, length) }
            key = nil
            length = 0
        }
        if let runKey {
            key = runKey
            length += 1
            lastAt = now
        }
        return finished
    }

    /// Finish a stale pending burst (call before persisting; a burst still in
    /// progress is kept so it isn't split).
    mutating func expire(at now: Date) -> (key: String, length: Int)? {
        guard let current = key, now.timeIntervalSince(lastAt) > Self.maxGap else { return nil }
        let finished = length >= Self.minLength ? (key: current, length: length) : nil
        key = nil
        length = 0
        return finished
    }
}
