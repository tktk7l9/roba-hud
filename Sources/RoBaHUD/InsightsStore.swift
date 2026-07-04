import AppKit
import Foundation
import Observation

/// Owns persistence: Application Support/RoBaHUD/insights.json, saved with a
/// short debounce like StatsStore, plus the frontmost-app cache used to
/// attribute presses to apps (NSWorkspace notification, no polling).
@MainActor
@Observable
final class InsightsStore {
    private(set) var log = InsightsLog()
    @ObservationIgnored private var tracker = RunTracker()
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private var frontmostApp: String?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoBaHUD", isDirectory: true)
        return dir.appendingPathComponent("insights.json")
    }

    init() {
        load()
        frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in self?.frontmostApp = id }
        }
    }

    /// One attributed key-down from the engine. `mods` are the physically
    /// chorded modifiers (implicit / same-report mods already excluded).
    func record(layer: Int, page: UInt32, usage: UInt32, mods: Set<UInt32>, at now: Date = Date()) {
        let day = InsightsLog.dayKey(for: now)
        let chord = InsightsNaming.chordLabel(page: page, usage: usage, mods: mods)
        log.recordPress(layer: layer, chord: chord, app: frontmostApp, day: day)
        if let finished = tracker.track(runKey: InsightsNaming.runKey(page: page, usage: usage, mods: mods), at: now) {
            log.recordRun(key: finished.key, length: finished.length, day: day)
        }
        dirty = true
        scheduleSave()
    }

    func reset() {
        log = InsightsLog()
        tracker = RunTracker()
        dirty = true
        flush()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let loaded = try? JSONDecoder().decode(InsightsLog.self, from: data) else { return }
        log = loaded
        log.prune()
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
        let now = Date()
        if let finished = tracker.expire(at: now) {
            log.recordRun(key: finished.key, length: finished.length, day: InsightsLog.dayKey(for: now))
            dirty = true
        }
        guard dirty else { return }
        dirty = false
        do {
            let dir = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(log).write(to: Self.fileURL, options: .atomic)
        } catch {
            // Insights are best-effort; never disturb the HUD over them.
        }
    }
}
