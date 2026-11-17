import SwiftUI
import AppKit
import KaKLayersCore

/// Layer editor, shown in a popover from the layer bar.
struct LayerSettings: View {
    @EnvironmentObject var app: AppState
    let layer: Layer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layer").font(.headline)
            HStack {
                TextField("Name", text: SwiftUI.Binding(get: { layer.name }, set: { v in app.updateLayer(layer.id) { $0.name = v } }))
                ColorPicker("", selection: SwiftUI.Binding(get: { Color(hex: layer.colorHex) }, set: { c in app.updateLayer(layer.id) { $0.colorHex = c.hexString } }))
                    .labelsHidden()
            }
            Picker("Mode", selection: SwiftUI.Binding(get: { layer.mode }, set: { v in app.updateLayer(layer.id) { $0.mode = v } })) {
                Text("Hold").tag(LayerMode.momentary); Text("Toggle").tag(LayerMode.toggle)
            }.pickerStyle(.segmented)
            HStack {
                Text("Trigger").foregroundStyle(.secondary)
                Text(layer.triggerKeys.isEmpty ? "none" : layer.triggerKeys.map(Keycodes.label).joined(separator: " + "))
                Spacer()
                Button(app.recording == .layerTrigger(layer.id) ? "Press keys…" : "Record") {
                    app.record(.layerTrigger(layer.id)) { r in app.updateLayer(layer.id) { $0.triggerKeys = r.keys } }
                }
            }
            Text("Hold several keys at once (for example ⌘⌃⇧) for a hyper-key layer.").font(.system(size: 11)).foregroundStyle(.secondary)
            if layer.mode == .momentary {
                Text("When tapped alone, output").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text("Leave it empty and a tap sends the key itself, with Shift and other modifiers still applied.").font(.system(size: 11)).foregroundStyle(.secondary)
                ActionRail(actions: SwiftUI.Binding(get: { layer.tapAction }, set: { v in app.updateLayer(layer.id) { $0.tapAction = v } }), listId: "layertap-\(layer.id)")
            }
            Divider()
            Button("Delete layer…", role: .destructive) { app.layerPopover = nil; app.confirmDeleteLayer(layer.id) }.controlSize(.small)
        }
    }
}

/// One editable step. Fixed widths keep the rail tidy and nothing is ever cut off.
struct ActionRow: View {
    @EnvironmentObject var app: AppState
    @SwiftUI.Binding var action: Action
    let listId: String
    let index: Int
    var rid: String { "\(listId)#\(index)" }

    var body: some View {
        switch action {
        case .key(let c):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard").font(.system(size: 10)).foregroundStyle(.secondary)
                    ForEach(["command", "control", "option", "shift"], id: \.self) { m in
                        Toggle(modSymbol(m), isOn: SwiftUI.Binding(get: { c.modifiers.contains(m) }, set: { on in
                            var n = c; n.modifiers.removeAll { $0 == m }; if on { n.modifiers.append(m) }; action = .key(n)
                        })).toggleStyle(.button).controlSize(.small)
                    }
                }
                HStack(spacing: 4) {
                    Button { app.keyPickerFor = rid } label: {
                        HStack(spacing: 4) { Text(Keycodes.label(c.key)).fixedSize(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)) }
                            .frame(minWidth: 70)
                    }
                    .controlSize(.small)
                    .popover(isPresented: SwiftUI.Binding(get: { app.keyPickerFor == rid }, set: { if !$0 { app.keyPickerFor = nil } })) {
                        KeyPickerList(selected: c.key) { code in action = .key(KeyCombo(key: code, modifiers: c.modifiers)); app.keyPickerFor = nil }
                    }
                    Button(app.recording == .action(rid) ? "Press…" : "Record") {
                        app.record(.action(rid)) { r in if let m = r.main { action = .key(KeyCombo(key: m, modifiers: r.modifiers)) } }
                    }.controlSize(.small)
                }
            }
        case .delay(let ms):
            HStack(spacing: 6) {
                Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(.secondary)
                Stepper("\(ms) ms", value: SwiftUI.Binding(get: { ms }, set: { action = .delay($0) }), in: 0...10000, step: 50)
                    .font(.system(size: 12, design: .monospaced)).fixedSize()
            }
        case .shell(let s):
            HStack(spacing: 6) {
                Text("$").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                TextField("command or script path", text: SwiftUI.Binding(get: { s }, set: { action = .shell($0) }))
                    .font(.system(size: 12, design: .monospaced)).frame(width: 210)
            }
        case .openApp(let id):
            Button { app.keyPickerFor = rid } label: { AppLabel(bundleId: id) }
                .buttonStyle(.bordered).controlSize(.regular)
                .popover(isPresented: SwiftUI.Binding(get: { app.keyPickerFor == rid }, set: { if !$0 { app.keyPickerFor = nil } })) {
                    AppPickerList(selected: id) { picked in action = .openApp(picked); app.keyPickerFor = nil }
                }
        case .openURL(let s):
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("URL", text: SwiftUI.Binding(get: { s }, set: { action = .openURL($0) })).frame(width: 200)
            }
        case .consumer(let k):
            Picker("Media", selection: SwiftUI.Binding(get: { k }, set: { action = .consumer($0) })) {
                ForEach(Keycodes.mediaKeys, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }.fixedSize()
        case .mouse(let b):
            Picker("Mouse", selection: SwiftUI.Binding(get: { b }, set: { action = .mouse($0) })) {
                ForEach(["button1", "button2", "button3", "button4", "button5"], id: \.self) { Text($0).tag($0) }
            }.fixedSize()
        case .stickyModifier(let m):
            Picker("Sticky", selection: SwiftUI.Binding(get: { m }, set: { action = .stickyModifier($0) })) {
                ForEach(["left_shift", "left_control", "left_option", "left_command"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }.fixedSize()
        case .setVariable, .inputSource:
            Text(KeyGlyphs.words(action)).font(.system(size: 12))
        }
    }
}


/// Lazy list: only visible rows are built (a Picker would build all ~125 menu items on every redraw).
struct KeyPickerList: View {
    let selected: String
    let pick: (String) -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Keycodes.all, id: \.code) { k in
                    Button { pick(k.code) } label: {
                        HStack { Text(k.label).frame(width: 60, alignment: .leading); Text(k.code).foregroundStyle(.secondary).font(.system(size: 11)); Spacer()
                            if k.code == selected { Image(systemName: "checkmark") } }
                        .padding(.horizontal, 10).padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }.frame(width: 260, height: 300)
    }
}
