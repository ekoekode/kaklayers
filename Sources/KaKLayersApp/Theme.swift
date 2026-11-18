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
    /// Smallest window height with a single row of layer chips.
    static let minWindowHeight: CGFloat = 780
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
/// A rectangle with its own radius on each corner (RoundedRectangle only has one).
/// Like CSS, radii that would overlap along a side are scaled down together, so a corner can be as round as the side allows.
struct CornerShape: Shape {
    var tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat
    func path(in r: CGRect) -> Path {
        var tl = max(tl, 0.01), tr = max(tr, 0.01), br = max(br, 0.01), bl = max(bl, 0.01)
        let k = min(1, r.width / (tl + tr), r.width / (bl + br), r.height / (tl + bl), r.height / (tr + br))
        tl *= k; tr *= k; br *= k; bl *= k
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}

/// The outline of one key cap: a rounded rectangle for keys, mouse-button shapes for the mouse.
/// The mouse buttons' outer corners are the body's corner radius minus the inset, so they stay concentric with the outline.
struct CapShape: Shape {
    let kind: KeyShape
    var unit: CGFloat = 60
    static let mouseInset: CGFloat = 5
    /// One radius for all four corners of the body; the buttons' outer corners use it minus the inset.
    static func mouseBodyRadius(unit u: CGFloat) -> CGFloat { mouseOuterRadius(unit: u) + mouseInset }
    static func mouseOuterRadius(unit u: CGFloat) -> CGFloat { 1.0 * u }
    func path(in r: CGRect) -> Path {
        let c = Theme.cornerKey, s = min(r.width, r.height)
        let outer = Self.mouseOuterRadius(unit: unit)
        switch kind {
        case .rect: return CornerShape(tl: c, tr: c, br: c, bl: c).path(in: r)
        case .mouseLeft: return CornerShape(tl: outer, tr: c * 0.7, br: c, bl: c).path(in: r)
        case .mouseRight: return CornerShape(tl: c * 0.7, tr: outer, br: c, bl: c).path(in: r)
        case .wheel: return CornerShape(tl: s / 2, tr: s / 2, br: s / 2, bl: s / 2).path(in: r)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    /// Child sizes are measured once per update (not on every layout call), and each line-breaking result is remembered per width.
    struct Cache {
        var sizes: [CGSize]
        var memo: [CGFloat: (size: CGSize, frames: [CGRect])] = [:]
    }
    func makeCache(subviews: Subviews) -> Cache { Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) }) }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        arrange(width: proposal.width ?? .infinity, cache: &cache).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let r = arrange(width: bounds.width, cache: &cache)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(width: CGFloat, cache: inout Cache) -> (size: CGSize, frames: [CGRect]) {
        if let hit = cache.memo[width] { return hit }
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var frames: [CGRect] = []
        for var sz in cache.sizes {
            if sz.width > width { sz.width = width }
            if x > 0 && x + sz.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        let result = (size: CGSize(width: maxW, height: y + rowH), frames: frames)
        cache.memo[width] = result
        return result
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
                    app.drop.target = nil
                    guard let s = items.first, s.hasPrefix("key:") else { return false }
                    app.copySettings(from: String(s.dropFirst(4)), to: code); return true
                } isTargeted: { on in
                    if on { app.drop.target = code } else if app.drop.target == code { app.drop.target = nil }
                }
        }
    }
}
