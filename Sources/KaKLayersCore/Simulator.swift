import Foundation

public struct Resolution {
    public var binding: KeyBinding?
    public var layer: Layer?        // nil = base
    public var explanation: String
}

/// Mirrors the order the compiler emits rules in, so "what will fire" matches Karabiner.
public enum Simulator {
    public static func resolve(_ p: Project, held: Set<String>, key: String, mods: Set<String> = []) -> Resolution {
        // Layer rules are emitted in project order, each before the base rule.
        for l in p.layers where held.contains(l.id) {
            if let b = best(p, layer: l.id, key: key, mods: mods) {
                return Resolution(binding: b, layer: l, explanation: "\(Keycodes.label(key)) fires the “\(l.name)” layer binding.")
            }
            if l.mode == .toggle, l.triggerKeys == [key] {
                return Resolution(binding: nil, layer: l, explanation: "\(Keycodes.label(key)) turns layer “\(l.name)” off.")
            }
        }
        for l in p.layers where !held.contains(l.id) && l.triggerKeys == [key] {
            return Resolution(binding: nil, layer: l, explanation: "\(Keycodes.label(key)) activates layer “\(l.name)”" +
                              (l.tapAction.isEmpty ? "." : " (tap alone outputs a different key)."))
        }
        if let b = best(p, layer: nil, key: key, mods: mods) {
            return Resolution(binding: b, layer: nil, explanation: "\(Keycodes.label(key)) fires its base-layer binding.")
        }
        return Resolution(binding: nil, layer: nil, explanation: "\(Keycodes.label(key)) is passed through unchanged.")
    }

    /// Most specific enabled binding whose required modifiers are all held.
    static func best(_ p: Project, layer: String?, key: String, mods: Set<String>) -> KeyBinding? {
        p.variants(layer: layer, key: key)
            .filter { $0.enabled && !$0.isEmpty && Set($0.fromModifiers).isSubset(of: mods) }
            .max { $0.fromModifiers.count < $1.fromModifiers.count }
    }
}
