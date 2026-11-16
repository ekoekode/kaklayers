import SwiftUI
import AppKit
import KaKLayersCore

let layerPalette = ["#4F8EF7", "#E5484D", "#30A46C", "#F5A524", "#9B5DE5", "#00B8D9", "#F15BB5", "#8D6E63"]

extension Color {
    init(hex: String) {
        var h = hex; if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var project: Project {
        didSet {
            save()
            problems = ConflictChecker.check(project)
            if !restoring {
                // One undo step per burst of edits (a slider drag is a single step, not hundreds).
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastUndoPush > 0.6 { undoStack.append(oldValue); if undoStack.count > 100 { undoStack.removeFirst() } }
                lastUndoPush = now
                redoStack.removeAll()
            }
        }
    }
    private var lastUndoPush: CFAbsoluteTime = 0
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    private var restoring = false
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func undo() {
        guard let prev = undoStack.popLast() else { return }
        restoring = true; redoStack.append(project); project = prev; restoring = false
        objectWillChange.send()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        restoring = true; undoStack.append(project); project = next; restoring = false
        objectWillChange.send()
    }
    @Published var activeLayer: String? = nil { didSet { editingChord = nil; if layerPopover != activeLayer { layerPopover = nil } } }       // nil = base
    @Published var selectedKey: String? = nil { didSet { editingChord = nil } }
    /// When set, the inspector edits this chord (keys pressed together) instead of the single selected key.
    @Published var editingChord: [String]? = nil
    func keysFor(_ key: String) -> [String] { editingChord ?? [key] }
    @Published var showAllLayers = false
    @Published var status: String = ""
    let hover = HoverModel()          // not @Published: hover must not redraw the keyboard
    @Published private(set) var problems: [Problem] = []
    @Published var dockTab: CapRole = .press
    @Published var showChecks = false
    @Published var layerPopover: String? = nil
    @Published var keyPickerFor: String? = nil
    @Published var showJSON = false
    @Published var variantMods: [String] = []   // modifier variant being edited
    @Published var simMods: Set<String> = []
    @Published var mediaRow: Bool = UserDefaults.standard.bool(forKey: "mediaRow") { didSet { if persist { UserDefaults.standard.set(mediaRow, forKey: "mediaRow") } } }
    @Published var layoutKind: Keycodes.LayoutKind = Keycodes.LayoutKind(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .ansi { didSet { if persist { UserDefaults.standard.set(layoutKind.rawValue, forKey: "layout") } } }
    @Published var simulate = false
    @Published var simHeld: Set<String> = []
    @Published var recording: RecordTarget? = nil

    enum RecordTarget: Equatable { case input, layerTrigger(String), action(String) }

    let recorder = KeyRecorder()
    static let saveURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("KaKLayers")
        let old = base.appendingPathComponent("Layers")   // pre-rename folder: move it once, keeping the saved project
        if !FileManager.default.fileExists(atPath: d.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: d)
        }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("project.json")
    }()

    private let persist: Bool

    init(project initial: Project? = nil, persist: Bool = true) {
        self.persist = persist
        if let initial {
            project = initial
        } else if persist, let d = try? Data(contentsOf: Self.saveURL), let p = try? JSONDecoder().decode(Project.self, from: d) {
            project = Self.isLegacyStarter(p) ? Self.starter() : p
        } else {
            project = Self.starter()
        }
        problems = ConflictChecker.check(project)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    /// New projects start empty: no layers, no bindings.
    static func starter() -> Project { Project(name: "My Layers") }

    /// The sample project earlier versions created. If a saved project is still exactly this, it is treated as empty.
    static func isLegacyStarter(_ p: Project) -> Bool {
        func norm(_ x: Project) -> [KeyBinding] { x.bindings.map { var b = $0; b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; return b } }
        let l = legacyStarter()
        return p.layers == l.layers && norm(p) == norm(l)
    }

    static func legacyStarter() -> Project {
        let nav = Layer(id: "nav", name: "Nav", colorHex: layerPalette[0],
                        triggerKeys: ["grave_accent_and_tilde"],
                        tapAction: [.key(KeyCombo(key: "grave_accent_and_tilde", modifiers: ["shift"]))])
        func arrow(_ from: String, _ to: String) -> KeyBinding {
            KeyBinding(layerId: "nav", fromKeys: [from], onPress: [.key(KeyCombo(key: to))])
        }
        return Project(layers: [nav], bindings: [arrow("h", "left_arrow"), arrow("j", "down_arrow"), arrow("k", "up_arrow"), arrow("l", "right_arrow")])
    }

    private var pendingSave: DispatchWorkItem?

    /// Debounced: dragging a slider changes the project every tick, so write to disk once things settle.
    func save() {
        guard persist else { return }
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
    func saveNow() {
        guard persist else { return }
        pendingSave?.cancel(); pendingSave = nil
        if let d = try? JSONEncoder().encode(project) { try? d.write(to: Self.saveURL, options: .atomic) }
    }

    // MARK: Selection and quick actions
    func tapKey(_ code: String) {
        if simulate {
            let r = Simulator.resolve(project, held: simHeld, key: code, mods: simMods)
            let words = r.binding.map { b in " → " + [b.onPress, b.onTap, b.onHold, b.onDoubleTap, b.onRelease].flatMap { $0 }.map(KeyGlyphs.words).joined(separator: ", then ") } ?? ""
            status = "▶︎ " + r.explanation + words
        } else { selectedKey = code }
    }

    /// Dragging key A onto key B makes A send B (in the active layer).
    func remap(from a: String, to b: String) {
        guard a != b else { return }
        selectedKey = a
        variantMods = []
        updateBinding(a) { $0.onPress = [.key(KeyCombo(key: b))] }
        status = "\(Keycodes.label(a)) now sends \(Keycodes.label(b)) in \(project.layer(activeLayer)?.name ?? "Base")."
    }

    private var typeMonitor: Any?
    /// Press a physical key to select it (unless a text field is being edited).
    func installTypeToSelect() {
        guard typeMonitor == nil else { return }
        typeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.recording == nil, !self.simulate else { return ev }
            if !ev.modifierFlags.intersection([.command, .control, .option]).isEmpty { return ev }
            if let r = NSApp.keyWindow?.firstResponder, r is NSTextView || r is NSTextField { return ev }
            guard ev.keyCode != 48, let raw = Keycodes.byMac[Int(ev.keyCode)]?.code else { return ev }   // leave Tab for focus
            let k = self.mediaRow ? (Keycodes.mediaCode(forFunction: raw) ?? raw) : raw   // media row shows media keys in place of F1–F12
            self.selectedKey = k
            return nil
        }
    }

    // MARK: Layers
    func addLayer() {
        let color = layerPalette[project.layers.count % layerPalette.count]
        let l = Layer(name: "Layer \(project.layers.count + 1)", colorHex: color)
        project.layers.append(l)
        activeLayer = l.id
        layerPopover = l.id          // open its settings straight away
    }
    func confirmDeleteLayer(_ id: String) {
        guard let l = project.layer(id) else { return }
        let n = project.bindings.filter { $0.layerId == id }.count
        let alert = NSAlert()
        alert.messageText = "Delete layer “\(l.name)”?"
        alert.informativeText = "Its \(n) binding(s) will be deleted too. You can undo this with ⌘Z."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { deleteLayer(id) }
    }
    func deleteLayer(_ id: String) {
        project.layers.removeAll { $0.id == id }
        project.bindings.removeAll { $0.layerId == id }
        if activeLayer == id { activeLayer = nil }
    }
    func updateLayer(_ id: String, _ f: (inout Layer) -> Void) {
        guard let i = project.layers.firstIndex(where: { $0.id == id }) else { return }
        f(&project.layers[i])
    }

    // MARK: Bindings
    /// Accent for the current layer; the system accent on Base.
    var layerTint: Color { project.layer(activeLayer).map { Color(hex: $0.colorHex) } ?? Theme.baseTint }
    func color(forLayer id: String?) -> Color {
        project.layer(id).map { Color(hex: $0.colorHex) } ?? .secondary
    }
    func bindingIndex(layer: String?, key: String) -> Int? {
        project.bindings.firstIndex { $0.layerId == layer && $0.fromKeys == keysFor(key) && Set($0.fromModifiers) == Set(variantMods) }
    }
    /// KeyBinding for the selected key in the active layer (created on demand, removed again if left empty).
    func ensureBinding(_ key: String) -> Int {
        if let i = bindingIndex(layer: activeLayer, key: key) { return i }
        project.bindings.append(KeyBinding(layerId: activeLayer, fromKeys: keysFor(key), fromModifiers: variantMods))
        return project.bindings.count - 1
    }
    func updateBinding(_ key: String, _ f: (inout KeyBinding) -> Void) {
        let i = ensureBinding(key)
        var b = project.bindings[i]
        f(&b)
        if b != project.bindings[i] { project.bindings[i] = b }   // no publish when nothing changed
    }
    func clearBinding(_ key: String) {
        project.bindings.removeAll { $0.layerId == activeLayer && $0.fromKeys == keysFor(key) && Set($0.fromModifiers) == Set(variantMods) }
    }

    // MARK: Presets / import
    func addPreset(_ preset: Preset) {
        project.add(preset)
        status = "Added preset “\(preset.name)”."
    }
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = ConfigWriter.defaultDir
        panel.message = "Choose a karabiner.json or complex-modification file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let r = try Importer.importSimple(data: Data(contentsOf: url))
            project.bindings += r.bindings
            status = "Imported \(r.bindings.count) simple remap(s); skipped \(r.skipped) advanced rule(s) the editor can't represent yet (they are left untouched in Karabiner)."
        } catch { status = "Import failed: \(error.localizedDescription)" }
    }

    // MARK: Apply
    func apply() {
        do {
            let r = try ConfigWriter().apply(project)
            status = "Applied \(r.ruleCount) rules to \(r.configPath)" + (r.backupPath != nil ? " (backup saved)" : "")
        } catch { status = "Apply failed: \(error.localizedDescription)" }
    }
    func restore() {
        do {
            status = try ConfigWriter().restoreLatestBackup().map { "Restored \(($0 as NSString).lastPathComponent)" } ?? "No backup found"
        } catch { status = "Restore failed: \(error.localizedDescription)" }
    }
    func exportJSON() -> String { (try? KarabinerCompiler.jsonString(KarabinerCompiler.compile(project))) ?? "" }

    // MARK: Recording
    func record(_ target: RecordTarget, _ done: @escaping (KeyRecorder.Result) -> Void) {
        if recording == target { recorder.stop(); recording = nil; return }
        recording = target
        recorder.start { [weak self] result in
            self?.recording = nil
            done(result)
        }
    }
}
