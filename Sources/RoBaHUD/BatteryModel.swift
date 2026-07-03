import Foundation

/// Which half a GATT battery characteristic belongs to.
/// ZMK's central proxies peripheral batteries as extra Battery Level
/// characteristics whose Characteristic User Description (0x2901) reads
/// "Peripheral N"; the central's own characteristic has no such CUD.
enum BatteryRole: Equatable, Hashable, Codable {
    case central
    case peripheral(Int)

    static func from(cud: String?) -> BatteryRole {
        guard let cud, cud.hasPrefix("Peripheral ") else { return .central }
        return .peripheral(Int(cud.dropFirst("Peripheral ".count)) ?? 0)
    }

    /// roBa: the right half is the split central.
    var displayName: String {
        switch self {
        case .central: "右"
        case .peripheral(0): "左"
        case .peripheral(let n): "P\(n)"
        }
    }

    /// Stable key for persistence / dictionaries.
    var key: String {
        switch self {
        case .central: "central"
        case .peripheral(let n): "peripheral\(n)"
        }
    }
}

enum BatterySeverity: Equatable {
    case ok, low, critical

    static func of(level: Int) -> BatterySeverity {
        if level <= 10 { return .critical }
        if level <= 20 { return .low }
        return .ok
    }
}

/// Latest known level per half.
struct BatteryLevels: Equatable {
    var levels: [String: Int] = [:]     // BatteryRole.key → 0…100
    var updatedAt: Date?

    mutating func set(role: BatteryRole, level: Int, at date: Date) {
        levels[role.key] = max(0, min(100, level))
        updatedAt = date
    }

    func level(of role: BatteryRole) -> Int? { levels[role.key] }
}

/// Decides when a "battery low" notification should fire.
/// Fires on a downward crossing of the threshold; re-arms only after the
/// level recovers above threshold + hysteresis (i.e. after a recharge), so
/// jitter around the threshold can't spam notifications.
struct BatteryNotificationPolicy {
    var threshold: Int = 20
    var hysteresis: Int = 5
    /// roles currently "fired" (below threshold, notification already sent)
    private var fired: Set<String> = []

    mutating func shouldNotify(role: BatteryRole, level: Int) -> Bool {
        if level > threshold + hysteresis {
            fired.remove(role.key)
            return false
        }
        if level <= threshold, !fired.contains(role.key) {
            fired.insert(role.key)
            return true
        }
        return false
    }
}

/// One history sample. Levels may be partial (a half may be unknown).
struct BatterySample: Codable, Equatable {
    let at: Date
    let levels: [String: Int]
}

/// Rolling battery history for the graph. Samples are appended when a level
/// changes and pruned beyond the retention window.
struct BatteryHistory: Codable, Equatable {
    var samples: [BatterySample] = []
    var retentionDays: Double = 30

    /// Appends a sample unless it duplicates the previous one's levels.
    mutating func append(levels: [String: Int], at date: Date) {
        guard !levels.isEmpty else { return }
        if let last = samples.last, last.levels == levels { return }
        samples.append(BatterySample(at: date, levels: levels))
        prune(now: date)
    }

    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retentionDays * 86400)
        if let firstKept = samples.firstIndex(where: { $0.at >= cutoff }) {
            if firstKept > 0 { samples.removeFirst(firstKept) }
        } else if !samples.isEmpty {
            samples.removeAll()
        }
    }

    /// Series for one role within the last `days`, oldest first.
    func series(role: BatteryRole, days: Double, now: Date) -> [(at: Date, level: Int)] {
        let cutoff = now.addingTimeInterval(-days * 86400)
        return samples.compactMap { sample in
            guard sample.at >= cutoff, let level = sample.levels[role.key] else { return nil }
            return (sample.at, level)
        }
    }

    /// Roles that ever appear in the retained window (central first).
    var knownRoles: [BatteryRole] {
        var keys = Set<String>()
        for sample in samples { keys.formUnion(sample.levels.keys) }
        var roles: [BatteryRole] = []
        if keys.contains("central") { roles.append(.central) }
        for key in keys.sorted() where key.hasPrefix("peripheral") {
            roles.append(.peripheral(Int(key.dropFirst("peripheral".count)) ?? 0))
        }
        return roles
    }
}
