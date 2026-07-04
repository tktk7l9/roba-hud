import SwiftUI

/// Usage statistics: top keys, per-layer distribution, reset.
struct StatsSheet: View {
    @Bindable var store: HUDStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("打鍵統計").font(.headline)
                Spacer()
                Button("閉じる") { store.showStatsSheet = false }
                    .keyboardShortcut(.cancelAction)
            }

            let stats = store.statsStore.stats
            Text("合計 \(stats.total) 打鍵 ・ \(stats.since.formatted(date: .abbreviated, time: .omitted)) から")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if stats.total == 0 {
                Text("まだデータがありません。roBa でタイピングすると蓄積されます。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                layerDistribution(stats)
                Divider()
                topKeys(stats)
                let chords = store.insightsStore.log.chordTotals()
                if !chords.isEmpty {
                    Divider()
                    topChords(chords)
                }
                let runs = store.insightsStore.log.runTotals()
                if !runs.isEmpty {
                    Divider()
                    topRuns(runs)
                }
            }

            HStack {
                Spacer()
                Button("リセット", role: .destructive) { store.statsStore.reset() }
                    .font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func layerDistribution(_ stats: KeyStats) -> some View {
        let totals = stats.layerTotals().sorted { $0.key < $1.key }
        let grand = max(stats.total, 1)
        return VStack(alignment: .leading, spacing: 3) {
            Text("レイヤー別").font(.system(size: 11, weight: .semibold))
            ForEach(totals, id: \.key) { layer, count in
                HStack(spacing: 6) {
                    Text(store.keymap?.layerName(layer) ?? "L\(layer)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: max(2, proxy.size.width * CGFloat(count) / CGFloat(grand)))
                    }
                    .frame(height: 10)
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private func topKeys(_ stats: KeyStats) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("よく使うキー Top 10").font(.system(size: 11, weight: .semibold))
            ForEach(Array(stats.top(10).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Text(store.keymap?.layerName(item.layer) ?? "L\(item.layer)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Text(keyName(layer: item.layer, position: item.position))
                        .font(.system(size: 11))
                    Spacer()
                    Text("\(item.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func topChords(_ chords: [(chord: String, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("よく使うショートカット Top 8").font(.system(size: 11, weight: .semibold))
            ForEach(chords.prefix(8), id: \.chord) { item in
                HStack(spacing: 6) {
                    Text(item.chord).font(.system(size: 11))
                    Spacer()
                    Text("\(item.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func topRuns(_ runs: [(key: String, stats: InsightsLog.RunStats)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("連打バースト(3連打以上)").font(.system(size: 11, weight: .semibold))
            ForEach(runs.prefix(5), id: \.key) { item in
                HStack(spacing: 6) {
                    Text(item.key).font(.system(size: 11))
                    Spacer()
                    Text("\(item.stats.runs)回 / 計\(item.stats.presses)打 / 最長\(item.stats.maxLength)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func keyName(layer: Int, position: Int) -> String {
        guard let keymap = store.keymap,
              keymap.layers.indices.contains(layer),
              keymap.layers[layer].bindings.indices.contains(position) else {
            return "#\(position)"
        }
        let label = LabelProvider.label(for: keymap.layers[layer].bindings[position].binding, in: keymap)
        return label.hold.map { "\(label.tap) (\($0))" } ?? label.tap
    }
}
