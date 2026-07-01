import Foundation
import Observation

/// Per-(layer, position) key-press counters with JSON persistence and a
/// log-scaled heat value for the overlay.
struct KeyStats: Codable, Equatable {
    /// "layer.position" → count. String keys keep the JSON flat and Codable.
    var counts: [String: Int] = [:]
    var since: Date = Date()

    static func key(layer: Int, position: Int) -> String { "\(layer).\(position)" }

    mutating func record(layer: Int, position: Int) {
        counts[Self.key(layer: layer, position: position), default: 0] += 1
    }

    func count(layer: Int, position: Int) -> Int {
        counts[Self.key(layer: layer, position: position)] ?? 0
    }

    var total: Int { counts.values.reduce(0, +) }
    var maxCount: Int { counts.values.max() ?? 0 }

    /// 0…1, log-scaled against the global max so colors stay comparable
    /// across layers.
    func heat(layer: Int, position: Int) -> Double {
        let c = count(layer: layer, position: position)
        guard c > 0, maxCount > 0 else { return 0 }
        return log(1 + Double(c)) / log(1 + Double(maxCount))
    }

    /// Per-layer press totals, for the stats sheet.
    func layerTotals() -> [Int: Int] {
        var totals: [Int: Int] = [:]
        for (key, count) in counts {
            if let layer = Int(key.split(separator: ".").first ?? "") {
                totals[layer, default: 0] += count
            }
        }
        return totals
    }

    /// Top-N (layer, position, count), descending.
    func top(_ n: Int) -> [(layer: Int, position: Int, count: Int)] {
        counts.compactMap { key, count -> (Int, Int, Int)? in
            let parts = key.split(separator: ".")
            guard parts.count == 2, let l = Int(parts[0]), let p = Int(parts[1]) else { return nil }
            return (l, p, count)
        }
        .sorted { $0.2 > $1.2 }
        .prefix(n)
        .map { (layer: $0.0, position: $0.1, count: $0.2) }
    }
}

/// Owns persistence: Application Support/RoBaHUD/stats.json, saved with a
/// short debounce after changes and flushed on quit.
@MainActor
@Observable
final class StatsStore {
    private(set) var stats = KeyStats()
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var saveTimer: Timer?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoBaHUD", isDirectory: true)
        return dir.appendingPathComponent("stats.json")
    }

    init() {
        load()
    }

    func record(layer: Int, position: Int) {
        stats.record(layer: layer, position: position)
        dirty = true
        scheduleSave()
    }

    func reset() {
        stats = KeyStats()
        dirty = true
        flush()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let loaded = try? JSONDecoder().decode(KeyStats.self, from: data) else { return }
        stats = loaded
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard dirty else { return }
        dirty = false
        do {
            let dir = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(stats).write(to: Self.fileURL, options: .atomic)
        } catch {
            // Stats are best-effort; never disturb the HUD over them.
        }
    }
}
