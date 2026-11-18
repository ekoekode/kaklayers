import SwiftUI
import AppKit
import KaKLayersCore

/// Three columns whose edges land on the keyboard's grid: F5 (6.5u) and the navigation block (15.5u).
struct DockView: View {
    @EnvironmentObject var app: AppState
    let unit: CGFloat

    var body: some View {
        let a = (6.5 * unit).rounded(), b = (9 * unit).rounded()
        let c = Theme.deckWidth(unit) - Theme.gap - a - b
        if let key = app.selectedKey {
            HStack(alignment: .top, spacing: 0) {
                DockCard("Selection") { SelectionPanel(key: key) }.frame(width: a - Theme.gutter)
                Spacer().frame(width: Theme.gutter)
                DockCard("Workflow") { WorkflowPanel(key: key) }.frame(width: b - Theme.gutter)
                Spacer().frame(width: Theme.gutter)
                DockCard("Context & timing") { ContextPanel(key: key) }.frame(width: c)
            }
            .padding(.bottom, Theme.gutter)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("Select a key").font(.system(size: 15, weight: .semibold))
                Text("Click it, or press it on your keyboard. Drag a key onto another, or press ⌘C then ⌘V, to copy its settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DockCard<Content: View>: View {
    @Environment(\.snapshot) var snapshot
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            if snapshot { content.frame(maxWidth: .infinity, alignment: .leading); Spacer(minLength: 0) }
            else { ScrollView(.vertical, showsIndicators: false) { content.frame(maxWidth: .infinity, alignment: .leading) } }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(RoundedRectangle(cornerRadius: Theme.cornerCard).fill(Theme.cap))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: Shared slot helpers

extension AppState {
    func slot(_ key: String, _ kp: WritableKeyPath<KeyBinding, [Action]>) -> SwiftUI.Binding<[Action]> {
        SwiftUI.Binding(get: { self.project.binding(layer: self.activeLayer, keys: self.keysFor(key), mods: self.variantMods)?[keyPath: kp] ?? [] },
                        set: { v in self.updateBinding(key) { $0[keyPath: kp] = v } })
    }
    func intSlot(_ key: String, _ kp: WritableKeyPath<KeyBinding, Int>) -> SwiftUI.Binding<Int> {
        SwiftUI.Binding(get: { self.project.binding(layer: self.activeLayer, keys: self.keysFor(key), mods: self.variantMods)?[keyPath: kp] ?? KeyBinding(fromKeys: [key])[keyPath: kp] },
                        set: { v in self.updateBinding(key) { $0[keyPath: kp] = v } })
    }
    func current(_ key: String) -> KeyBinding? {
        project.binding(layer: activeLayer, keys: keysFor(key), mods: variantMods)
    }
}

extension CapRole {
    var short: String { switch self { case .press: "Press"; case .tap: "Tap"; case .hold: "Hold"; case .doubleTap: "Double"; case .release: "Release" } }
    var help: String {
        switch self {
        case .press: "Runs the moment the key goes down."
        case .tap: "Runs when the key is pressed and released on its own. A hold-only key still types itself when tapped unless you set something here."
        case .hold: "Runs once the key has been held past the hold threshold."
        case .doubleTap: "Runs when the key is pressed twice quickly."
        case .release: "Runs when the key comes back up."
        }
    }
    var keyPath: WritableKeyPath<KeyBinding, [Action]> {
        switch self { case .press: \.onPress; case .tap: \.onTap; case .hold: \.onHold; case .doubleTap: \.onDoubleTap; case .release: \.onRelease }
    }
}

// MARK: Selection

struct SelectionPanel: View {
    @EnvironmentObject var app: AppState
    let key: String

    var body: some View {
        let layer = app.project.layer(app.activeLayer)
        let idx = app.project.layers.firstIndex { $0.id == app.activeLayer }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(app.editingChord == nil ? Keycodes.label(key) : "⛓")
                    .font(.system(size: 22, weight: .semibold)).fixedSize()
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerKey).fill(Theme.window))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerKey).stroke(Theme.hairline))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.editingChord.map { "Chord " + $0.map(Keycodes.label).joined(separator: " + ") } ?? (Keycodes.isMouseButton(key) ? "\(Keycodes.mouseName(key)) button" : "Key \(Keycodes.label(key))"))
                        .font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Image(systemName: idx.map { Theme.shape(forLayerIndex: $0) } ?? "circle.dashed").font(.system(size: 9))
                            .foregroundStyle(layer.map { Color(hex: $0.colorHex) } ?? .secondary)
                        Text("in \(layer?.name ?? "Base")").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("When held with").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(["command", "control", "option", "shift"], id: \.self) { m in
                        Toggle(modSymbol(m), isOn: SwiftUI.Binding(get: { app.variantMods.contains(m) },
                                                                    set: { on in app.variantMods.removeAll { $0 == m }; if on { app.variantMods.append(m) } }))
                            .toggleStyle(.button).controlSize(.regular)
                    }
                }
                let vs = app.project.variants(layer: app.activeLayer, key: key).filter { !$0.isEmpty }
                if !vs.isEmpty {
                    Text("Defined: " + vs.map { $0.fromModifiers.isEmpty ? "plain" : $0.fromModifiers.map(modSymbol).joined() }.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ChordSection(key: key)
            if app.current(key) != nil {
                Button("Clear this binding", role: .destructive) { app.clearBinding(key) }.controlSize(.small)
            }
        }
    }
}

struct ChordSection: View {
    @EnvironmentObject var app: AppState
    let key: String

    var body: some View {
        let chords = app.project.chords(layer: app.activeLayer, containing: key)
        VStack(alignment: .leading, spacing: 6) {
            Text("Chords").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                if app.editingChord != nil {
                    Button("← \(Keycodes.label(key)) alone") { app.editingChord = nil }.controlSize(.small)
                }
                ForEach(chords) { c in
                    Button((app.editingChord == c.fromKeys ? "● " : "") + c.fromKeys.map(Keycodes.label).joined(separator: " + ")) { app.editingChord = c.fromKeys }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Button(app.recording == .input ? "Hold the keys together" : "New chord with \(Keycodes.label(key))") {
                    app.record(.input) { r in
                        let keys = (Array(NSOrderedSet(array: [key] + r.keys)) as? [String]) ?? [key]
                        if keys.count < 2 { app.status = "A chord needs at least two different keys."; return }
                        app.variantMods = []
                        app.editingChord = keys
                        app.status = "Editing chord \(keys.map(Keycodes.label).joined(separator: " + ")). Add an action in Workflow."
                    }
                }.controlSize(.small)
            }
        }
    }
}

// MARK: Workflow

struct WorkflowPanel: View {
    @EnvironmentObject var app: AppState
    let key: String

    var body: some View {
        let b = app.current(key)
        let count: (CapRole) -> Int = { b?[keyPath: $0.keyPath].count ?? 0 }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(CapRole.allCases, id: \.self) { role in
                    let on = app.dockTab == role
                    Button { app.dockTab = role } label: {
                        HStack(spacing: 4) {
                            Text(role.short).font(.system(size: 12, weight: on ? .semibold : .regular)).fixedSize()
                            if count(role) > 0 {
                                Text("\(count(role))").font(.system(size: 10, weight: .bold)).foregroundStyle(on ? Color.white : Color.secondary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(on ? app.layerTint : Color.primary.opacity(0.1)))
                            }
                        }
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? app.layerTint.opacity(0.16) : Color.clear))
                    }.buttonStyle(.plain)
                }
            }
            Text(app.dockTab.help).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ActionRail(actions: app.slot(key, app.dockTab.keyPath), listId: "\(key)-\(app.dockTab)")
        }
    }
}

/// Steps as cards joined by arrows. Wraps to new lines, never scrolls sideways.
struct ActionRail: View {
    @EnvironmentObject var app: AppState
    @SwiftUI.Binding var actions: [Action]
    var listId: String

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(Array(actions.enumerated()), id: \.offset) { i, _ in
                HStack(spacing: 6) {
                    if i > 0 { Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    StepCard(action: SwiftUI.Binding(get: { i < actions.count ? actions[i] : .delay(0) }, set: { if i < actions.count { actions[i] = $0 } }),
                             listId: listId, index: i,
                             canLeft: i > 0, canRight: i < actions.count - 1,
                             left: { actions.swapAt(i, i - 1) }, right: { actions.swapAt(i, i + 1) }, remove: { actions.remove(at: i) })
                }
            }
            HStack(spacing: 6) {
                if !actions.isEmpty { Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
                Menu {
                    Button("Key press (down and up)") { actions.append(.key(KeyCombo(key: "a"))) }
                    Button("Key down (hold)") { actions.append(.keyDown(KeyCombo(key: "left_shift"))) }
                    Button("Key up (release)") { actions.append(.keyUp(KeyCombo(key: "left_shift"))) }
                    Button("Delay") { actions.append(.delay(100)) }
                    Button("Shell command or script") { actions.append(.shell("")) }
                    Button("Open app") { actions.append(.openApp("com.apple.Terminal")) }
                    Button("Open URL") { actions.append(.openURL("https://")) }
                    Button("Media key") { actions.append(.consumer("play_or_pause")) }
                    Button("Mouse button") { actions.append(.mouse("button1")) }
                    Button("Toggle sticky modifier") { actions.append(.stickyModifier("left_shift")) }
                } label: { Label(actions.isEmpty ? "Add a step" : "Add", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}

struct StepCard: View {
    @SwiftUI.Binding var action: Action
    let listId: String
    let index: Int
    let canLeft: Bool, canRight: Bool
    let left: () -> Void, right: () -> Void, remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ActionRow(action: $action, listId: listId, index: index)
            VStack(spacing: 0) {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                if canLeft { Button(action: left) { Image(systemName: "chevron.left").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(.secondary) }
                if canRight { Button(action: right) { Image(systemName: "chevron.right").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.window))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
    }
}

// MARK: Context & timing

final class TextBox: ObservableObject { @Published var text = "" }

struct ContextPanel: View {
    @EnvironmentObject var app: AppState
    let key: String
    @StateObject private var apps = TextBox()
    @StateObject private var devs = TextBox()

    static func parse(_ t: String) -> [DeviceID] {
        t.split(separator: ",").compactMap { part in
            let ids = part.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard ids.count == 2, let v = ids[0], let p = ids[1] else { return nil }
            return DeviceID(vendorId: v, productId: p)
        }
    }
    static func format(_ d: [DeviceID]) -> String { d.map { "\($0.vendorId):\($0.productId)" }.joined(separator: ", ") }

    func slider(_ title: String, _ kp: WritableKeyPath<KeyBinding, Int>, range: ClosedRange<Double>) -> some View {
        let v = app.intSlot(key, kp)
        return HStack(spacing: 8) {
            Text(title).font(.system(size: 12)).frame(width: 112, alignment: .leading).fixedSize()
            Slider(value: SwiftUI.Binding(get: { Double(v.wrappedValue) }, set: { v.wrappedValue = Int($0 / 10) * 10 }), in: range)
            Text("\(v.wrappedValue) ms").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing).fixedSize()
        }
    }

    func reload() {
        let b = app.current(key)
        apps.text = b?.apps.joined(separator: ", ") ?? ""
        devs.text = Self.format(b?.devices ?? [])
    }

    var body: some View {
        let b = app.current(key)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                slider("Tap window", \.tapTimeoutMs, range: 50...1000)
                slider("Hold threshold", \.holdThresholdMs, range: 100...2000)
                slider("Double-tap window", \.doubleTapMs, range: 100...1000)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Only in apps").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack {
                    TextField("Bundle IDs, comma separated", text: $apps.text)
                        .onChange(of: apps.text) { t in app.updateBinding(key) { $0.apps = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } }
                    Button("Choose…") { app.keyPickerFor = "ctx-apps" }.controlSize(.small)
                        .popover(isPresented: SwiftUI.Binding(get: { app.keyPickerFor == "ctx-apps" }, set: { if !$0 { app.keyPickerFor = nil } })) {
                            AppPickerList(selected: nil) { id in addApp(id); app.keyPickerFor = nil }
                        }
                }
                Toggle("Everywhere except these", isOn: SwiftUI.Binding(get: { b?.appsExclude ?? false }, set: { v in app.updateBinding(key) { $0.appsExclude = v } }))
                    .font(.system(size: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Only on devices").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextField("vendor:product, e.g. 1452:834", text: $devs.text)
                    .help("Find IDs in Karabiner-Elements → EventViewer → Devices.")
                    .onChange(of: devs.text) { t in app.updateBinding(key) { $0.devices = Self.parse(t) } }
            }
        }
        .onAppear { reload() }
        .onChange(of: key) { _ in reload() }
        .onChange(of: app.variantMods) { _ in reload() }
        .onChange(of: app.activeLayer) { _ in reload() }
        .onChange(of: app.editingChord) { _ in reload() }
    }

    func addApp(_ id: String) {
        let existing = apps.text.isEmpty ? [] : apps.text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if !existing.contains(id) { apps.text = (existing + [id]).joined(separator: ", ") }
    }
}
