import SwiftUI
import KaKLayersCore

/// Window shell: toolbar, layer bar, full-width keyboard deck, dock, status bar.
struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        GeometryReader { geo in
            let u = Theme.unit(forWidth: geo.size.width)
            VStack(spacing: 0) {
                ToolbarView()
                Divider()
                VStack(spacing: 12) {
                    LayerBar()
                    KeyboardDeck(unit: u)
                }
                .frame(width: Theme.deckWidth(u) - Theme.gap, alignment: .leading)
                .padding(.vertical, Theme.gutter)
                .frame(maxWidth: .infinity)
                .background(Theme.plate)
                Divider()
                DockView(unit: u)
                    .frame(width: Theme.deckWidth(u) - Theme.gap)
                    .padding(.top, Theme.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatusBar().frame(minHeight: 28)
            }
            .background(Theme.window)
        }
        .frame(minHeight: Theme.minWindowHeight + app.layerBarExtra)
        .onAppear { app.installTypeToSelect() }
        .sheet(isPresented: $app.showJSON) {
            VStack(alignment: .leading) {
                HStack { Text("Generated Karabiner JSON").font(.headline); Spacer(); Button("Done") { app.showJSON = false } }
                ScrollView { Text(app.exportJSON()).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding().frame(width: 700, height: 520)
        }
    }
}

// MARK: Toolbar

struct ToolbarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
            Text("🍰 KāKLayers").font(.system(size: 15, weight: .semibold))
            Spacer()
            Toggle(isOn: $app.simulate) { Label("Simulate", systemImage: "play.circle") }.toggleStyle(.button)
            Menu {
                ForEach(Presets.all) { pr in Button("\(pr.name) — \(pr.detail)") { app.addPreset(pr) } }
                Divider()
                Button("Import from karabiner.json…") { app.importFile() }
            } label: { Label("Library", systemImage: "square.grid.2x2") }.menuStyle(.borderlessButton).fixedSize()
            checksButton
            Menu {
                Button("View generated JSON") { app.showJSON = true }
                Button("Export Karabiner JSON…") { app.exportKarabinerJSON() }
                Divider()
                Button("Open project…") { app.openProject() }
                Button("Save project as…") { app.saveProjectAs() }
                if app.projectFile != nil { Button("Use app's own project folder") { app.useDefaultProject() } }
                Text("Project: " + (app.projectFile?.lastPathComponent ?? "app folder"))
                Divider()
                Button("Apply to another file…") { app.applyToAnotherFile() }
                Button("Set Karabiner config location…") { app.chooseConfigLocation() }
                if app.configFile != nil { Button("Use ~/.config/karabiner") { app.useDefaultConfig() } }
                Text("Config: " + (app.configFile?.path ?? "~/.config/karabiner/karabiner.json"))
                Divider()
                Button("Restore last backup") { app.restore() }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
            Button { app.apply() } label: { Label("Apply to Karabiner", systemImage: "checkmark.circle.fill") }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Theme.gutter).frame(height: 48)
        .background(Theme.window)
    }

    var checksButton: some View {
        let probs = app.problems
        let warnings = probs.filter { $0.severity == .warning }.count
        return Button { app.showChecks.toggle() } label: {
            Label(probs.isEmpty ? "No issues" : "\(probs.count)", systemImage: warnings > 0 ? "exclamationmark.triangle.fill" : (probs.isEmpty ? "checkmark.seal" : "info.circle"))
                .foregroundStyle(warnings > 0 ? Color.orange : Color.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $app.showChecks, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Checks").font(.headline)
                if probs.isEmpty { Text("Nothing to fix.").foregroundStyle(.secondary) }
                ForEach(probs) { p in
                    Label { Text(p.message).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: p.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle").foregroundStyle(p.severity == .warning ? Color.orange : Color.secondary)
                    }.font(.system(size: 12))
                }
            }.padding(14).frame(width: 340, alignment: .leading)
        }
    }
}

// MARK: Layer bar

/// Layers (not Base) can be dragged onto each other to re-order; keys carry a different payload prefix.
/// Holds the app without observing it, so it is not re-evaluated on every unrelated change.
struct ReorderModifier: ViewModifier {
    let app: AppState
    @Environment(\.snapshot) var snapshot
    let id: String?
    func body(content: Content) -> some View {
        if let id, !snapshot {
            content
                .draggable("layer:" + id)
                .dropDestination(for: String.self) { items, _ in
                    guard let s = items.first, s.hasPrefix("layer:") else { return false }
                    let moved = String(s.dropFirst(6)); guard moved != id else { return false }
                    app.project.moveLayer(moved, before: id); return true
                }
                .contextMenu {
                    Button("Layer settings…") { app.activeLayer = id; app.layerPopover = id }
                    Button("Move earlier") { app.project.shiftLayer(id, by: -1) }
                    Button("Move later") { app.project.shiftLayer(id, by: 1) }
                    Divider()
                    Button("Delete layer…", role: .destructive) { app.confirmDeleteLayer(id) }
                }
        } else { content }
    }
}

/// Reads the layer live, so the popover follows edits made inside it.
struct LayerSettingsHost: View {
    @EnvironmentObject var app: AppState
    let id: String
    var body: some View {
        if let layer = app.project.layer(id) { LayerSettings(layer: layer).frame(width: 320).padding(14) }
    }
}

/// One layer chip. Plain values plus the app (not observed), so a chip only redraws when its own look changes.
struct LayerChip: View, Equatable {
    let id: String?
    let name: String
    let hex: String?
    let shape: String
    let trigger: String
    let active: Bool
    let held: Bool
    let simulating: Bool
    let selected: Bool
    let popoverOpen: Bool
    let app: AppState

    static func == (a: LayerChip, b: LayerChip) -> Bool {
        a.id == b.id && a.name == b.name && a.hex == b.hex && a.shape == b.shape && a.trigger == b.trigger && a.active == b.active
            && a.held == b.held && a.simulating == b.simulating && a.selected == b.selected && a.popoverOpen == b.popoverOpen
    }

    var body: some View {
        let color = hex.map(Color.init(hex:)) ?? Color.secondary
        let showHeld = simulating && id != nil
        let on = showHeld && held
        return HStack(spacing: 6) {
            Image(systemName: shape).font(.system(size: 10)).foregroundStyle(on ? Color.white : color)
            Text(name).font(.system(size: 12, weight: .medium)).fixedSize().foregroundStyle(on ? Color.white : Color.primary)
            if !trigger.isEmpty {
                Text(trigger).font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary).fixedSize()
            }
            if id != nil && !simulating {
                Button {
                    app.activeLayer = id
                    app.layerPopover = (app.layerPopover == id ? nil : id)
                } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 11)).frame(width: 18, height: 18).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Layer settings")
            }
        }
        .padding(.horizontal, 11).frame(height: 28)
        .background(Capsule().fill(on ? color : (selected ? Color.red.opacity(0.12) : (active && !simulating ? color.opacity(0.20) : Color.primary.opacity(0.06)))))
        .overlay(Capsule().stroke(selected ? Color.red.opacity(0.75) : (active && !simulating ? color : Color.clear), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if selected && !simulating {
                Button { app.confirmDeleteSelectedLayers() } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain).offset(x: 5, y: -5).help("Delete the selected layers")
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            if simulating, let id { if held { app.simHeld.remove(id) } else { app.simHeld.insert(id) } }
            else if let id, NSEvent.modifierFlags.contains(.shift) { app.toggleLayerSelection(id) }
            else { app.clearLayerSelection(); app.activeLayer = id }
        }
        .modifier(ReorderModifier(app: app, id: id))
        .popover(isPresented: SwiftUI.Binding(get: { id != nil && popoverOpen }, set: { if !$0 { app.layerPopover = nil } }), arrowEdge: .bottom) {
            if let id { LayerSettingsHost(id: id) }
        }
    }
}

/// Reports the layer bar's height so the window can keep room for the dock below it.
struct LayerBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct LayerBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Chips wrap onto more lines and the bar grows with them (fixedSize makes the height follow the wrapped width).
            FlowLayout(spacing: 10, lineSpacing: 12) {
                chip(id: nil, name: "Base", hex: nil, shape: "circle.dashed", trigger: "")
                ForEach(Array(app.project.layers.enumerated()), id: \.element.id) { i, l in
                    chip(id: l.id, name: l.name, hex: l.colorHex, shape: Theme.shape(forLayerIndex: i), trigger: l.triggerKeys.map { KeyGlyphs.glyph($0) }.joined())
                }
                Button { app.addLayer() } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).background(Circle().fill(Color.primary.opacity(0.06))).help("New layer")
                if app.project.layers.isEmpty {
                    Text("No layers yet. Add one with +, or pick a preset from Library.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if app.simulate {
                    Text("Hold:").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(["command", "control", "option", "shift"], id: \.self) { m in
                        Toggle(modSymbol(m), isOn: Binding(get: { app.simMods.contains(m) }, set: { on in
                            if on { app.simMods.insert(m) } else { app.simMods.remove(m) } })).toggleStyle(.button).controlSize(.small)
                    }
                } else {
                    Toggle("All layers", isOn: $app.showAllLayers).toggleStyle(.switch).controlSize(.small)
                }
                Picker("", selection: $app.layoutKind) { ForEach(Keycodes.LayoutKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                Picker("", selection: $app.mediaRow) { Text("F1–F12").tag(false); Text("Media").tag(true) }
                    .pickerStyle(.segmented).frame(width: 130).labelsHidden()
                    .help("Top row as function keys, or as the media keys it sends without fn. A rule on either one fires for both.")
                Picker("", selection: $app.mouseMode) { Text("10 key").tag(false); Text("Mouse").tag(true) }
                    .pickerStyle(.segmented).frame(width: 130).labelsHidden()
                    .help("Show the 10 key, or a mouse so you can bind its buttons")
            }
            .fixedSize().frame(height: 28)
        }
        .background(GeometryReader { Color.clear.preference(key: LayerBarHeightKey.self, value: $0.size.height) })
        .onPreferenceChange(LayerBarHeightKey.self) { h in
            let extra = max(0, (h - 28).rounded())
            if extra != app.layerBarExtra { app.layerBarExtra = extra }
        }
    }

    func chip(id: String?, name: String, hex: String?, shape: String, trigger: String) -> some View {
        LayerChip(id: id, name: name, hex: hex, shape: shape, trigger: trigger,
                  active: app.activeLayer == id, held: id.map { app.simHeld.contains($0) } ?? false, simulating: app.simulate,
                  selected: id.map { app.layerSelection.contains($0) } ?? false, popoverOpen: id != nil && app.layerPopover == id, app: app)
            .equatable()
    }
}

// MARK: Status bar

struct StatusBar: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack {
            Text(app.status.isEmpty ? "Click a key or press it on your keyboard. Drag a key onto another, or ⌘C then ⌘V, to copy its settings." : app.status)
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }.padding(.horizontal, Theme.gutter).background(Theme.window)
    }
}
