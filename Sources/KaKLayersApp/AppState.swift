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
    @Published var activeLayer: String? = nil { didSet { editingChord = nil; syncVariant(); if layerPopover != activeLayer { layerPopover = nil } } }       // nil = base
    @Published var selectedKey: String? = nil { didSet { editingChord = nil; if selectedKey != oldValue { syncVariant() } } }
    /// Open the selected key on the variant its cap shows, so the workflow and the Clear button match what you see.
    func syncVariant() {
        let v = selectedKey.map { project.defaultVariantMods(layer: activeLayer, key: $0) } ?? []
        if v != variantMods { variantMods = v }
    }
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
    /// The block at the right of the keyboard: the 10 key, or a mouse.
    @Published var mouseMode: Bool = UserDefaults.standard.bool(forKey: "mouseMode") { didSet { if persist { UserDefaults.standard.set(mouseMode, forKey: "mouseMode") } } }
    var pad: Keycodes.PadKind { mouseMode ? .mouse : .tenKey }
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

    /// Where the project is saved. nil = the app's own folder. Set by Save project as… / Open project….
    @Published var projectFile: URL? = nil { didSet { if persist { Self.remember(projectFile, key: "projectFile") } } }
    /// A custom karabiner.json to apply to. nil = ~/.config/karabiner/karabiner.json.
    @Published var configFile: URL? = nil { didSet { if persist { Self.remember(configFile, key: "configFile") } } }
    var writer: ConfigWriter { ConfigWriter(configFile: configFile) }

    static func remember(_ url: URL?, key: String) {
        if let url { UserDefaults.standard.set(url.path, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    static func remembered(_ key: String) -> URL? {
        UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0) }
    }

    init(project initial: Project? = nil, persist: Bool = true) {
        self.persist = persist
        let savedProject = persist ? Self.remembered("projectFile").flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } : nil
        self.projectFile = savedProject
        self.configFile = persist ? Self.remembered("configFile") : nil
        if let initial {
            project = initial
        } else if persist, let d = try? Data(contentsOf: savedProject ?? Self.saveURL), let p = try? JSONDecoder().decode(Project.self, from: d) {
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
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(project) else { return }
        do { try d.write(to: projectFile ?? Self.saveURL, options: .atomic) }
        catch { status = "Couldn't save the project: \(error.localizedDescription)" }
    }

    // MARK: Selection and quick actions
    func tapKey(_ code: String) {
        if simulate {
            let r = Simulator.resolve(project, held: simHeld, key: code, mods: simMods)
            let words = r.binding.map { b in " → " + [b.onPress, b.onTap, b.onHold, b.onDoubleTap, b.onRelease].flatMap { $0 }.map(KeyGlyphs.words).joined(separator: ", then ") } ?? ""
            status = "▶︎ " + r.explanation + words
        } else { selectedKey = code }
    }

    // MARK: Copy / paste / drag key settings
    /// Not @Published: copying must not redraw the keyboard.
    var keyClipboard: (key: String, layer: String?, settings: [KeyBinding])?
    /// Observed only by each key's drop highlight.
    let drop = DropModel()

    private var activeLayerName: String { project.layer(activeLayer)?.name ?? "Base" }

    func copyKeySettings(_ key: String) {
        let s = project.keySettings(layer: activeLayer, key: key)
        keyClipboard = (key, activeLayer, s)
        status = s.isEmpty ? "Copied \(Keycodes.label(key)) with no settings: pasting it resets the target key."
                           : "Copied \(Keycodes.label(key))'s settings. Select another key and press ⌘V to paste."
    }
    func pasteKeySettings(to key: String) {
        guard let c = keyClipboard else { status = "Nothing copied yet. Select a key with settings and press ⌘C."; return }
        applyCopy(c.settings, from: c.key, fromLayer: c.layer, to: key)
    }
    /// Dragging key A onto key B copies A's settings (in the active layer) onto B.
    func copySettings(from a: String, to b: String) {
        let s = project.keySettings(layer: activeLayer, key: a)
        applyCopy(s, from: a, fromLayer: activeLayer, to: b)      // an empty key copies nothing, which resets the target
    }
    private func applyCopy(_ settings: [KeyBinding], from a: String, fromLayer: String?, to b: String) {
        if a == b && fromLayer == activeLayer { status = "That's the same key."; return }
        project.paste(settings, layer: activeLayer, key: b)       // one change, so one undo step
        selectedKey = b; syncVariant()
        status = settings.isEmpty ? "Reset \(Keycodes.label(b)) in \(activeLayerName): \(Keycodes.label(a)) has no settings."
                                  : "Copied \(Keycodes.label(a))'s settings to \(Keycodes.label(b)) in \(activeLayerName)."
    }

    private var typeMonitor: Any?
    private var mouseMonitor: Any?

    /// Press a physical key to select it (unless a text field is being edited).
    func installTypeToSelect() {
        // Simulate also listens to the real mouse buttons (middle, back, forward, and right-click), like it does for keys on screen.
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .rightMouseDown]) { [weak self] ev in
                guard let self, self.simulate, self.recording == nil else { return ev }
                let code: String? = ev.type == .rightMouseDown ? "button2" : (2...4).contains(ev.buttonNumber) ? "button\(ev.buttonNumber + 1)" : nil
                if let code { self.tapKey(code) }
                return ev            // the click still does its normal job (menus, the context menu on layer chips)
            }
        }
        guard typeMonitor == nil else { return }
        typeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.recording == nil, !self.simulate else { return ev }
            if let r = NSApp.keyWindow?.firstResponder, r is NSTextView || r is NSTextField { return ev }
            // With layers selected, Delete removes them and Esc clears the selection.
            if !self.layerSelection.isEmpty, !ev.modifierFlags.contains(.command) {
                switch ev.keyCode {
                case 51, 117: self.confirmDeleteSelectedLayers(); return nil
                case 53: self.clearLayerSelection(); return nil
                default: break
                }
            }
            // ⌘C / ⌘V copy and paste the selected key's settings (text fields keep their normal copy/paste)
            if ev.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command], self.editingChord == nil, let k = self.selectedKey {
                switch ev.charactersIgnoringModifiers?.lowercased() {
                case "c": self.copyKeySettings(k); return nil
                case "v" where self.keyClipboard != nil: self.pasteKeySettings(to: k); return nil
                default: break
                }
            }
            if !ev.modifierFlags.intersection([.command, .control, .option]).isEmpty { return ev }
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
    // MARK: Multi-select layers (shift-click) and delete
    @Published var layerSelection: Set<String> = []
    /// Extra height the layer bar needs when its chips wrap onto more lines; the window's minimum height grows by this.
    @Published var layerBarExtra: CGFloat = 0

    /// Shift-click: add or remove a layer from the selection (the layer you were on counts as the first pick).
    func toggleLayerSelection(_ id: String) {
        if layerSelection.isEmpty, let a = activeLayer, a != id { layerSelection = [a] }
        if layerSelection.contains(id) { layerSelection.remove(id) } else { layerSelection.insert(id) }
        let n = layerSelection.count
        status = n == 0 ? "" : "\(n) layer\(n == 1 ? "" : "s") selected. Press Delete or click ✕ to delete them, Esc to cancel."
    }
    func clearLayerSelection() { if !layerSelection.isEmpty { layerSelection = []; status = "" } }

    func confirmDeleteSelectedLayers() {
        let ids = layerSelection.filter { project.layer($0) != nil }
        guard !ids.isEmpty else { layerSelection = []; return }
        if ids.count == 1, let id = ids.first { layerSelection = []; confirmDeleteLayer(id); return }
        let layers = project.layers.filter { ids.contains($0.id) }
        let n = project.bindings.filter { $0.layerId.map(ids.contains) ?? false }.count
        let alert = NSAlert()
        alert.messageText = "Delete \(ids.count) layers?"
        alert.informativeText = layers.prefix(6).map { "• " + $0.name }.joined(separator: "\n")
            + (layers.count > 6 ? "\n• and \(layers.count - 6) more" : "")
            + "\n\nTheir \(n) binding(s) will be deleted too. You can undo this with ⌘Z."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { deleteLayers(ids) }
    }
    /// One change, so one undo step.
    func deleteLayers(_ ids: Set<String>) {
        var p = project
        p.removeLayers(ids)
        project = p
        if let a = activeLayer, ids.contains(a) { activeLayer = nil }
        layerSelection = []
        status = "Deleted \(ids.count) layer\(ids.count == 1 ? "" : "s")."
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
    /// Removes everything set on one key in the active layer: the plain binding and every modifier variant. One undo step.
    func resetKey(_ key: String) {
        guard !project.keySettings(layer: activeLayer, key: key).isEmpty else { status = "\(Keycodes.label(key)) has nothing to reset in \(activeLayerName)."; return }
        var p = project
        p.bindings.removeAll { $0.layerId == activeLayer && $0.fromKeys == [key] }
        project = p
        if selectedKey == key { variantMods = [] }
        status = "Reset \(Keycodes.label(key)) in \(activeLayerName). ⌘Z undoes it."
    }
    /// Deletes one saved combo (a modifier variant) of a key; the others stay.
    func clearVariant(_ key: String, mods: [String]) {
        project.bindings.removeAll { $0.layerId == activeLayer && $0.fromKeys == [key] && Set($0.fromModifiers) == Set(mods) }
        if Set(variantMods) == Set(mods) { syncVariant() }
        status = "Deleted the \(mods.isEmpty ? "plain" : mods.map(modSymbol).joined()) combo on \(Keycodes.label(key))."
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
            let r = try writer.apply(project)
            status = "Applied \(r.ruleCount) rules to \(r.configPath)" + (r.backupPath != nil ? " (backup saved)" : "")
        } catch { status = "Apply failed: \(error.localizedDescription)" }
    }
    func restore() {
        do {
            status = try writer.restoreLatestBackup().map { "Restored \(($0 as NSString).lastPathComponent)" } ?? "No backup found"
        } catch { status = "Restore failed: \(error.localizedDescription)" }
    }
    // MARK: Files: custom config, export, project files
    private func savePanel(name: String, message: String) -> URL? {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]; p.nameFieldStringValue = name; p.message = message; p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }
    private func openPanel(message: String) -> URL? {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]; p.message = message
        return p.runModal() == .OK ? p.url : nil
    }

    /// Write the compiled rules as a standalone Karabiner file (import it via Complex Modifications → Add predefined rule → Import from file).
    func exportKarabinerJSON() {
        guard let url = savePanel(name: "kaklayers-rules.json", message: "Save the rules as a Karabiner complex-modifications file.") else { return }
        do { try exportJSON().write(to: url, atomically: true, encoding: .utf8); status = "Exported \(KarabinerCompiler.rules(for: project).count) rules to \(url.path)" }
        catch { status = "Export failed: \(error.localizedDescription)" }
    }
    /// One-off: merge into any karabiner.json (a backup is saved next to it).
    func applyToAnotherFile() {
        guard let url = savePanel(name: "karabiner.json", message: "Choose a karabiner.json to merge your rules into. Its other rules are kept and a backup is saved next to it.") else { return }
        do {
            let r = try ConfigWriter(configFile: url).apply(project)
            status = "Applied \(r.ruleCount) rules to \(r.configPath)" + (r.backupPath != nil ? " (backup saved)" : "")
        } catch { status = "Apply failed: \(error.localizedDescription)" }
    }
    func chooseConfigLocation() {
        guard let url = savePanel(name: "karabiner.json", message: "Choose the karabiner.json that “Apply to Karabiner” should use.") else { return }
        configFile = url; status = "Apply will now write to \(url.path)"
    }
    func useDefaultConfig() { configFile = nil; status = "Apply will write to ~/.config/karabiner/karabiner.json" }

    func saveProjectAs() {
        let safe = project.name.replacingOccurrences(of: "/", with: "-")
        guard let url = savePanel(name: "\(safe).kaklayers.json", message: "Save this project to a file. Changes keep saving to it until you switch back.") else { return }
        projectFile = url; saveNow()
        if projectFile != nil { status = "Project saved to \(url.path)" }
    }
    func openProject() {
        guard let url = openPanel(message: "Open a KāKLayers project file."),
              let data = try? Data(contentsOf: url) else { return }
        do {
            let p = try JSONDecoder().decode(Project.self, from: data)
            project = p; activeLayer = nil; selectedKey = nil; projectFile = url
            status = "Opened \(url.lastPathComponent)"
        } catch { status = "That file isn't a KāKLayers project: \(error.localizedDescription)" }
    }
    func useDefaultProject() { projectFile = nil; saveNow(); status = "Project now saves in the app's own folder." }

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
