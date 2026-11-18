import Foundation

public struct KeyDef: Hashable {
    public let code: String      // Karabiner key_code
    public let label: String
    public let mac: Int          // macOS virtual key code
    public let x: Double, y: Double, w: Double, h: Double
}

public enum Keycodes {
    public static let consumerKeys: Set<String> = [
        "play_or_pause", "mute", "volume_increment", "volume_decrement",
        "display_brightness_increment", "display_brightness_decrement", "fastforward", "rewind",
        "dictation", "microphone", "eject",
    ]
    public static func isConsumer(_ k: String) -> Bool { consumerKeys.contains(k) }

    /// Karabiner keeps media/system keys in three separate families (names verified against the installed
    /// Karabiner-Elements' own key list). Backlight keys and Mission Control/Launchpad/Spotlight are vendor codes.
    public static let vendorKeyboardKeys: Set<String> = ["mission_control", "launchpad", "spotlight", "dashboard"]
    public static let vendorTopCaseKeys: Set<String> = ["illumination_up", "illumination_down", "illumination_toggle"]
    /// Every non-letter "media" output offered in the picker.
    public static var mediaKeys: [String] { (Array(consumerKeys) + Array(vendorKeyboardKeys) + Array(vendorTopCaseKeys)).sorted() }
    /// The JSON field a key belongs in: key_code, consumer_key_code or one of the Apple vendor fields.
    public static func codeField(_ k: String) -> String {
        if consumerKeys.contains(k) { return "consumer_key_code" }
        if vendorKeyboardKeys.contains(k) { return "apple_vendor_keyboard_key_code" }
        if vendorTopCaseKeys.contains(k) { return "apple_vendor_top_case_key_code" }
        return "key_code"
    }

    /// One key as Karabiner names it: which JSON field it goes in, and its code.
    public struct KeyRef: Hashable {
        public let field: String
        public let code: String
        public init(_ field: String, _ code: String) { self.field = field; self.code = code }
    }

    /// Each top-row slot: the plain function key, plus every key a Mac keyboard may send for it without fn.
    /// Karabiner treats these as different keys, and which one arrives depends on the keyboard model, so a rule
    /// on one of them is written for all of them (names checked against the installed Karabiner-Elements).
    static let fRowSlots: [[KeyRef]] = {
        func f(_ n: Int) -> KeyRef { KeyRef("key_code", "f\(n)") }
        func c(_ x: String) -> KeyRef { KeyRef("consumer_key_code", x) }
        func kb(_ x: String) -> KeyRef { KeyRef("apple_vendor_keyboard_key_code", x) }
        func top(_ x: String) -> KeyRef { KeyRef("apple_vendor_top_case_key_code", x) }
        return [
            [f(1), c("display_brightness_decrement"), top("brightness_down"), kb("brightness_down")],
            [f(2), c("display_brightness_increment"), top("brightness_up"), kb("brightness_up")],
            [f(3), kb("mission_control"), c("ac_desktop_show_all_windows")],
            [f(4), kb("launchpad"), c("ac_desktop_show_all_applications"), kb("spotlight"), c("ac_search")],
            [f(5), top("illumination_down"), c("dictation")],
            [f(6), top("illumination_up")],
            [f(7), c("rewind"), c("scan_previous_track")],
            [f(8), c("play_or_pause")],
            [f(9), c("fastforward"), c("fast_forward"), c("scan_next_track")],
            [f(10), c("mute")],
            [f(11), c("volume_decrement")],
            [f(12), c("volume_increment")],
        ]
    }()

    /// The other keys that share a top-row slot with `code` (empty if it is not in one).
    public static func aliases(of code: String) -> [KeyRef] {
        guard let slot = fRowSlots.first(where: { $0.contains { $0.code == code } }) else { return [] }
        let primary = KeyRef(codeField(code), code)
        return slot.filter { $0 != primary }
    }

    /// What the Magic Keyboard F-row sends without fn (media mode), with a one-glyph legend.
    public static let mediaRow: [(f: String, code: String, label: String)] = [
        ("f1", "display_brightness_decrement", "🔅"), ("f2", "display_brightness_increment", "🔆"),
        ("f3", "mission_control", "▤"), ("f4", "launchpad", "▦"),
        ("f5", "illumination_down", "◐"), ("f6", "illumination_up", "◑"),
        ("f7", "rewind", "⏪"), ("f8", "play_or_pause", "⏯"), ("f9", "fastforward", "⏩"),
        ("f10", "mute", "🔇"), ("f11", "volume_decrement", "🔉"), ("f12", "volume_increment", "🔊"),
    ]
    public static func mediaCode(forFunction f: String) -> String? { mediaRow.first { $0.f == f }?.code }

    /// macOS modifier virtual key codes -> Karabiner names.
    public static let modifierMac: [Int: String] = [
        55: "left_command", 54: "right_command", 56: "left_shift", 60: "right_shift",
        58: "left_option", 61: "right_option", 59: "left_control", 62: "right_control",
        57: "caps_lock", 63: "fn",
    ]

    /// Collapse left_/right_ names to the generic modifier names Karabiner uses in `modifiers`.
    public static func genericModifier(_ name: String) -> String? {
        switch name {
        case "left_command", "right_command": return "command"
        case "left_shift", "right_shift": return "shift"
        case "left_option", "right_option": return "option"
        case "left_control", "right_control": return "control"
        case "fn": return "fn"
        default: return nil
        }
    }

    public static let all: [KeyDef] = mainBlock + navCluster + numpad
    public static let byCode: [String: KeyDef] = Dictionary((all + isoExtras + jisExtras + mediaDefs).map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })

    public enum LayoutKind: String, CaseIterable, Codable { case ansi = "ANSI", iso = "ISO", jis = "JIS" }

    static let isoExtras: [KeyDef] = [
        KeyDef(code: "non_us_backslash", label: "\\ |", mac: 10, x: 1.25, y: 4.5, w: 1, h: 1),
        KeyDef(code: "non_us_pound", label: "# ~", mac: 42, x: 12.75, y: 3.5, w: 0.75, h: 1),
    ]

    static let jisExtras: [KeyDef] = [
        KeyDef(code: "international3", label: "¥", mac: 93, x: 12, y: 1.5, w: 1, h: 1),
        KeyDef(code: "international1", label: "_", mac: 94, x: 12.25, y: 4.5, w: 1, h: 1),
        KeyDef(code: "japanese_eisuu", label: "英数", mac: 102, x: 5.25, y: 5.5, w: 1, h: 1),
        KeyDef(code: "japanese_kana", label: "かな", mac: 104, x: 9.25, y: 5.5, w: 1, h: 1),
    ]

    /// JIS: no key left of 1, ¥ before delete, @ [ ] : on the right, extra _ key, 英数/かな around a short space bar.
    /// Labels follow the Apple JIS keyboard; key names are Karabiner's JIS names.
    static func jisLayout() -> [KeyDef] {
        let fixed = all.filter { $0.y == 0 || $0.x >= 15.5 || ["left_arrow", "up_arrow", "down_arrow", "right_arrow"].contains($0.code) }
        var r = fixed
        r += row(1.5, [k("1","1",18), k("2","2",19), k("3","3",20), k("4","4",21), k("5","5",23), k("6","6",22), k("7","7",26),
                       k("8","8",28), k("9","9",25), k("0","0",29), k("hyphen","-",27), k("equal_sign","^",24),
                       k("international3","¥",93), k("delete_or_backspace","⌫",51,2)])
        r += row(2.5, [k("tab","tab",48,1.5), k("q","Q",12), k("w","W",13), k("e","E",14), k("r","R",15), k("t","T",17),
                       k("y","Y",16), k("u","U",32), k("i","I",34), k("o","O",31), k("p","P",35),
                       k("open_bracket","@",33), k("close_bracket","[",30)])
        r += row(3.5, [k("caps_lock","caps",57,1.75), k("a","A",0), k("s","S",1), k("d","D",2), k("f","F",3), k("g","G",5),
                       k("h","H",4), k("j","J",38), k("k","K",40), k("l","L",37), k("semicolon",";",41), k("quote",":",39),
                       k("non_us_pound","]",42,0.75)])
        r.append(KeyDef(code: "return_or_enter", label: "return", mac: 36, x: 13.5, y: 2.5, w: 1.5, h: 2))
        r += row(4.5, [k("left_shift","shift",56,2.25), k("z","Z",6), k("x","X",7), k("c","C",8), k("v","V",9), k("b","B",11),
                       k("n","N",45), k("m","M",46), k("comma",",",43), k("period",".",47), k("slash","/",44),
                       k("international1","_",94), k("right_shift","shift",60,1.75)])
        r += row(5.5, [k("fn","fn",63), k("left_control","ctrl",59), k("left_option","opt",58), k("left_command","cmd",55,1.25),
                       k("japanese_eisuu","英数",102), k("spacebar","space",49,4), k("japanese_kana","かな",104),
                       k("right_command","cmd",54,1.25)])
        return r
    }

    /// Keys to draw for a physical layout.
    /// F1–F12 drawn as the media keys they send without fn.
    static let mediaDefs: [KeyDef] = mediaRow.compactMap { m in
        mainBlock.first { $0.code == m.f }.map { KeyDef(code: m.code, label: m.label, mac: $0.mac, x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
    }

    public static func layout(_ kind: LayoutKind, mediaRow media: Bool = false) -> [KeyDef] {
        let keys = baseLayout(kind)
        guard media else { return keys }
        let swap = Dictionary(uniqueKeysWithValues: mediaRow.map { ($0.f, $0.code) })
        return keys.map { k in swap[k.code].flatMap { byCode[$0] } ?? k }
    }

    static func baseLayout(_ kind: LayoutKind) -> [KeyDef] {
        if kind == .jis { return jisLayout() }
        guard kind == .iso else { return all }
        func shifted(_ k: KeyDef, x: Double? = nil, w: Double? = nil, h: Double? = nil) -> KeyDef {
            KeyDef(code: k.code, label: k.label, mac: k.mac, x: x ?? k.x, y: k.y, w: w ?? k.w, h: h ?? k.h)
        }
        var out: [KeyDef] = []
        for k in all {
            switch k.code {
            case "left_shift": out.append(shifted(k, w: 1.25))
            case "backslash": continue
            case "return_or_enter": out.append(KeyDef(code: k.code, label: k.label, mac: k.mac, x: 13.5, y: 2.5, w: 1.5, h: 2))
            default: out.append(k)
            }
        }
        // Shift (1.25) + extra key (1.0) = ANSI shift width (2.25), so Z..slash keep their x.
        out += isoExtras
        return out
    }
    public static let byMac: [Int: KeyDef] = Dictionary(all.map { ($0.mac, $0) }, uniquingKeysWith: { a, _ in a })

    public static func label(_ code: String) -> String { byCode[code]?.label ?? code }

    // MARK: Layout (units of one key; main block starts x=0, nav x=15.5, numpad x=19)

    private typealias Spec = (String, String, Int, Double) // code,label,mac,width

    private static func row(_ y: Double, x0: Double = 0, _ specs: [Spec]) -> [KeyDef] {
        var x = x0
        var out: [KeyDef] = []
        for (code, label, mac, w) in specs {
            out.append(KeyDef(code: code, label: label, mac: mac, x: x, y: y, w: w, h: 1))
            x += w
        }
        return out
    }

    private static func k(_ c: String, _ l: String, _ m: Int, _ w: Double = 1) -> Spec { (c, l, m, w) }

    static let mainBlock: [KeyDef] = {
        var r: [KeyDef] = []
        r += row(0, [k("escape", "esc", 53, 1.5)] )
        r += row(0, x0: 2, [k("f1","F1",122), k("f2","F2",120), k("f3","F3",99), k("f4","F4",118)])
        r += row(0, x0: 6.5, [k("f5","F5",96), k("f6","F6",97), k("f7","F7",98), k("f8","F8",100)])
        r += row(0, x0: 11, [k("f9","F9",101), k("f10","F10",109), k("f11","F11",103), k("f12","F12",111)])
        r += row(1.5, [k("grave_accent_and_tilde","`  ~",50), k("1","1",18), k("2","2",19), k("3","3",20), k("4","4",21),
                       k("5","5",23), k("6","6",22), k("7","7",26), k("8","8",28), k("9","9",25), k("0","0",29),
                       k("hyphen","-",27), k("equal_sign","=",24), k("delete_or_backspace","⌫",51,2)])
        r += row(2.5, [k("tab","tab",48,1.5), k("q","Q",12), k("w","W",13), k("e","E",14), k("r","R",15), k("t","T",17),
                       k("y","Y",16), k("u","U",32), k("i","I",34), k("o","O",31), k("p","P",35),
                       k("open_bracket","[",33), k("close_bracket","]",30), k("backslash","\\",42,1.5)])
        r += row(3.5, [k("caps_lock","caps",57,1.75), k("a","A",0), k("s","S",1), k("d","D",2), k("f","F",3), k("g","G",5),
                       k("h","H",4), k("j","J",38), k("k","K",40), k("l","L",37), k("semicolon",";",41),
                       k("quote","'",39), k("return_or_enter","return",36,2.25)])
        r += row(4.5, [k("left_shift","shift",56,2.25), k("z","Z",6), k("x","X",7), k("c","C",8), k("v","V",9), k("b","B",11),
                       k("n","N",45), k("m","M",46), k("comma",",",43), k("period",".",47), k("slash","/",44),
                       k("right_shift","shift",60,2.75)])
        r += row(5.5, [k("fn","fn",63), k("left_control","ctrl",59), k("left_option","opt",58), k("left_command","cmd",55,1.25),
                       k("spacebar","space",49,5), k("right_command","cmd",54,1.25), k("right_option","opt",61),
                       k("left_arrow","←",123), k("up_arrow","↑",126), k("down_arrow","↓",125), k("right_arrow","→",124)]
            .map { $0 }) // arrows share the bottom row
        return r
    }()

    static let navCluster: [KeyDef] = {
        var r: [KeyDef] = []
        r += row(0, x0: 15.5, [k("f13","F13",105), k("f14","F14",107), k("f15","F15",113)])
        r += row(1.5, x0: 15.5, [k("home","home",115), k("page_up","pg↑",116)])
        r += row(2.5, x0: 15.5, [k("delete_forward","del⌦",117), k("end","end",119), k("page_down","pg↓",121)])
        return r
    }()

    static let numpad: [KeyDef] = {
        var r: [KeyDef] = []
        let x0 = 19.0
        r += row(0, x0: x0, [k("f16","F16",106), k("f17","F17",64), k("f18","F18",79), k("f19","F19",80)])
        r += row(1.5, x0: x0, [k("keypad_num_lock","clear",71), k("keypad_equal_sign","=",81), k("keypad_slash","/",75), k("keypad_asterisk","*",67)])
        r += row(2.5, x0: x0, [k("keypad_7","7",89), k("keypad_8","8",91), k("keypad_9","9",92), k("keypad_hyphen","−",78)])
        r += row(3.5, x0: x0, [k("keypad_4","4",86), k("keypad_5","5",87), k("keypad_6","6",88), k("keypad_plus","+",69)])
        r += row(4.5, x0: x0, [k("keypad_1","1",83), k("keypad_2","2",84), k("keypad_3","3",85)])
        r += row(5.5, x0: x0, [k("keypad_0","0",82,2), k("keypad_period",".",65)])
        r.append(KeyDef(code: "keypad_enter", label: "enter", mac: 76, x: x0 + 3, y: 4.5, w: 1, h: 2))
        return r
    }()

    public static let totalWidth: Double = 23
    public static let totalHeight: Double = 6.5
}
