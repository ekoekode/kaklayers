import SwiftUI
import AppKit
import KaKLayersCore

/// One place for spacing, sizes and the key-unit grid, so everything lines up.
enum Theme {
    static let gutter = CGFloat(Metrics.gutter)
    static let gap = CGFloat(Metrics.keyGap)
    static let cornerKey: CGFloat = 7
    static let cornerCard: CGFloat = 12

    /// One key unit. The whole window is built from multiples of this.
    static func unit(forWidth w: CGFloat) -> CGFloat {
        min(CGFloat(Metrics.maxKeyUnit), max(CGFloat(Metrics.minKeyUnit), floor((w - 2 * gutter) / CGFloat(Keycodes.totalWidth))))
    }
    static func deckWidth(_ u: CGFloat) -> CGFloat { (CGFloat(Keycodes.totalWidth) * u).rounded() }
    static func deckHeight(_ u: CGFloat) -> CGFloat { (CGFloat(Keycodes.totalHeight) * u).rounded() }

    /// Snapped rectangle for a key: neighbours share rounded edges, so rows and columns align exactly.
    static func rect(_ k: KeyDef, unit u: CGFloat) -> CGRect {
        let x0 = (CGFloat(k.x) * u).rounded(), x1 = (CGFloat(k.x + k.w) * u).rounded()
        let y0 = (CGFloat(k.y) * u).rounded(), y1 = (CGFloat(k.y + k.h) * u).rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0 - gap, height: y1 - y0 - gap)
    }

    /// Base layer color: a neutral slate, so no layer color is ever confused with it.
    static let baseTint = Color(hex: "#7A8794")

    static let layerShapes = ["circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "star.fill"]
    static func shape(forLayerIndex i: Int) -> String { layerShapes[i % layerShapes.count] }

    // Semantic colors: adapt to light/dark/high-contrast automatically.
    static let window = Color(nsColor: .windowBackgroundColor)
    static let plate = Color.primary.opacity(0.045)
    static let cap = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)

    private static var legendCache: [String: CGFloat] = [:]
    static func legendWidth(_ s: String) -> CGFloat {
        if let w = legendCache[s] { return w }
        let w = CGFloat(TextFit.width(s, size: Metrics.legendFont, weight: 0.23)); legendCache[s] = w; return w
    }
}

func modSymbol(_ m: String) -> String {
    switch m { case "command": "⌘"; case "control": "⌃"; case "option": "⌥"; case "shift": "⇧"; default: m }
}

/// Wraps children onto new lines; never scrolls sideways and never clips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            var sz = s.sizeThatFits(.unspecified)
            if sz.width > width { sz.width = width }
            if x > 0 && x + sz.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}


// Snapshot rendering (ImageRenderer) cannot draw ScrollViews or drag handlers; these switches bypass them.
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshot: Bool { get { self[SnapshotKey.self] } set { self[SnapshotKey.self] = newValue } }
}

struct KeyDragDrop: ViewModifier {
    let app: AppState
    @Environment(\.snapshot) var snapshot
    let code: String
    func body(content: Content) -> some View {
        if snapshot { content } else {
            content
                .draggable("key:" + code)
                .dropDestination(for: String.self) { items, _ in
                    guard let s = items.first, s.hasPrefix("key:") else { return false }
                    app.remap(from: String(s.dropFirst(4)), to: code); return true
                }
        }
    }
}
