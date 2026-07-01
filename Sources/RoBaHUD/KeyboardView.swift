import SwiftUI

/// Renders the 43-key roBa layout for the displayed layer.
struct KeyboardView: View {
    var store: HUDStore

    var body: some View {
        let bounds = store.layoutBounds
        GeometryReader { proxy in
            let scale = min(proxy.size.width / bounds.width,
                            proxy.size.height / bounds.height)
            let xOffset = (proxy.size.width - bounds.width * scale) / 2
            let yOffset = (proxy.size.height - bounds.height * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(store.geometry) { key in
                    let center = key.center
                    KeyCapView(
                        label: label(for: key.index),
                        highlighted: store.highlighted.contains(key.index),
                        unit: scale
                    )
                    .frame(width: scale * 0.94, height: scale * 0.94)
                    .rotationEffect(.degrees(key.rotation))
                    .position(x: xOffset + (center.x - bounds.minX) * scale,
                              y: yOffset + (center.y - bounds.minY) * scale)
                }
            }
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
    }

    /// Label for a position on the displayed layer. &trans shows the
    /// fall-through (base layer) binding dimmed — more useful than "▽".
    private func label(for position: Int) -> KeyLabel {
        guard let keymap = store.keymap,
              keymap.layers.indices.contains(store.displayedLayer) else {
            return KeyLabel("")
        }
        let binding = keymap.layers[store.displayedLayer].bindings[position].binding
        if case .transparent = binding {
            let effective = keymap.effective(layer: store.displayedLayer, position: position)
            if case .transparent = effective { return KeyLabel("▽", dimmed: true) }
            let base = LabelProvider.label(for: effective, in: keymap)
            return KeyLabel(base.tap, hold: base.hold, dimmed: true)
        }
        return LabelProvider.label(for: binding, in: keymap)
    }
}

struct KeyCapView: View {
    let label: KeyLabel
    let highlighted: Bool
    let unit: CGFloat           // points per key unit, for font scaling

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.12)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: unit * 0.12)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            VStack(spacing: unit * 0.02) {
                Text(label.tap)
                    .font(.system(size: unit * 0.30, weight: .medium))
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                if let hold = label.hold, !hold.isEmpty {
                    Text(hold)
                        .font(.system(size: unit * 0.17, weight: .regular))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(unit * 0.06)
            .foregroundStyle(label.dimmed && !highlighted ? Color.secondary.opacity(0.55) : Color.primary)
        }
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }

    private var fillColor: Color {
        if highlighted { return Color.accentColor.opacity(0.85) }
        return Color(nsColor: .controlBackgroundColor).opacity(label.dimmed ? 0.4 : 0.9)
    }
}
