import Foundation

/// A key plus modifiers, e.g. cmd+shift+4. `key` is a Karabiner `key_code` name.
public struct KeyCombo: Codable, Hashable {
    public var key: String
    public var modifiers: [String]
    public init(key: String, modifiers: [String] = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// One step in an action chain. Chains run in order, so delays and shell
/// commands can be interleaved with keypresses.
public enum Action: Codable, Hashable {
    case key(KeyCombo)               // key press: down and up
    case keyDown(KeyCombo)           // hold a key down (until a matching key up, or while the trigger is held)
    case keyUp(KeyCombo)             // release a key that was held down
    case consumer(String)            // consumer_key_code, e.g. "play_or_pause"
    case mouse(String)               // pointing_button, e.g. "button1"
    case shell(String)               // shell_command
    case delay(Int)                  // milliseconds
    case setVariable(name: String, value: Int)
    case inputSource(String)         // input_source_id
    case openApp(String)             // bundle identifier
    case openURL(String)
    case stickyModifier(String)      // e.g. "left_shift" (toggles)
}

public enum LayerMode: String, Codable, CaseIterable {
    case momentary   // active while the trigger is held
    case toggle      // press to turn on, press again to turn off
}

public struct DeviceID: Codable, Hashable {
    public var vendorId: Int
    public var productId: Int
    public init(vendorId: Int, productId: Int) {
        self.vendorId = vendorId
        self.productId = productId
    }
}

/// A keyboard layer. The base layer is implicit (layerId == nil on bindings).
public struct Layer: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var mode: LayerMode
    /// Trigger keys. One key = normal; several = pressed together (e.g. cmd+ctrl+shift).
    public var triggerKeys: [String]
    /// Output when the trigger is tapped and released without using the layer.
    public var tapAction: [Action]
    public var tapTimeoutMs: Int

    public init(id: String = UUID().uuidString.prefix(8).lowercased(),
                name: String,
                colorHex: String,
                mode: LayerMode = .momentary,
                triggerKeys: [String] = [],
                tapAction: [Action] = [],
                tapTimeoutMs: Int = 200) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.mode = mode
        self.triggerKeys = triggerKeys
        self.tapAction = tapAction
        self.tapTimeoutMs = tapTimeoutMs
    }

    public var variableName: String { "layer_\(id)" }
}

/// A remap of one input (key + optional modifiers) in one layer.
public struct KeyBinding: Codable, Identifiable, Hashable {
    public var id: UUID
    public var layerId: String?          // nil = base layer
    public var fromKeys: [String]        // 1 key, or several for a chord
    public var fromModifiers: [String]   // mandatory modifiers
    public var onPress: [Action]
    public var onTap: [Action]           // key pressed and released alone
    public var onHold: [Action]          // key held past holdThresholdMs
    public var onRelease: [Action]
    public var onDoubleTap: [Action]
    public var tapTimeoutMs: Int
    public var holdThresholdMs: Int
    public var doubleTapMs: Int
    public var apps: [String]            // bundle identifiers
    public var appsExclude: Bool         // true = only when NOT in these apps
    public var devices: [DeviceID]
    public var note: String
    public var enabled: Bool

    public init(id: UUID = UUID(),
                layerId: String? = nil,
                fromKeys: [String],
                fromModifiers: [String] = [],
                onPress: [Action] = [],
                onTap: [Action] = [],
                onHold: [Action] = [],
                onRelease: [Action] = [],
                onDoubleTap: [Action] = [],
                tapTimeoutMs: Int = 200,
                holdThresholdMs: Int = 500,
                doubleTapMs: Int = 250,
                apps: [String] = [],
                appsExclude: Bool = false,
                devices: [DeviceID] = [],
                note: String = "",
                enabled: Bool = true) {
        self.id = id
        self.layerId = layerId
        self.fromKeys = fromKeys
        self.fromModifiers = fromModifiers
        self.onPress = onPress
        self.onTap = onTap
        self.onHold = onHold
        self.onRelease = onRelease
        self.onDoubleTap = onDoubleTap
        self.tapTimeoutMs = tapTimeoutMs
        self.holdThresholdMs = holdThresholdMs
        self.doubleTapMs = doubleTapMs
        self.apps = apps
        self.appsExclude = appsExclude
        self.devices = devices
        self.note = note
        self.enabled = enabled
    }

    public var isEmpty: Bool {
        onPress.isEmpty && onTap.isEmpty && onHold.isEmpty && onRelease.isEmpty && onDoubleTap.isEmpty
    }
}

public struct Project: Codable, Hashable {
    public var name: String
    public var layers: [Layer]
    public var bindings: [KeyBinding]

    public init(name: String = "My Layers", layers: [Layer] = [], bindings: [KeyBinding] = []) {
        self.name = name
        self.layers = layers
        self.bindings = bindings
    }

    /// Any binding for the key (prefers the plain, modifier-free one). Used for display.
    public func binding(layer: String?, key: String) -> KeyBinding? {
        let all = bindings.filter { $0.layerId == layer && $0.fromKeys == [key] }
        return all.first { $0.fromModifiers.isEmpty } ?? all.first
    }
    /// Exact variant: same layer, key and modifier set.
    public func binding(layer: String?, key: String, mods: [String]) -> KeyBinding? {
        binding(layer: layer, keys: [key], mods: mods)
    }
    /// Exact variant for a single key or a chord (several keys pressed together).
    public func binding(layer: String?, keys: [String], mods: [String]) -> KeyBinding? {
        bindings.first { $0.layerId == layer && $0.fromKeys == keys && Set($0.fromModifiers) == Set(mods) }
    }
    /// Non-empty chords in a layer that include `key`.
    public func chords(layer: String?, containing key: String) -> [KeyBinding] {
        bindings.filter { $0.layerId == layer && $0.fromKeys.count > 1 && $0.fromKeys.contains(key) && !$0.isEmpty }
    }
    /// The variant a key should open on: the plain binding if there is one, otherwise the first modifier variant that has actions.
    /// This is the binding the key cap shows, so the cap, the workflow and the Clear button always agree.
    public func defaultVariantMods(layer: String?, key: String) -> [String] {
        let vs = bindings.filter { $0.layerId == layer && $0.fromKeys == [key] && !$0.isEmpty }
        if vs.isEmpty || vs.contains(where: { $0.fromModifiers.isEmpty }) { return [] }
        return vs[0].fromModifiers
    }

    public func variants(layer: String?, key: String) -> [KeyBinding] {
        bindings.filter { $0.layerId == layer && $0.fromKeys == [key] }
    }
    public func layer(_ id: String?) -> Layer? {
        guard let id else { return nil }
        return layers.first { $0.id == id }
    }

    /// Move a layer so it sits just before `target` (or at the end when `target` is nil).
    /// Layer order is rule order, so it decides priority when several layers are held.
    public mutating func moveLayer(_ id: String, before target: String?) {
        guard id != target, let from = layers.firstIndex(where: { $0.id == id }) else { return }
        let layer = layers.remove(at: from)
        if let t = target, let to = layers.firstIndex(where: { $0.id == t }) { layers.insert(layer, at: to) }
        else { layers.append(layer) }
    }

    public mutating func shiftLayer(_ id: String, by delta: Int) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(i + delta, 0), layers.count - 1)
        guard j != i else { return }
        layers.swapAt(i, j)
    }
}

public extension Project {
    /// Everything configured on one key in one layer: the plain binding and any modifier variants
    /// (workflow, timings, apps, devices). Chords that merely include the key are not part of it.
    func keySettings(layer: String?, key: String) -> [KeyBinding] {
        bindings.filter { $0.layerId == layer && $0.fromKeys == [key] && !$0.isEmpty }
    }

    /// Replaces the target key's single-key bindings in `layer` with copies of `settings` (fresh ids).
    mutating func paste(_ settings: [KeyBinding], layer: String?, key: String) {
        bindings.removeAll { $0.layerId == layer && $0.fromKeys == [key] }
        bindings += settings.map { var b = $0; b.id = UUID(); b.layerId = layer; b.fromKeys = [key]; return b }
    }
}

public extension Project {
    /// Removes several layers and every binding that belongs to them in one change.
    mutating func removeLayers(_ ids: Set<String>) {
        layers.removeAll { ids.contains($0.id) }
        bindings.removeAll { $0.layerId.map(ids.contains) ?? false }
    }
}
