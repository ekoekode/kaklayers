import SwiftUI
import KaKLayersCore

enum Badge: Hashable {
    case shape(String, String)   // SF symbol, layer color hex
    case text(String)
}

/// Hover state lives apart from AppState so moving the mouse over keys never redraws the keyboard.
/// The hover card only appears after the pointer rests on a key, so sweeping across the keyboard costs nothing.
/// The key currently under a dragged key. Only each cap's DropHighlight observes it.
final class DropModel: ObservableObject {
    @Published var target: String?
}

/// Lights up the key under the cursor while another key is dragged onto it.
struct DropHighlight: View {
    let code: String
    let tint: Color
    @ObservedObject var model: DropModel
    var body: some View {
        if model.target == code {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerKey).fill(tint.opacity(0.28))
                RoundedRectangle(cornerRadius: Theme.cornerKey + 2).stroke(tint.opacity(0.25), lineWidth: 8).padding(-3)
                RoundedRectangle(cornerRadius: Theme.cornerKey).stroke(tint, lineWidth: 3)
            }
            .allowsHitTesting(false)
        }
    }
}

final class HoverModel: ObservableObject {
    @Published var key: String? = nil
    private var work: DispatchWorkItem?
    func enter(_ k: String) {
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.key = k }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
    }
    func leave(_ k: String) {
        work?.cancel(); work = nil
        if key == k { key = nil }
    }
}

/// Everything one key cap needs, computed once per change. Equatable, so unchanged caps are skipped.
struct CapModel: Equatable {
    var key: KeyDef
    var size: CGSize
    var used: Bool
    var isBase: Bool
    var tintHex: String?
    var content: CapContent?
    var badges: [Badge]
    var triggerHex: String?
    var selected: Bool
    var accessibility: String
}

extension AppState {
    /// One pass over bindings instead of a search per key.
    func capModels(unit: CGFloat) -> [CapModel] {
        let layer = activeLayer
        let layerObj = project.layer(layer)
        var single: [String: KeyBinding] = [:]
        var chordKeys = Set<String>()
        var variantCount: [String: Int] = [:]
        var usedByLayer: [String: Set<String>] = [:]
        for b in project.bindings where b.enabled || true {
            guard !b.isEmpty else { continue }
            if b.fromKeys.count == 1, let k = b.fromKeys.first {
                usedByLayer[b.layerId ?? "", default: []].insert(k)
                if b.layerId == layer {
                    variantCount[k, default: 0] += 1
                    if single[k] == nil || (b.fromModifiers.isEmpty && !(single[k]!.fromModifiers.isEmpty)) { single[k] = b }
                }
            } else if b.layerId == layer { b.fromKeys.forEach { chordKeys.insert($0) } }
        }
        var triggers: [String: [(Int, Layer)]] = [:]
        for (i, l) in project.layers.enumerated() { for k in l.triggerKeys { triggers[k, default: []].append((i, l)) } }
        let tintHex = layerObj?.colorHex
        let layerName = layerObj?.name ?? "Base"

        return Keycodes.layout(layoutKind, mediaRow: mediaRow).map { k in
            let r = Theme.rect(k, unit: unit)
            let b = single[k.code]
            let content = b.map { KeyGlyphs.content(for: $0, budget: Metrics.rowBudget(unit: Double(unit), widthUnits: k.w)) }
            var badges: [Badge] = []
            for (i, l) in triggers[k.code] ?? [] { badges.append(.shape(Theme.shape(forLayerIndex: i), l.colorHex)) }
            if chordKeys.contains(k.code) { badges.append(.text("⛓")) }
            if let n = content?.moreRoles, n > 0 { badges.append(.text("+\(n)")) }
            if (variantCount[k.code] ?? 0) > 1 { badges.append(.text("⌘")) }
            if showAllLayers {
                for (i, l) in project.layers.enumerated() where l.id != layer && (usedByLayer[l.id]?.contains(k.code) ?? false) {
                    badges.append(.shape(Theme.shape(forLayerIndex: i), l.colorHex))
                }
            }
            var a11y = Keycodes.label(k.code)
            if let b {
                a11y += ", in \(layerName) layer: " + [("on press", b.onPress), ("on tap", b.onTap), ("on hold", b.onHold), ("on double tap", b.onDoubleTap), ("on release", b.onRelease)]
                    .filter { !$0.1.isEmpty }.map { "\($0.0), " + $0.1.map(KeyGlyphs.words).joined(separator: ", then ") }.joined(separator: "; ")
            }
            return CapModel(key: k, size: r.size, used: b != nil, isBase: layer == nil, tintHex: tintHex, content: content,
                            badges: badges, triggerHex: triggers[k.code]?.first?.1.colorHex,
                            selected: selectedKey == k.code || (editingChord?.contains(k.code) ?? false), accessibility: a11y)
        }
    }
}

/// The full-width keyboard. Every key is placed on the shared unit grid.
struct KeyboardDeck: View {
    @EnvironmentObject var app: AppState
    let unit: CGFloat

    var body: some View {
        let models = app.capModels(unit: unit)
        ZStack(alignment: .topLeading) {
            MousePlate(unit: unit)
            ForEach(models, id: \.key.code) { m in
                let r = Theme.rect(m.key, unit: unit)
                KeyCapView(m: m, unit: unit, app: app).equatable()
                    .offset(x: r.minX, y: r.minY)
                    .zIndex(m.selected ? 2 : 0)
            }
            HoverCard(unit: unit, hover: app.hover)
        }
        .frame(width: Theme.deckWidth(unit) - Theme.gap, height: Theme.deckHeight(unit) - Theme.gap, alignment: .topLeading)
    }
}

/// A quiet plate behind the mouse buttons so they read as one group, with a caption in the free row below.
struct MousePlate: View {
    let unit: CGFloat
    var body: some View {
        let pad: CGFloat = 5
        let x0 = (15.5 * unit).rounded() - pad, x1 = (18.5 * unit).rounded() - Theme.gap + pad
        let y0 = (3.5 * unit).rounded() - pad, y1 = (5.5 * unit).rounded() - Theme.gap + pad
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.cornerKey + 4).fill(Theme.plate)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerKey + 4).stroke(Theme.hairline.opacity(0.55), lineWidth: 1))
                .frame(width: x1 - x0, height: y1 - y0).offset(x: x0, y: y0)
            HStack(spacing: 5) {
                Image(systemName: "computermouse").font(.system(size: 10, weight: .semibold))
                Text("MOUSE").font(.system(size: 10, weight: .semibold)).tracking(0.8)
            }
            .foregroundStyle(.secondary)
            .offset(x: x0 + 6, y: (5.5 * unit).rounded() + 6)
        }
        .allowsHitTesting(false)
    }
}

struct HoverCard: View {
    @EnvironmentObject var app: AppState
    let unit: CGFloat
    @ObservedObject var hover: HoverModel

    var body: some View {
        let keys = Keycodes.layout(app.layoutKind, mediaRow: app.mediaRow)
        if let hk = hover.key, let k = keys.first(where: { $0.code == hk }),
           let b = app.project.binding(layer: app.activeLayer, key: k.code), !b.isEmpty {
            let r = Theme.rect(k, unit: unit)
            let below = r.minY < 3.2 * unit
            let width: CGFloat = 260
            let x = min(max(r.midX - width / 2, 0), Theme.deckWidth(unit) - width - Theme.gap)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Keycodes.label(k.code)) · \(app.project.layer(app.activeLayer)?.name ?? "Base")").font(.system(size: 12, weight: .semibold))
                ForEach([(CapRole.press, b.onPress), (.tap, b.onTap), (.hold, b.onHold), (.doubleTap, b.onDoubleTap), (.release, b.onRelease)].filter { !$0.1.isEmpty }, id: \.0) { role, actions in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(role.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                            Text(KeyGlyphs.words(a)).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(10).frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cap))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline.opacity(1)))
            .alignmentGuide(.top) { below ? $0[.top] : $0[.bottom] }
            .offset(x: x, y: below ? r.maxY + 8 : r.minY - 8)
            .allowsHitTesting(false).zIndex(10)
        }
    }
}

/// Deliberately does NOT observe AppState: it only redraws when its own model changes.
struct KeyCapView: View, Equatable {
    let m: CapModel
    let unit: CGFloat
    let app: AppState

    static func == (a: KeyCapView, b: KeyCapView) -> Bool { a.m == b.m && a.unit == b.unit }

    var body: some View {
        let key = m.key
        let tint = m.isBase ? Theme.baseTint : (m.tintHex.map(Color.init(hex:)) ?? Theme.baseTint)
        let triggerFill = m.triggerHex.map(Color.init(hex:))
        let cap = Int(max(0, (Metrics.legendBudget(unit: Double(unit), widthUnits: key.w) - Double(Theme.legendWidth(key.label))) / 10))

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.cornerKey).fill(Color.black.opacity(0.10)).offset(y: 1)   // cap edge, no blur
            RoundedRectangle(cornerRadius: Theme.cornerKey).fill(Theme.cap)
            if m.used { RoundedRectangle(cornerRadius: Theme.cornerKey).fill(tint.opacity(0.16)) }
            if let triggerFill { RoundedRectangle(cornerRadius: Theme.cornerKey).fill(triggerFill.opacity(0.28)) }
            if m.used {
                VStack(spacing: 0) { Spacer(minLength: 0); Rectangle().fill(tint).frame(height: 3) }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerKey))
            }
            Text(key.label).font(.system(size: CGFloat(Metrics.legendFont), weight: .semibold))
                .foregroundStyle(.primary.opacity(0.78)).fixedSize()
                .padding(.leading, CGFloat(Metrics.capPadding)).padding(.top, 5)
            HStack(spacing: 1) {
                ForEach(Array(m.badges.prefix(cap)), id: \.self) { badge in
                    switch badge {
                    case .shape(let sym, let hex): Image(systemName: sym).font(.system(size: 7)).foregroundStyle(Color(hex: hex))
                    case .text(let t): Text(t).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, CGFloat(Metrics.capPadding)).padding(.top, 6)
            if let content = m.content {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 2) {
                            Text(row.role.icon).font(.system(size: 8)).foregroundStyle(.secondary)
                                .frame(width: CGFloat(Metrics.roleIconWidth), alignment: .leading).fixedSize()
                            Text(row.text).font(.system(size: CGFloat(Metrics.rowFont), weight: .medium))
                                .foregroundStyle(m.isBase ? Color.primary : tint).fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, CGFloat(Metrics.capPadding)).padding(.bottom, 7)
            }
        }
        .frame(width: m.size.width, height: m.size.height)
        .overlay {
            if m.selected {
                // Glow in the active layer's color, drawn as soft stacked rings (no blur: blur is slow without a GPU).
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cornerKey + 4).stroke(tint.opacity(0.10), lineWidth: 9)
                    RoundedRectangle(cornerRadius: Theme.cornerKey + 3).stroke(tint.opacity(0.18), lineWidth: 6)
                    RoundedRectangle(cornerRadius: Theme.cornerKey + 2).stroke(tint.opacity(0.32), lineWidth: 3.5)
                    RoundedRectangle(cornerRadius: Theme.cornerKey).stroke(tint, lineWidth: 1.5)
                }
            } else {
                RoundedRectangle(cornerRadius: Theme.cornerKey).stroke(triggerFill ?? Theme.hairline.opacity(0.7), lineWidth: triggerFill == nil ? 1 : 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerKey))
        .onHover { inside in
            if inside { app.hover.enter(key.code) } else { app.hover.leave(key.code) }
        }
        .onTapGesture { app.tapKey(key.code) }
        .overlay(DropHighlight(code: key.code, tint: m.isBase ? Color.accentColor : tint, model: app.drop))
        .modifier(KeyDragDrop(app: app, code: key.code))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.accessibility)
        .accessibilityAddTraits(m.selected ? [.isButton, .isSelected] : .isButton)
    }
}
