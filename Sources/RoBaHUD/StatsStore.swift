import Foundation
import Observation

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
