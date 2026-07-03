import Foundation

/// Discharge-rate estimation from battery history ("残り約N日").
enum BatteryForecast {
    struct Estimate: Equatable {
        /// Percent lost per day (positive while discharging).
        let ratePerDay: Double
        /// Days until the level reaches `floor` (nil if not meaningfully draining).
        let daysLeft: Double?
    }

    /// Estimates from the most recent uninterrupted discharge segment.
    /// A rise of more than +1% between consecutive samples is treated as a
    /// charge event and cuts the segment. Requires ≥ minSpan of data and a
    /// net drop ≥ 1% to avoid noise-driven estimates.
    static func estimate(series: [(at: Date, level: Int)], now: Date,
                         floor: Int = 10, windowDays: Double = 7,
                         minSpan: TimeInterval = 6 * 3600) -> Estimate? {
        let cutoff = now.addingTimeInterval(-windowDays * 86400)
        let points = series.filter { $0.at >= cutoff }
        guard points.count >= 2 else { return nil }

        // Walk backwards to the last charge event.
        var start = 0
        for i in stride(from: points.count - 1, through: 1, by: -1)
        where points[i].level > points[i - 1].level + 1 {
            start = i
            break
        }
        let segment = Array(points[start...])
        guard let first = segment.first, let last = segment.last,
              segment.count >= 2,
              last.at.timeIntervalSince(first.at) >= minSpan,
              first.level - last.level >= 1 else { return nil }

        // Least-squares slope over the segment (%, per second).
        let t0 = first.at
        let xs = segment.map { $0.at.timeIntervalSince(t0) }
        let ys = segment.map { Double($0.level) }
        let n = Double(segment.count)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumXX = xs.map { $0 * $0 }.reduce(0, +)
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denominator

        let ratePerDay = -slope * 86400
        guard ratePerDay > 0.1 else { return nil }      // effectively flat

        let remaining = Double(last.level - floor)
        let daysLeft = remaining > 0 ? remaining / ratePerDay : 0
        return Estimate(ratePerDay: ratePerDay, daysLeft: daysLeft)
    }

    /// "−4.2%/日 ・ 残り約12日" style summary (nil = まだ推定できない).
    static func summary(_ estimate: Estimate?) -> String? {
        guard let estimate else { return nil }
        let rate = String(format: "−%.1f%%/日", estimate.ratePerDay)
        guard let days = estimate.daysLeft else { return rate }
        if days < 1 { return "\(rate) ・ 残り1日未満" }
        return "\(rate) ・ 残り約\(Int(days.rounded()))日"
    }
}
