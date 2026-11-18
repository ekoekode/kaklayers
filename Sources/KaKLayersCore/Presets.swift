import Foundation

public struct Preset: Identifiable {
    public var id: String { name }
    public let name: String
    public let detail: String
    public let build: () -> (layers: [Layer], bindings: [KeyBinding])
}

public enum Presets {
    static func arrow(_ layer: String, _ from: String, _ to: String, mods: [String] = []) -> KeyBinding {
        KeyBinding(layerId: layer, fromKeys: [from], onPress: [.key(KeyCombo(key: to, modifiers: mods))])
    }

    public static let all: [Preset] = [
        Preset(name: "Caps Lock → Esc / Ctrl", detail: "Tap = Escape, hold = Control") {
            ([], [KeyBinding(fromKeys: ["caps_lock"], onPress: [.key(KeyCombo(key: "left_control"))], onTap: [.key(KeyCombo(key: "escape"))])])
        },
        Preset(name: "Hyper key (Caps Lock)", detail: "Hold = ⌘⌃⌥⇧ together, tap = Escape") {
            ([], [KeyBinding(fromKeys: ["caps_lock"],
                             onPress: [.key(KeyCombo(key: "left_shift", modifiers: ["left_command", "left_control", "left_option"]))],
                             onTap: [.key(KeyCombo(key: "escape"))])])
        },
        Preset(name: "Vim arrows layer (hold ;)", detail: "Hold ; then h/j/k/l = arrows; tap still types ;") {
            let id = "vim" + String(UUID().uuidString.prefix(4)).lowercased()
            let l = Layer(id: id, name: "Vim", colorHex: "#30A46C", triggerKeys: ["semicolon"],
                          tapAction: [.key(KeyCombo(key: "semicolon"))])
            return ([l], [arrow(id, "h", "left_arrow"), arrow(id, "j", "down_arrow"), arrow(id, "k", "up_arrow"), arrow(id, "l", "right_arrow"),
                          arrow(id, "u", "page_down"), arrow(id, "i", "page_up"), arrow(id, "y", "home"), arrow(id, "o", "end")])
        },
        Preset(name: "Numpad layer (hold Right ⌥)", detail: "7 8 9 / u i o … become a numpad under your right hand") {
            let id = "num" + String(UUID().uuidString.prefix(4)).lowercased()
            let l = Layer(id: id, name: "Numpad", colorHex: "#F5A524", triggerKeys: ["right_option"])
            let map: [(String, String)] = [("u","7"),("i","8"),("o","9"),("j","4"),("k","5"),("l","6"),("m","1"),("comma","2"),("period","3"),("spacebar","0"),("semicolon","period")]
            return ([l], map.map { arrow(id, $0.0, $0.1) })
        },
        Preset(name: "App launcher layer (hold Tab)", detail: "Tab+t Terminal, Tab+b Browser, Tab+f Finder; tap Tab still tabs") {
            let id = "app" + String(UUID().uuidString.prefix(4)).lowercased()
            let l = Layer(id: id, name: "Apps", colorHex: "#9B5DE5", triggerKeys: ["tab"], tapAction: [.key(KeyCombo(key: "tab"))])
            func open(_ k: String, _ bid: String) -> KeyBinding { KeyBinding(layerId: id, fromKeys: [k], onPress: [.openApp(bid)]) }
            return ([l], [open("t", "com.apple.Terminal"), open("b", "com.apple.Safari"), open("f", "com.apple.finder")])
        },
    ]
}

public extension Project {
    mutating func add(_ preset: Preset) {
        let r = preset.build()
        layers += r.layers
        bindings += r.bindings
    }
}

// MARK: Conflict checker

public struct Problem: Identifiable {
    public enum Severity { case warning, info }
    public let id = UUID()
    public let severity: Severity
    public let message: String
}

public enum ConflictChecker {
    public static func check(_ p: Project) -> [Problem] {
        var out: [Problem] = []
        var seen: [String: String] = [:]
        for l in p.layers {
            if l.triggerKeys.isEmpty {
                out.append(Problem(severity: .warning, message: "Layer “\(l.name)” has no trigger key, so it can never be activated."))
                continue
            }
            let sig = l.triggerKeys.sorted().joined(separator: "+")
            if let other = seen[sig] {
                out.append(Problem(severity: .warning, message: "Layers “\(other)” and “\(l.name)” share the same trigger."))
            }
            seen[sig] = l.name
            for b in p.bindings where b.layerId == nil && b.enabled && l.triggerKeys.count == 1 && b.fromKeys == l.triggerKeys && !b.isEmpty {
                out.append(Problem(severity: .warning, message: "Base binding on \(Keycodes.label(b.fromKeys[0])) is shadowed by layer “\(l.name)” using it as a trigger."))
            }
            if l.triggerKeys.count == 1, let t = l.triggerKeys.first, t == "button1" || t == "button2" {
                out.append(Problem(severity: .warning, message: "“\(l.name)”: \(Keycodes.label(t)) click as a layer trigger changes how normal clicking and dragging feel. The extra buttons (Middle, Back, Forward) are safer triggers."))
            }
            if l.mode == .momentary, l.tapAction.isEmpty, l.triggerKeys.count == 1, KarabinerCompiler.isModifier(l.triggerKeys[0]) {
                out.append(Problem(severity: .info, message: "“\(l.name)”: tapping \(Keycodes.label(l.triggerKeys[0])) outputs nothing, because it is a modifier. Add a tap output if you want one."))
            }
        }
        for l in p.layers {
            for m in KarabinerCompiler.analyze(l.tapAction) { out.append(Problem(severity: .warning, message: "“\(l.name)” tap: \(m)")) }
        }
        for b in p.bindings where b.enabled && !b.isEmpty {
            let where_ = "\(Keycodes.label(b.fromKeys.first ?? "?")) in “\(p.layer(b.layerId)?.name ?? "Base")”"
            for list in [b.onPress, b.onTap, b.onHold, b.onDoubleTap, b.onRelease] {
                for m in KarabinerCompiler.analyze(list) { out.append(Problem(severity: .warning, message: "\(where_): \(m)")) }
            }
        }
        let usesMouse = p.layers.contains { $0.triggerKeys.contains(where: Keycodes.isMouseButton) }
            || p.bindings.contains { $0.enabled && !$0.isEmpty && $0.fromKeys.contains(where: Keycodes.isMouseButton) }
        if usesMouse {
            out.append(Problem(severity: .info, message: "Mouse buttons only work for devices Karabiner sees as a mouse. Trackpad clicks and a Magic Mouse's left/right click may not be reported, so check Karabiner-Elements' EventViewer while you click."))
        }
        var dup: Set<String> = []
        for b in p.bindings where b.enabled && !b.isEmpty {
            let sig = "\(b.layerId ?? "-")|\(b.fromKeys.joined(separator: "+"))|\(b.fromModifiers.sorted().joined(separator: "+"))"
            if !dup.insert(sig).inserted {
                out.append(Problem(severity: .warning, message: "Two bindings on \(Keycodes.label(b.fromKeys.first ?? "?")) in “\(p.layer(b.layerId)?.name ?? "Base")” have identical input, so only the first can fire."))
            }
        }
        for b in p.bindings where b.layerId != nil && p.layer(b.layerId) == nil {
            out.append(Problem(severity: .warning, message: "A binding on \(Keycodes.label(b.fromKeys.first ?? "?")) belongs to a deleted layer."))
        }
        let shells = p.bindings.filter { b in (b.onPress + b.onTap + b.onHold + b.onRelease + b.onDoubleTap).contains { if case .shell = $0 { return true }; return false } }
        if !shells.isEmpty {
            out.append(Problem(severity: .info, message: "\(shells.count) binding(s) run shell commands. They execute with your user permissions when triggered."))
        }
        return out
    }
}

// MARK: Importer (simple remaps only)

public enum Importer {
    public struct Result { public var bindings: [KeyBinding]; public var skipped: Int }

    /// Imports plain "key → key(s)" manipulators from a karabiner.json or complex-modification file.
    /// Anything with conditions, tap/hold logic, etc. is skipped and counted, never silently altered.
    public static func importSimple(data: Data) throws -> Result {
        let root = try JSONSerialization.jsonObject(with: data) as? JSON ?? [:]
        var rules: [JSON] = (root["rules"] as? [JSON]) ?? []
        if rules.isEmpty, let profiles = root["profiles"] as? [JSON] {
            let p = profiles.first { ($0["selected"] as? Bool) == true } ?? profiles.first
            rules = ((p?["complex_modifications"] as? JSON)?["rules"] as? [JSON]) ?? []
        }
        var out: [KeyBinding] = []; var skipped = 0
        for rule in rules where !KarabinerCompiler.isOurs(rule["description"] as? String ?? "") {
            for m in (rule["manipulators"] as? [JSON]) ?? [] {
                guard m["conditions"] == nil, m["to_if_alone"] == nil, m["to_if_held_down"] == nil, m["to_after_key_up"] == nil,
                      m["to_delayed_action"] == nil,
                      let from = m["from"] as? JSON, let key = from["key_code"] as? String, from["simultaneous"] == nil,
                      let to = m["to"] as? [JSON], !to.isEmpty else { skipped += 1; continue }
                var actions: [Action] = []; var ok = true
                for e in to {
                    if let k = e["key_code"] as? String, e.keys.allSatisfy({ ["key_code", "modifiers"].contains($0) }) {
                        actions.append(.key(KeyCombo(key: k, modifiers: (e["modifiers"] as? [String]) ?? [])))
                    } else if let s = e["shell_command"] as? String { actions.append(.shell(s)) }
                    else { ok = false }
                }
                if !ok { skipped += 1; continue }
                let mand = ((from["modifiers"] as? JSON)?["mandatory"] as? [String]) ?? []
                out.append(KeyBinding(fromKeys: [key], fromModifiers: mand, onPress: actions, note: (m["description"] as? String) ?? ""))
            }
        }
        return Result(bindings: out, skipped: skipped)
    }
}
