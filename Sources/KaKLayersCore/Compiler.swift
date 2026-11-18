import Foundation

public typealias JSON = [String: Any]

/// Compiles a `Project` into Karabiner-Elements "complex modifications" JSON.
public enum KarabinerCompiler {
    /// Every rule we generate starts with this so we can replace only our own rules.
    public static let rulePrefix = "[KaKLayers] "
    /// Prefix used before the rename; still recognised as ours and rewritten on the next apply.
    public static let legacyRulePrefix = "[Layers] "
    public static func isOurs(_ description: String) -> Bool { description.hasPrefix(rulePrefix) || description.hasPrefix(legacyRulePrefix) }

    public static func compile(_ project: Project) -> JSON {
        ["title": "KaKLayers: \(project.name)", "rules": rules(for: project)]
    }

    public static func rules(for project: Project) -> [JSON] {
        var rules: [JSON] = []

        for layer in project.layers {
            var manips: [JSON] = []
            let ctx = Context(project: project)
            // Toggle-off must win over the layer's own bindings.
            if layer.mode == .toggle { manips += expand([toggleOff(layer)], keys: layer.triggerKeys, modifiers: []) }
            for b in ordered(project.bindings.filter { $0.layerId == layer.id }) where b.enabled && !b.isEmpty {
                manips += compile(binding: b, ctx: ctx)
            }
            manips += expand([triggerOn(layer)], keys: layer.triggerKeys, modifiers: [])
            rules.append(["description": rulePrefix + layer.name, "manipulators": manips])
        }

        let base = ordered(project.bindings.filter { $0.layerId == nil }).filter { $0.enabled && !$0.isEmpty }
        if !base.isEmpty {
            let ctx = Context(project: project)
            rules.append(["description": rulePrefix + "Base layer",
                          "manipulators": base.flatMap { compile(binding: $0, ctx: ctx) }])
        }
        return rules
    }

    /// Karabiner uses the first matching manipulator. Chords must precede the single keys they
    /// contain, and bindings requiring modifiers must precede plain ones (plain keys accept any
    /// modifiers). Stable sort keeps the user's order otherwise.
    static func ordered(_ bs: [KeyBinding]) -> [KeyBinding] {
        bs.enumerated().sorted { a, b in
            if a.element.fromKeys.count != b.element.fromKeys.count { return a.element.fromKeys.count > b.element.fromKeys.count }
            if a.element.fromModifiers.count != b.element.fromModifiers.count { return a.element.fromModifiers.count > b.element.fromModifiers.count }
            return a.offset < b.offset
        }.map(\.element)
    }

    struct Context { let project: Project }

    // MARK: Original function

    /// What a key does with no rules at all: itself, with the modifiers the binding requires. Empty for chords.
    /// Anything the user has not defined falls back to this, so a tap never swallows the key.
    static func original(keys: [String], modifiers: [String]) -> [Action] {
        guard keys.count == 1, let k = keys.first else { return [] }
        if Keycodes.codeField(k) != "key_code" { return [.consumer(k)] }
        return [.key(KeyCombo(key: k, modifiers: modifiers))]
    }

    /// Modifier keys have no character to give back when tapped, so layers on them stay silent.
    static func isModifier(_ key: String) -> Bool { Keycodes.genericModifier(key) != nil }

    // MARK: Layer triggers

    static func triggerOn(_ layer: Layer) -> JSON {
        var m: JSON = ["type": "basic", "from": from(keys: layer.triggerKeys, modifiers: [])]
        var params: JSON = [:]
        switch layer.mode {
        case .momentary:
            m["to"] = [["set_variable": ["name": layer.variableName, "value": 1, "key_up_value": 0]]]
        case .toggle:
            m["to"] = [["set_variable": ["name": layer.variableName, "value": 1]]]
            m["conditions"] = [varCond(layer.variableName, 0, equals: true)]
        }
        // Tapped without using the layer: the user's tap action, or else the key itself (Shift etc. still apply).
        var tap = layer.tapAction
        if tap.isEmpty, layer.triggerKeys.count == 1, let k = layer.triggerKeys.first, !isModifier(k) {
            tap = original(keys: layer.triggerKeys, modifiers: [])
        }
        if !tap.isEmpty && layer.mode == .momentary {
            m["to_if_alone"] = events(tap)
            params["basic.to_if_alone_timeout_milliseconds"] = layer.tapTimeoutMs
        }
        if layer.triggerKeys.count > 1 { params["basic.simultaneous_threshold_milliseconds"] = 100 }
        if !params.isEmpty { m["parameters"] = params }
        return m
    }

    static func toggleOff(_ layer: Layer) -> JSON {
        ["type": "basic",
         "from": from(keys: layer.triggerKeys, modifiers: []),
         "to": [["set_variable": ["name": layer.variableName, "value": 0]]],
         "conditions": [varCond(layer.variableName, 1, equals: true)]]
    }

    // MARK: Bindings

    /// A binding on a top-row key is written for the function key and for the media key(s) it sends without fn.
    static func compile(binding b: KeyBinding, ctx: Context) -> [JSON] {
        expand(compileSingle(binding: b, ctx: ctx), keys: b.fromKeys, modifiers: b.fromModifiers)
    }

    /// Repeats `manipulators` once per alias of a single top-row key, changing only the `from`.
    static func expand(_ manipulators: [JSON], keys: [String], modifiers: [String]) -> [JSON] {
        guard keys.count == 1, let k = keys.first else { return manipulators }
        let refs = Keycodes.aliases(of: k)
        guard !refs.isEmpty else { return manipulators }
        var out = manipulators
        for r in refs {
            out += manipulators.map { var m = $0; m["from"] = from(ref: r, modifiers: modifiers); return m }
        }
        return out
    }

    static func compileSingle(binding b: KeyBinding, ctx: Context) -> [JSON] {
        var conditions: [JSON] = []
        if let lid = b.layerId, let layer = ctx.project.layer(lid) {
            conditions.append(varCond(layer.variableName, 1, equals: true))
        }
        if !b.apps.isEmpty {
            conditions.append(["type": b.appsExclude ? "frontmost_application_unless" : "frontmost_application_if",
                               "bundle_identifiers": b.apps.map(bundleRegex)])
        }
        if !b.devices.isEmpty {
            conditions.append(["type": "device_if",
                               "identifiers": b.devices.map { ["vendor_id": $0.vendorId, "product_id": $0.productId] }])
        }

        let fromDict = from(keys: b.fromKeys, modifiers: b.fromModifiers)
        var params: JSON = [:]
        if b.fromKeys.count > 1 { params["basic.simultaneous_threshold_milliseconds"] = 100 }

        func manipulator(from f: JSON, to: [JSON], extra: JSON = [:], conds: [JSON], p: JSON) -> JSON {
            var m: JSON = ["type": "basic", "from": f]
            if !to.isEmpty { m["to"] = to }
            for (k, v) in extra { m[k] = v }
            if !conds.isEmpty { m["conditions"] = conds }
            if !p.isEmpty { m["parameters"] = p }
            if !b.note.isEmpty { m["description"] = b.note }
            return m
        }

        // Whatever is not defined keeps the key's own function.
        let original = Self.original(keys: b.fromKeys, modifiers: b.fromModifiers)
        let tapFallback = (b.onPress.isEmpty && b.onTap.isEmpty) ? original : []

        // Double tap: a "pending tap" variable armed by the first press.
        if !b.onDoubleTap.isEmpty {
            let v = "dt_" + b.id.uuidString.prefix(8).lowercased()
            var second = params
            second["basic.to_if_alone_timeout_milliseconds"] = b.tapTimeoutMs
            let secondM = manipulator(
                from: fromDict,
                to: [setVar(v, 0)] + events(b.onDoubleTap),
                conds: conditions + [varCond(v, 1, equals: true)],
                p: second)

            var first = params
            first["basic.to_delayed_action_delay_milliseconds"] = b.doubleTapMs
            let single = events(b.onTap.isEmpty ? tapFallback : b.onTap)
            let firstM = manipulator(
                from: fromDict,
                to: [setVar(v, 1)] + events(b.onPress),
                extra: ["to_delayed_action": [
                    "to_if_invoked": [setVar(v, 0)] + single,
                    "to_if_canceled": [setVar(v, 0)],
                ] as JSON],
                conds: conditions, p: first)
            return [secondM, firstM]
        }

        var extra: JSON = [:]
        // A hold-only key still types itself when tapped; a release-only key passes the press through.
        let tap = !b.onTap.isEmpty ? b.onTap : (!b.onHold.isEmpty ? tapFallback : [])
        if !tap.isEmpty {
            extra["to_if_alone"] = events(tap)
            params["basic.to_if_alone_timeout_milliseconds"] = b.tapTimeoutMs
        }
        let releaseOnly = b.onPress.isEmpty && b.onTap.isEmpty && b.onHold.isEmpty && !b.onRelease.isEmpty
        if !b.onHold.isEmpty {
            extra["to_if_held_down"] = events(b.onHold)
            params["basic.to_if_held_down_threshold_milliseconds"] = b.holdThresholdMs
        }
        if !b.onRelease.isEmpty { extra["to_after_key_up"] = events(b.onRelease) }
        return [manipulator(from: fromDict, to: events(releaseOnly ? original : b.onPress), extra: extra, conds: conditions, p: params)]
    }

    // MARK: Pieces

    static func from(keys: [String], modifiers: [String]) -> JSON {
        var f: JSON = [:]
        if keys.count > 1 {
            f["simultaneous"] = keys.map { ["key_code": $0] }
            f["simultaneous_options"] = ["key_down_order": "insensitive", "key_up_order": "insensitive"]
        } else if let k = keys.first {
            f = [Keycodes.codeField(k): k]
        }
        return withModifiers(f, modifiers)
    }

    static func from(ref: Keycodes.KeyRef, modifiers: [String]) -> JSON {
        withModifiers([ref.field: ref.code], modifiers)
    }

    private static func withModifiers(_ from: JSON, _ modifiers: [String]) -> JSON {
        var f = from
        var mods: JSON = ["optional": ["any"]]
        if !modifiers.isEmpty { mods["mandatory"] = modifiers }
        f["modifiers"] = mods
        return f
    }

    static func varCond(_ name: String, _ value: Int, equals: Bool) -> JSON {
        ["type": equals ? "variable_if" : "variable_unless", "name": name, "value": value]
    }

    static func setVar(_ name: String, _ value: Int) -> JSON {
        ["set_variable": ["name": name, "value": value]]
    }

    static func bundleRegex(_ id: String) -> String {
        "^" + NSRegularExpression.escapedPattern(for: id) + "$"
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func events(_ actions: [Action]) -> [JSON] { actions.map(event) }

    static func event(_ a: Action) -> JSON {
        switch a {
        case .key(let c):
            var e: JSON = ["key_code": c.key]
            if !c.modifiers.isEmpty { e["modifiers"] = c.modifiers }
            return e
        case .consumer(let k): return [Keycodes.codeField(k): k]
        case .mouse(let b): return ["pointing_button": b]
        case .shell(let s): return ["shell_command": s]
        case .delay(let ms): return ["key_code": "vk_none", "hold_down_milliseconds": ms]
        case .setVariable(let n, let v): return setVar(n, v)
        case .inputSource(let id): return ["select_input_source": ["input_source_id": "^" + NSRegularExpression.escapedPattern(for: id) + "$"]]
        case .openApp(let id): return ["shell_command": "open -b \(shellQuote(id))"]
        case .openURL(let u): return ["shell_command": "open \(shellQuote(u))"]
        case .stickyModifier(let m): return ["sticky_modifier": [m: "toggle"]]
        }
    }

    // MARK: Serialization

    public static func jsonString(_ json: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
