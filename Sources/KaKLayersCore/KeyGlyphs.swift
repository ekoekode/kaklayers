import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Sizes shared by the layout engine and the fit tests, so "it fits" is checked against the real numbers.
public enum Metrics {
    public static let minKeyUnit: Double = 52     // smallest key unit the window allows
    public static let maxKeyUnit: Double = 72
    public static let keyGap: Double = 3
    public static let capPadding: Double = 5
    public static let roleIconWidth: Double = 9
    public static let rowFont: Double = 10
    public static let legendFont: Double = 10
    public static let gutter: Double = 16
    public static let minWindowWidth: Double = Keycodes.totalWidth * minKeyUnit + 2 * gutter

    /// Width available for one role row's text on a key `widthUnits` wide.
    public static func rowBudget(unit: Double, widthUnits: Double = 1) -> Double {
        widthUnits * unit - keyGap - 2 * capPadding - roleIconWidth - 3
    }
    /// Width available for the printed key legend.
    public static func legendBudget(unit: Double, widthUnits: Double) -> Double {
        widthUnits * unit - keyGap - 2 * capPadding
    }
}

public enum CapRole: String, CaseIterable {
    case press, tap, hold, doubleTap, release
    public var icon: String {
        switch self { case .press: "▸"; case .tap: "●"; case .hold: "◔"; case .doubleTap: "2×"; case .release: "⌁" }
    }
    public var title: String {
        switch self { case .press: "On press"; case .tap: "On tap"; case .hold: "On hold"; case .doubleTap: "On double-tap"; case .release: "On release" }
    }
}

public struct CapRow: Equatable {
    public var role: CapRole
    public var text: String
}

public struct CapContent: Equatable {
    public var rows: [CapRow]
    public var moreRoles: Int      // roles that did not fit in two rows, shown as "+n"
}

/// Short, never-truncated text for key caps. Every action offers candidates from most to least
/// detailed; the longest one that fits the budget is chosen, so nothing is ever cut with an ellipsis.
public enum KeyGlyphs {
    static let names: [String: String] = [
        "escape": "⎋", "tab": "⇥", "caps_lock": "⇪", "return_or_enter": "⏎", "keypad_enter": "⌤", "delete_or_backspace": "⌫",
        "delete_forward": "⌦", "spacebar": "␣", "left_arrow": "←", "right_arrow": "→", "up_arrow": "↑", "down_arrow": "↓",
        "home": "↖", "end": "↘", "page_up": "⇞", "page_down": "⇟", "fn": "fn",
        "left_command": "⌘", "right_command": "⌘", "left_shift": "⇧", "right_shift": "⇧",
        "left_option": "⌥", "right_option": "⌥", "left_control": "⌃", "right_control": "⌃",
        "grave_accent_and_tilde": "`", "hyphen": "-", "equal_sign": "=", "open_bracket": "[", "close_bracket": "]",
        "backslash": "\\", "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/",
        "keypad_slash": "/", "keypad_asterisk": "*", "keypad_hyphen": "-", "keypad_plus": "+", "keypad_period": ".", "keypad_equal_sign": "=",
        "keypad_num_lock": "⌧", "non_us_backslash": "|", "non_us_pound": "#",
        "international1": "_", "international3": "¥", "japanese_eisuu": "英", "japanese_kana": "か",
        "button1": "L", "button2": "R", "button3": "M", "button4": "⇠", "button5": "⇢",
    ]
    static let consumer: [String: String] = [
        "play_or_pause": "⏯", "mute": "🔇", "volume_increment": "🔊", "volume_decrement": "🔉",
        "mission_control": "▤", "launchpad": "▦", "spotlight": "⌕", "dashboard": "◧", "illumination_down": "◐", "illumination_up": "◑",
        "illumination_toggle": "◒", "dictation": "🎙", "microphone": "🎙", "eject": "⏏",
        "display_brightness_increment": "🔆", "display_brightness_decrement": "🔅", "fastforward": "⏩", "rewind": "⏪",
    ]
    static let modOrder = ["control", "option", "shift", "command"]
    static let modGlyph = ["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘", "fn": "fn"]

    public static func glyph(_ code: String) -> String {
        if let g = names[code] { return g }
        if let g = consumer[code] { return g }
        if code.hasPrefix("keypad_") { return String(code.dropFirst(7)) }
        if code.count == 1 { return code.uppercased() }
        if code.hasPrefix("f"), Int(code.dropFirst()) != nil { return code.uppercased() }
        return String(code.prefix(2)).uppercased()
    }

    /// "⌘⇧H", or "✦H" for all four modifiers.
    public static func combo(_ c: KeyCombo, compact: Bool = false) -> String {
        let mods = Set(c.modifiers.compactMap { Keycodes.genericModifier($0) ?? ($0 == "fn" ? "fn" : $0) })
        let key = glyph(c.key)
        if mods.isEmpty { return key }
        if compact, mods.count >= 3 { return "✦" + key }
        if mods.isSuperset(of: ["command", "control", "option", "shift"]) { return "✦" + key }
        return modOrder.filter(mods.contains).compactMap { modGlyph[$0] }.joined() + key
    }

    /// Candidates, most detailed first. The last one is always a single glyph.
    public static func candidates(_ a: Action) -> [String] {
        switch a {
        case .key(let c): return unique([combo(c), combo(c, compact: true), glyph(c.key)])
        case .keyDown(let c): return unique(["↧" + combo(c), "↧" + combo(c, compact: true), "↧" + glyph(c.key), "↧"])
        case .keyUp(let c): return unique(["↥" + glyph(c.key), "↥"])
        case .consumer(let k): return [consumer[k] ?? "♫"]
        case .mouse(let b): return unique(["🖱" + glyph(b), "🖱"])
        case .shell: return ["$"]
        case .delay(let ms): return unique(["⏱" + (ms >= 1000 ? "\(ms / 1000)s" : "\(ms)"), "⏱"])
        case .setVariable: return ["="]
        case .inputSource: return ["⌨︎"]
        case .openApp(let id):
            let n = (id.split(separator: ".").last.map(String.init) ?? "").prefix(3)
            return unique(["↗" + n, "↗"])
        case .openURL: return ["↗"]
        case .stickyModifier(let m): return [Keycodes.genericModifier(m).flatMap { modGlyph[$0] } ?? "⇪"]
        }
    }

    static func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>(); return xs.filter { seen.insert($0).inserted }
    }

    /// Fit as many actions as the budget allows; the rest become "+n". Never uses an ellipsis.
    public static func row(_ actions: [Action], budget: Double, fontSize: Double = Metrics.rowFont) -> String {
        guard !actions.isEmpty else { return "" }
        var out = ""
        for (i, a) in actions.enumerated() {
            let remaining = actions.count - i - 1
            let reserve = remaining > 0 ? TextFit.width("+\(remaining)", size: fontSize) : 0
            let cands = candidates(a)
            // choose the longest candidate that fits next to what we have (and the "+n" we may need)
            if let fit = cands.first(where: { TextFit.width(out + $0, size: fontSize) + reserve <= budget }) {
                out += fit
            } else {
                let left = actions.count - i
                let tail = "+\(left)"
                if out.isEmpty { return cands.last(where: { TextFit.width($0, size: fontSize) <= budget }) ?? cands.last! }
                // make room for the counter by dropping trailing glyphs if needed
                while !out.isEmpty && TextFit.width(out + tail, size: fontSize) > budget { out.removeLast() }
                return out + tail
            }
        }
        return out
    }

    public static func content(for b: KeyBinding, budget: Double) -> CapContent {
        let all: [(CapRole, [Action])] = [(.press, b.onPress), (.tap, b.onTap), (.hold, b.onHold), (.doubleTap, b.onDoubleTap), (.release, b.onRelease)]
            .filter { !$0.1.isEmpty }
        let rows = all.prefix(2).map { CapRow(role: $0.0, text: row($0.1, budget: budget)) }
        return CapContent(rows: Array(rows), moreRoles: max(0, all.count - 2))
    }

    /// Plain-language description for hover cards and the dock.
    public static func words(_ a: Action) -> String {
        switch a {
        case .key(let c): return "Press " + combo(c)
        case .keyDown(let c): return "Hold down " + combo(c)
        case .keyUp(let c): return "Release " + glyph(c.key)
        case .consumer(let k): return "Media: " + k.replacingOccurrences(of: "_", with: " ")
        case .mouse(let b): return "Click the " + Keycodes.mouseName(b).lowercased() + " button"
        case .shell(let s): return "Run: " + s
        case .delay(let ms): return "Wait \(ms) ms"
        case .setVariable(let n, let v): return "Set \(n) = \(v)"
        case .inputSource(let i): return "Switch input to " + i
        case .openApp(let b): return "Open " + b
        case .openURL(let u): return "Open " + u
        case .stickyModifier(let m): return "Toggle sticky " + m.replacingOccurrences(of: "_", with: " ")
        }
    }
}

public enum TextFit {
    /// Width of `text` in the system font at `size` (SF Pro). Falls back to a conservative estimate off-Mac.
    nonisolated(unsafe) private static var cache: [String: Double] = [:]
    public static func width(_ text: String, size: Double, weight: Double = 0) -> Double {
        #if canImport(AppKit)
        let id = "\(size)|\(weight)|\(text)"
        if let w = cache[id] { return w }
        let font = NSFont.systemFont(ofSize: CGFloat(size), weight: NSFont.Weight(rawValue: CGFloat(weight)))
        let w = Double((text as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
        cache[id] = w
        return w
        #else
        return Double(text.count) * size * 0.75
        #endif
    }
}
