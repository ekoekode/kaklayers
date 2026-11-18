import Foundation
import KaKLayersCore

struct CompilerTests {
    func manips(_ p: Project, rule: Int = 0) -> [JSON] {
        KarabinerCompiler.rules(for: p)[rule]["manipulators"] as! [JSON]
    }
    func dict(_ v: Any?) -> NSDictionary { v as! NSDictionary }

    /// `~` tapped = `~`, held = Nav layer; layer binds h -> left_arrow.
    func testSuperKeyTapHoldLayer() {
        let nav = Layer(id: "nav", name: "Nav", colorHex: "#4F8EF7",
                        triggerKeys: ["grave_accent_and_tilde"],
                        tapAction: [.key(KeyCombo(key: "grave_accent_and_tilde", modifiers: ["shift"]))])
        let p = Project(layers: [nav], bindings: [
            KeyBinding(layerId: "nav", fromKeys: ["h"], onPress: [.key(KeyCombo(key: "left_arrow"))])])
        let m = manips(p)
        expect((m.count) == (2))
        // layer binding first, trigger last
        expect(((m[0]["conditions"] as! [JSON])[0]["name"] as? String) == "layer_nav")
        let trig = m[1]
        expect(((trig["to"] as! [JSON])[0]["set_variable"] as! NSDictionary) == (["name": "layer_nav", "value": 1, "key_up_value": 0] as NSDictionary))
        expect(((trig["to_if_alone"] as! [JSON])[0]["key_code"] as? String) == ("grave_accent_and_tilde"))
        expect(((trig["parameters"] as! JSON)["basic.to_if_alone_timeout_milliseconds"] as? Int) == (200))
    }

    func testHyperChordTrigger() {
        let hyper = Layer(id: "hyper", name: "Hyper", colorHex: "#E5484D",
                          triggerKeys: ["left_command", "left_control", "left_shift"])
        let t = manips(Project(layers: [hyper]))[0]
        let from = t["from"] as! JSON
        expect(((from["simultaneous"] as! [JSON]).count) == (3))
    }

    func testToggleLayerHasOffManipulatorFirst() {
        let l = Layer(id: "t", name: "T", colorHex: "#000", mode: .toggle, triggerKeys: ["caps_lock"])
        let m = manips(Project(layers: [l]))
        expect((m.count) == (2))
        expect((((m[0]["to"] as! [JSON])[0]["set_variable"] as! JSON)["value"] as? Int) == (0))
        expect((((m[1]["to"] as! [JSON])[0]["set_variable"] as! JSON)["value"] as? Int) == (1))
    }

    func testDelayAndShellChain() {
        let b = KeyBinding(fromKeys: ["f12"], onPress: [
            .key(KeyCombo(key: "a")), .delay(300), .shell("say 'hi'"), .openApp("com.apple.Terminal")])
        let to = manips(Project(bindings: [b]))[0]["to"] as! [JSON]
        expect((to[1]["hold_down_milliseconds"] as? Int) == (300))
        expect((to[2]["shell_command"] as? String) == ("say 'hi'"))
        expect((to[3]["shell_command"] as? String) == ("open -b 'com.apple.Terminal'"))
    }

    func testHoldReleaseAndAppCondition() {
        let b = KeyBinding(fromKeys: ["a"], onTap: [.key(KeyCombo(key: "a"))], onHold: [.key(KeyCombo(key: "b"))],
                        onRelease: [.shell("true")], holdThresholdMs: 400,
                        apps: ["com.apple.Terminal"], appsExclude: true)
        let m = manips(Project(bindings: [b]))[0]
        expect((m["to_if_alone"]) != nil)
        expect((m["to_if_held_down"]) != nil)
        expect((m["to_after_key_up"]) != nil)
        expect(((m["parameters"] as! JSON)["basic.to_if_held_down_threshold_milliseconds"] as? Int) == (400))
        let c = (m["conditions"] as! [JSON])[0]
        expect((c["type"] as? String) == ("frontmost_application_unless"))
        expect(((c["bundle_identifiers"] as! [String])[0]) == ("^com\\.apple\\.Terminal$"))
    }

    func testDoubleTapProducesTwoManipulators() {
        let b = KeyBinding(fromKeys: ["left_shift"], onTap: [.key(KeyCombo(key: "a"))], onDoubleTap: [.key(KeyCombo(key: "caps_lock"))])
        let m = manips(Project(bindings: [b]))
        expect((m.count) == (2))
        expect((m[1]["to_delayed_action"]) != nil)
        expect(((m[0]["conditions"] as! [JSON])[0]["type"] as? String) == ("variable_if"))
    }

    func testKeyCodesAreUnique() {
        expect((Set(Keycodes.all.map(\.code)).count) == (Keycodes.all.count))
        expect((Set(Keycodes.all.map(\.mac)).count) == (Keycodes.all.count))
    }

    func testApplyMergesAndKeepsUserRules() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("layers-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let user: JSON = ["global": ["check_for_updates_on_startup": true],
                          "profiles": [["name": "P", "selected": true, "virtual_hid_keyboard": ["country_code": 0],
                                        "complex_modifications": ["rules": [["description": "mine", "manipulators": []], ["description": "[Layers] old", "manipulators": []]]]]]]
        try JSONSerialization.data(withJSONObject: user).write(to: dir.appendingPathComponent("karabiner.json"))
        let p = Project(bindings: [KeyBinding(fromKeys: ["a"], onPress: [.key(KeyCombo(key: "b"))])])
        let w = ConfigWriter(dir: dir)
        _ = try w.apply(p)
        let r = try w.apply(p) // idempotent
        expect((r.backupPath) != nil)
        let out = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("karabiner.json"))) as! JSON
        let profile = (out["profiles"] as! [JSON])[0]
        expect((profile["virtual_hid_keyboard"]) != nil)
        expect((out["global"]) != nil)
        let rules = (profile["complex_modifications"] as! JSON)["rules"] as! [JSON]
        expect((rules.count) == (2))   // old "[Layers] " rule replaced, user rule kept
        expect(!rules.contains { ($0["description"] as? String) == "[Layers] old" })
        expect((rules.last?["description"] as? String) == ("mine"))
        expect((try w.restoreLatestBackup()) != nil)
    }
}


func testCustomConfigFileAndProjectRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kak-custom-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("dotfiles/karabiner.json")            // does not exist yet
    let p = Project(layers: [Layer(id: "x", name: "X", colorHex: "#4F8EF7", triggerKeys: ["caps_lock"])],
                    bindings: [KeyBinding(layerId: "x", fromKeys: ["h"], onPress: [.key(KeyCombo(key: "left_arrow"))])])
    let w = ConfigWriter(dir: dir, configFile: file)
    let first = try w.apply(p)
    expect(first.backupPath == nil && first.exportPath == nil && first.configPath == file.path)
    expect(FileManager.default.fileExists(atPath: file.path))
    expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets").path))   // no assets copy for custom files
    let second = try w.apply(p)
    expect(second.backupPath?.hasPrefix(file.deletingLastPathComponent().path) == true)         // backup sits beside the file
    let out = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! JSON
    let rules = (((out["profiles"] as! [JSON])[0]["complex_modifications"] as! JSON)["rules"] as! [JSON])
    expect(rules.count == KarabinerCompiler.rules(for: p).count)
    // project files survive an encode/decode round trip
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    expect(try JSONDecoder().decode(Project.self, from: enc.encode(p)) == p)
}

func testCopyPasteKeySettings() {
    var p = Project(layers: [Layer(id: "nav", name: "Nav", colorHex: "#4F8EF7", triggerKeys: ["caps_lock"])])
    let plain = KeyBinding(layerId: "nav", fromKeys: ["h"], onPress: [.key(KeyCombo(key: "left_arrow")), .delay(50)], onHold: [.shell("say hi")],
                           holdThresholdMs: 350, apps: ["com.apple.Safari"], appsExclude: true, devices: [DeviceID(vendorId: 1, productId: 2)], note: "n")
    let variant = KeyBinding(layerId: "nav", fromKeys: ["h"], fromModifiers: ["command"], onPress: [.key(KeyCombo(key: "home"))])
    let chord = KeyBinding(layerId: "nav", fromKeys: ["h", "j"], onPress: [.key(KeyCombo(key: "escape"))])
    let old = KeyBinding(layerId: "nav", fromKeys: ["l"], onPress: [.key(KeyCombo(key: "right_arrow"))])
    p.bindings = [plain, variant, chord, old]

    let copied = p.keySettings(layer: "nav", key: "h")
    expect(copied.count == 2)                                   // plain + ⌘ variant, not the chord
    p.paste(copied, layer: "nav", key: "l")
    let l = p.keySettings(layer: "nav", key: "l")
    expect(l.count == 2 && !l.contains { $0.id == plain.id || $0.id == variant.id })   // fresh ids
    let lp = l.first { $0.fromModifiers.isEmpty }!
    expect(lp.onPress == plain.onPress && lp.onHold == plain.onHold && lp.holdThresholdMs == 350)
    expect(lp.apps == ["com.apple.Safari"] && lp.appsExclude && lp.devices == plain.devices && lp.note == "n")
    expect(!l.contains { $0.onPress == old.onPress })           // the old L binding was replaced
    expect(p.keySettings(layer: "nav", key: "h").count == 2)    // source untouched
    expect(p.bindings.contains { $0.fromKeys == ["h", "j"] })   // chords left alone
    p.paste(copied, layer: nil, key: "l")                       // can paste into another layer
    expect(p.keySettings(layer: nil, key: "l").count == 2)
}

func testTapKeepsOriginalFunction() {
    func manips(_ p: Project, layer: String? = nil) -> [JSON] {
        KarabinerCompiler.rules(for: p).flatMap { ($0["manipulators"] as? [JSON]) ?? [] }
    }
    func toAlone(_ m: JSON) -> [JSON]? { m["to_if_alone"] as? [JSON] }

    // A momentary layer on ' with no tap action: tapping it types ' (and Shift stays held, so Shift+' types the shifted character).
    let quote = Layer(id: "q", name: "Quote", colorHex: "#4F8EF7", triggerKeys: ["quote"])
    let trig = manips(Project(layers: [quote])).last!
    expect(toAlone(trig)?.first?["key_code"] as? String == "quote")
    expect(((trig["from"] as! JSON)["modifiers"] as! JSON)["optional"] as? [String] == ["any"])      // Shift+' still triggers the rule
    expect((trig["parameters"] as? JSON)?["basic.to_if_alone_timeout_milliseconds"] as? Int == 200)

    // An explicit tap action wins over the default.
    var custom = quote; custom.tapAction = [.key(KeyCombo(key: "escape"))]
    expect(toAlone(manips(Project(layers: [custom])).last!)?.first?["key_code"] as? String == "escape")
    // Modifier triggers and toggle layers get no pass-through.
    let mod = Layer(id: "m", name: "M", colorHex: "#E5484D", triggerKeys: ["right_option"])
    expect(toAlone(manips(Project(layers: [mod])).last!) == nil)
    var tog = quote; tog.mode = .toggle
    expect(manips(Project(layers: [tog])).allSatisfy { toAlone($0) == nil })
    // Hyper (several keys) gets none either.
    let hyper = Layer(id: "h", name: "H", colorHex: "#E5484D", triggerKeys: ["left_command", "left_control"])
    expect(toAlone(manips(Project(layers: [hyper])).last!) == nil)

    // Hold-only binding: a tap sends the key itself, with the binding's required modifiers.
    let holdOnly = KeyBinding(fromKeys: ["a"], onHold: [.key(KeyCombo(key: "b"))])
    let h = manips(Project(bindings: [holdOnly]))[0]
    expect(toAlone(h)?.first?["key_code"] as? String == "a" && h["to"] == nil && h["to_if_held_down"] != nil)
    let holdMod = KeyBinding(fromKeys: ["a"], fromModifiers: ["command"], onHold: [.key(KeyCombo(key: "b"))])
    expect((toAlone(manips(Project(bindings: [holdMod]))[0])?.first?["modifiers"] as? [String]) == ["command"])
    // Tap defined, or press defined: nothing is added.
    let tapSet = KeyBinding(fromKeys: ["a"], onTap: [.key(KeyCombo(key: "c"))], onHold: [.key(KeyCombo(key: "b"))])
    expect(toAlone(manips(Project(bindings: [tapSet]))[0])?.first?["key_code"] as? String == "c")
    let pressSet = KeyBinding(fromKeys: ["a"], onPress: [.key(KeyCombo(key: "x"))], onHold: [.key(KeyCombo(key: "b"))])
    expect(toAlone(manips(Project(bindings: [pressSet]))[0]) == nil)
    // Release-only: the press passes through.
    let rel = manips(Project(bindings: [KeyBinding(fromKeys: ["a"], onRelease: [.shell("true")])]))[0]
    expect((rel["to"] as? [JSON])?.first?["key_code"] as? String == "a" && rel["to_after_key_up"] != nil)
    // Double-tap only: a single tap sends the key after the window.
    let dbl = manips(Project(bindings: [KeyBinding(fromKeys: ["a"], onDoubleTap: [.key(KeyCombo(key: "z"))])]))
    let invoked = (((dbl.last!["to_delayed_action"] as! JSON)["to_if_invoked"]) as! [JSON])
    expect(invoked.contains { $0["key_code"] as? String == "a" })
    // Chords have no single original key.
    let chord = KeyBinding(fromKeys: ["a", "s"], onHold: [.key(KeyCombo(key: "b"))])
    expect(toAlone(manips(Project(bindings: [chord]))[0]) == nil)
}

func testTopRowMatchesFunctionAndMediaKeys() {
    func froms(_ p: Project) -> [JSON] {
        KarabinerCompiler.rules(for: p).flatMap { ($0["manipulators"] as? [JSON]) ?? [] }.compactMap { $0["from"] as? JSON }
    }
    func has(_ fs: [JSON], _ field: String, _ code: String) -> Bool { fs.contains { ($0[field] as? String) == code } }

    // A binding on F1 also fires on the brightness key (all the families a keyboard might use).
    let f1 = froms(Project(bindings: [KeyBinding(fromKeys: ["f1"], onPress: [.key(KeyCombo(key: "a"))])]))
    expect(has(f1, "key_code", "f1") && has(f1, "consumer_key_code", "display_brightness_decrement"))
    expect(has(f1, "apple_vendor_top_case_key_code", "brightness_down") && has(f1, "apple_vendor_keyboard_key_code", "brightness_down"))
    // Mission Control is a vendor key; F3 covers it.
    let f3 = froms(Project(bindings: [KeyBinding(fromKeys: ["f3"], onPress: [.key(KeyCombo(key: "a"))])]))
    expect(has(f3, "apple_vendor_keyboard_key_code", "mission_control"))
    // A binding made on the media key (Media row) also fires on plain F10.
    let mute = froms(Project(bindings: [KeyBinding(fromKeys: ["mute"], onPress: [.key(KeyCombo(key: "a"))])]))
    expect(has(mute, "consumer_key_code", "mute") && has(mute, "key_code", "f10"))
    // Layer triggers and every role keep their modifiers on each variant.
    let withMods = froms(Project(bindings: [KeyBinding(fromKeys: ["f8"], fromModifiers: ["shift"], onPress: [.key(KeyCombo(key: "a"))])]))
    expect(withMods.count == 2 && withMods.allSatisfy { (($0["modifiers"] as? JSON)?["mandatory"] as? [String]) == ["shift"] })
    let trig = froms(Project(layers: [Layer(id: "f", name: "F", colorHex: "#4F8EF7", triggerKeys: ["f12"])]))
    expect(has(trig, "consumer_key_code", "volume_increment") && has(trig, "key_code", "f12"))
    // Ordinary keys and chords are not expanded.
    expect(froms(Project(bindings: [KeyBinding(fromKeys: ["a"], onPress: [.key(KeyCombo(key: "b"))])])).count == 1)
    expect(froms(Project(bindings: [KeyBinding(fromKeys: ["f1", "f2"], onPress: [.key(KeyCombo(key: "b"))])])).count == 1)
    // Every slot key the Media row draws is part of a slot.
    for m in Keycodes.mediaRow { expect(!Keycodes.aliases(of: m.code).isEmpty) }
}

func testRemoveSeveralLayers() {
    func layer(_ id: String) -> Layer { Layer(id: id, name: id, colorHex: "#4F8EF7", triggerKeys: [id]) }
    func bind(_ l: String?, _ k: String) -> KeyBinding { KeyBinding(layerId: l, fromKeys: [k], onPress: [.key(KeyCombo(key: "b"))]) }
    var p = Project(layers: [layer("a"), layer("b"), layer("c"), layer("d")],
                    bindings: [bind("a", "h"), bind("b", "h"), bind("c", "h"), bind("d", "h"), bind(nil, "h")])
    p.removeLayers(["b", "c", "zzz"])
    expect(p.layers.map(\.id) == ["a", "d"])
    expect(Set(p.bindings.map { $0.layerId ?? "base" }) == ["a", "d", "base"] && p.bindings.count == 3)
    p.removeLayers([])
    expect(p.layers.count == 2)
}

func testMouseButtons() {
    func manips(_ p: Project) -> [JSON] { KarabinerCompiler.rules(for: p).flatMap { ($0["manipulators"] as? [JSON]) ?? [] } }
    // Bindings match and send mouse buttons in the field Karabiner expects.
    let b = KeyBinding(fromKeys: ["button4"], onPress: [.key(KeyCombo(key: "open_bracket", modifiers: ["command"]))])
    let m = manips(Project(bindings: [b]))[0]
    expect((m["from"] as! JSON)["pointing_button"] as? String == "button4")
    let click = KeyBinding(fromKeys: ["a"], onPress: [.mouse("button2")])
    expect((manips(Project(bindings: [click]))[0]["to"] as! [JSON])[0]["pointing_button"] as? String == "button2")
    // A layer on the middle button: tapping it still middle-clicks.
    let layer = Layer(id: "m", name: "M", colorHex: "#4F8EF7", triggerKeys: ["button3"])
    let trig = manips(Project(layers: [layer])).last!
    expect((trig["from"] as! JSON)["pointing_button"] as? String == "button3")
    expect(((trig["to_if_alone"] as! [JSON])[0])["pointing_button"] as? String == "button3")
    // Hold-only mouse binding keeps its click on tap.
    let hold = KeyBinding(fromKeys: ["button5"], onHold: [.key(KeyCombo(key: "a"))])
    expect(((manips(Project(bindings: [hold]))[0]["to_if_alone"] as! [JSON])[0])["pointing_button"] as? String == "button5")
    // Left/right as a layer trigger is flagged; extra buttons are not.
    let left = Project(layers: [Layer(id: "l", name: "L", colorHex: "#4F8EF7", triggerKeys: ["button1"])])
    expect(ConflictChecker.check(left).contains { $0.severity == .warning })
    expect(!ConflictChecker.check(Project(layers: [layer])).contains { $0.severity == .warning })
    expect(ConflictChecker.check(Project(bindings: [b])).contains { $0.message.contains("EventViewer") })
    expect(!ConflictChecker.check(Project(bindings: [click])).contains { $0.message.contains("EventViewer") })
    // The deck draws all five buttons and they are not keyboard keys.
    for kind in Keycodes.LayoutKind.allCases {
        let codes = Set(Keycodes.layout(kind).map(\.code))
        expect(Keycodes.mouseButtons.isSubset(of: codes))
    }
    expect(Keycodes.byMac.values.allSatisfy { !Keycodes.isMouseButton($0.code) })
}

func testPresetsCompileAndAreClean() {
    for preset in Presets.all {
        var p = Project(); p.add(preset)
        let rules = KarabinerCompiler.rules(for: p)
        expect(!rules.isEmpty)
        expect((try? KarabinerCompiler.jsonString(["rules": rules])) != nil)
        expect(ConflictChecker.check(p).allSatisfy { $0.severity == .info })
    }
}
func testConflictShadowedTrigger() {
    let l = Layer(id: "x", name: "X", colorHex: "#000", triggerKeys: ["tab"], tapAction: [.key(KeyCombo(key: "tab"))])
    let p = Project(layers: [l], bindings: [KeyBinding(fromKeys: ["tab"], onPress: [.key(KeyCombo(key: "a"))])])
    expect(ConflictChecker.check(p).contains { $0.severity == .warning })
}
func testImporterSkipsComplex() throws {
    let json = #"{"rules":[{"description":"r","manipulators":[{"type":"basic","from":{"key_code":"a"},"to":[{"key_code":"b"}]},{"type":"basic","from":{"key_code":"c"},"to_if_alone":[{"key_code":"d"}],"to":[{"key_code":"e"}]}]}]}"#
    let r = try Importer.importSimple(data: Data(json.utf8))
    expect(r.bindings.count == 1); expect(r.skipped == 1)
}

func testSimulator() {
    let nav = Layer(id: "nav", name: "Nav", colorHex: "#000", triggerKeys: ["grave_accent_and_tilde"])
    let p = Project(layers: [nav], bindings: [KeyBinding(layerId: "nav", fromKeys: ["h"], onPress: [.key(KeyCombo(key: "left_arrow"))]),
                                              KeyBinding(fromKeys: ["h"], onPress: [.key(KeyCombo(key: "x"))])])
    expect(Simulator.resolve(p, held: ["nav"], key: "h").layer?.id == "nav")
    expect(Simulator.resolve(p, held: [], key: "h").layer == nil && Simulator.resolve(p, held: [], key: "h").binding != nil)
    expect(Simulator.resolve(p, held: [], key: "grave_accent_and_tilde").layer?.id == "nav")
    expect(Simulator.resolve(p, held: [], key: "q").binding == nil)
}

func testInputModifiers() {
    let b = KeyBinding(fromKeys: ["h"], fromModifiers: ["command"], onPress: [.key(KeyCombo(key: "left_arrow"))])
    let m = (KarabinerCompiler.rules(for: Project(bindings: [b]))[0]["manipulators"] as! [JSON])[0]
    let mods = (m["from"] as! JSON)["modifiers"] as! JSON
    expect((mods["mandatory"] as! [String]) == ["command"]); expect((mods["optional"] as! [String]) == ["any"])
}

func testVariantsOrderedAndResolved() {
    let plain = KeyBinding(fromKeys: ["h"], onPress: [.key(KeyCombo(key: "left_arrow"))])
    let cmd = KeyBinding(fromKeys: ["h"], fromModifiers: ["command"], onPress: [.key(KeyCombo(key: "home"))])
    let p = Project(bindings: [plain, cmd])          // plain defined first on purpose
    let ms = KarabinerCompiler.rules(for: p)[0]["manipulators"] as! [JSON]
    expect(((ms[0]["from"] as! JSON)["modifiers"] as! JSON)["mandatory"] != nil)   // cmd variant must come first
    expect(Simulator.resolve(p, held: [], key: "h", mods: ["command"]).binding?.fromModifiers == ["command"])
    expect(Simulator.resolve(p, held: [], key: "h").binding?.fromModifiers.isEmpty == true)
    expect(p.binding(layer: nil, key: "h", mods: ["command"]) != nil)
}

func testJISHasItsOwnKeys() {
    let codes = Set(Keycodes.layout(.jis).map(\.code))
    for c in ["international3", "international1", "japanese_eisuu", "japanese_kana", "non_us_pound"] { expect(codes.contains(c)); expect(Keycodes.byCode[c] != nil) }
    expect(!codes.contains("grave_accent_and_tilde") && !codes.contains("backslash"))
}
func testExtendedKeysAndMediaRow() {
    for kind in Keycodes.LayoutKind.allCases {
        let codes = Set(Keycodes.layout(kind).map(\.code))
        for n in 13...19 { expect(codes.contains("f\(n)")) }
        let media = Keycodes.layout(kind, mediaRow: true)
        expect(media.count == Keycodes.layout(kind).count)
        expect(media.contains { $0.code == "mission_control" } && !media.contains { $0.code == "f3" })
        expect(Set(media.map(\.code)).count == media.count)
    }
    // each media key lands in the JSON field Karabiner expects
    expect(Keycodes.codeField("mission_control") == "apple_vendor_keyboard_key_code")
    expect(Keycodes.codeField("illumination_up") == "apple_vendor_top_case_key_code")
    expect(Keycodes.codeField("play_or_pause") == "consumer_key_code" && Keycodes.codeField("f13") == "key_code")
    let b = KeyBinding(fromKeys: ["mission_control"], onPress: [.consumer("launchpad")])
    let m = (KarabinerCompiler.rules(for: Project(bindings: [b]))[0]["manipulators"] as! [JSON])[0]
    expect(((m["from"] as! JSON)["apple_vendor_keyboard_key_code"] as? String) == "mission_control")
    expect(((m["to"] as! [JSON])[0]["apple_vendor_keyboard_key_code"] as? String) == "launchpad")
}
func testLayoutsDoNotOverlap() {
    for kind in Keycodes.LayoutKind.allCases {
        let keys = Keycodes.layout(kind)
        expect(Set(keys.map(\.code)).count == keys.count)
        for (i, a) in keys.enumerated() { for b in keys[(i+1)...] {
            let overlap = a.x < b.x + b.w - 0.01 && b.x < a.x + a.w - 0.01 && a.y < b.y + b.h - 0.01 && b.y < a.y + a.h - 0.01
            if overlap { print("  overlap \(kind): \(a.code) / \(b.code)"); expect(false) }
        } }
        expect(keys.allSatisfy { $0.x + $0.w <= Keycodes.totalWidth + 0.01 && $0.y + $0.h <= Keycodes.totalHeight + 0.01 })
    }
}

func testDeviceCondition() {
    let b = KeyBinding(fromKeys: ["a"], onPress: [.key(KeyCombo(key: "b"))], devices: [DeviceID(vendorId: 1452, productId: 834)])
    let c = ((KarabinerCompiler.rules(for: Project(bindings: [b]))[0]["manipulators"] as! [JSON])[0]["conditions"] as! [JSON])[0]
    expect(c["type"] as? String == "device_if")
    let id = (c["identifiers"] as! [JSON])[0]
    expect(id["vendor_id"] as? Int == 1452 && id["product_id"] as? Int == 834)
}

func testDuplicateBindingWarning() {
    let a = KeyBinding(fromKeys: ["a"], onPress: [.key(KeyCombo(key: "b"))])
    let c = KeyBinding(fromKeys: ["a"], onPress: [.key(KeyCombo(key: "c"))])
    expect(ConflictChecker.check(Project(bindings: [a, c])).contains { $0.severity == .warning })
    expect(ConflictChecker.check(Project(bindings: [a])).isEmpty)
}
func testChordsPrecedeSingleKeys() {
    let single = KeyBinding(fromKeys: ["j"], onPress: [.key(KeyCombo(key: "down_arrow"))])
    let chord = KeyBinding(fromKeys: ["j", "k"], onPress: [.key(KeyCombo(key: "escape"))])
    let p = Project(bindings: [single, chord])   // single defined first on purpose
    let ms = KarabinerCompiler.rules(for: p)[0]["manipulators"] as! [JSON]
    expect((ms[0]["from"] as! JSON)["simultaneous"] != nil)
    expect(((ms[0]["from"] as! JSON)["simultaneous"] as! [JSON]).count == 2)
    expect((ms[0]["parameters"] as! JSON)["basic.simultaneous_threshold_milliseconds"] as? Int == 100)
    expect((ms[1]["from"] as! JSON)["key_code"] as? String == "j")
    expect(p.chords(layer: nil, containing: "k").count == 1)
    expect(p.binding(layer: nil, keys: ["j", "k"], mods: []) != nil)
    expect(ConflictChecker.check(p).allSatisfy { $0.severity == .info })
}
func testLayerReorder() {
    func L(_ id: String) -> Layer { Layer(id: id, name: id, colorHex: "#000", triggerKeys: [id]) }
    var p = Project(layers: [L("a"), L("b"), L("c")])
    p.moveLayer("c", before: "a"); expect(p.layers.map(\.id) == ["c", "a", "b"])
    p.moveLayer("c", before: nil); expect(p.layers.map(\.id) == ["a", "b", "c"])
    p.moveLayer("a", before: "a"); expect(p.layers.map(\.id) == ["a", "b", "c"])
    p.shiftLayer("a", by: -1); expect(p.layers.map(\.id) == ["a", "b", "c"])
    p.shiftLayer("a", by: 1); expect(p.layers.map(\.id) == ["b", "a", "c"])
    // order is rule order (priority)
    let names = KarabinerCompiler.rules(for: p).map { $0["description"] as! String }
    expect(names == ["[KaKLayers] b", "[KaKLayers] a", "[KaKLayers] c"])
}
func testLegendsFitAtMinimumUnit() {
    for kind in Keycodes.LayoutKind.allCases {
        for k in Keycodes.layout(kind) {
            let w = TextFit.width(k.label, size: Metrics.legendFont, weight: 0.23)
            let budget = Metrics.legendBudget(unit: Metrics.minKeyUnit, widthUnits: k.w)
            if w > budget { print("  legend too wide [\(kind)] \(k.code) '\(k.label)' \(w) > \(budget)"); expect(false) }
            expect(!k.label.contains("…") && !k.label.contains("..."))
        }
    }
}

func testCapTextFitsAndNeverEllipsizes() {
    let hyperF10 = KeyCombo(key: "f10", modifiers: ["command", "control", "option", "shift"])
    let threeMods = KeyCombo(key: "f10", modifiers: ["command", "option", "shift"])
    let samples: [[Action]] = [
        [.key(KeyCombo(key: "a"))], [.key(hyperF10)], [.key(threeMods)],
        [.key(KeyCombo(key: "left_arrow")), .delay(300), .shell("a very long command --with --many --flags"), .openApp("com.apple.Terminal")],
        [.delay(12000)], [.consumer("display_brightness_increment")], [.openURL("https://example.com/a/very/long/path")],
        [.key(KeyCombo(key: "a")), .key(KeyCombo(key: "b")), .key(KeyCombo(key: "c")), .key(KeyCombo(key: "d")), .key(KeyCombo(key: "e")), .key(KeyCombo(key: "f"))],
        [.inputSource("com.apple.keylayout.US"), .stickyModifier("left_shift"), .mouse("button5"), .setVariable(name: "x", value: 1)],
    ]
    for unit in [Metrics.minKeyUnit, 60, Metrics.maxKeyUnit] {
        let budget = Metrics.rowBudget(unit: unit)
        for acts in samples {
            let b = KeyBinding(fromKeys: ["a"], onPress: acts, onTap: acts, onHold: acts, onRelease: acts, onDoubleTap: acts)
            let c = KeyGlyphs.content(for: b, budget: budget)
            expect(c.rows.count == 2 && c.moreRoles == 3)
            for r in c.rows {
                let w = TextFit.width(r.text, size: Metrics.rowFont)
                if w > budget { print("  row too wide at unit \(unit): '\(r.text)' \(w) > \(budget)"); expect(false) }
                expect(!r.text.isEmpty && !r.text.contains("…") && !r.text.contains("..."))
            }
        }
    }
}
if CommandLine.arguments.contains("--glyphs") {
    let u = Metrics.minKeyUnit; let bud = Metrics.rowBudget(unit: u)
    print("budget at unit \(u): \(bud)pt")
    let hyper = KeyCombo(key: "f10", modifiers: ["command", "control", "option", "shift"])
    for acts: [Action] in [[.key(KeyCombo(key: "left_arrow"))], [.key(hyper)], [.key(KeyCombo(key: "h", modifiers: ["command", "shift"]))],
        [.key(KeyCombo(key: "a")), .delay(300), .shell("x"), .openApp("com.apple.Terminal")], [.delay(12000)], [.key(KeyCombo(key: "a")), .key(KeyCombo(key: "b")), .key(KeyCombo(key: "c")), .key(KeyCombo(key: "d"))]] {
        let t = KeyGlyphs.row(acts, budget: bud); print("'\(t)'  \(TextFit.width(t, size: Metrics.rowFont))pt")
    }
    print("widest legend:", Keycodes.layout(.ansi).map { ($0.label, TextFit.width($0.label, size: Metrics.legendFont, weight: 0.23) / Metrics.legendBudget(unit: u, widthUnits: $0.w)) }.max { $0.1 < $1.1 }!)
    exit(0)
}
if CommandLine.arguments.contains("--apply-starter") {
    let nav = Layer(id: "nav", name: "Nav", colorHex: "#4F8EF7", triggerKeys: ["grave_accent_and_tilde"],
                    tapAction: [.key(KeyCombo(key: "grave_accent_and_tilde", modifiers: ["shift"]))])
    func a(_ f: String, _ t: String) -> KeyBinding { KeyBinding(layerId: "nav", fromKeys: [f], onPress: [.key(KeyCombo(key: t))]) }
    let p = Project(layers: [nav], bindings: [a("h", "left_arrow"), a("j", "down_arrow"), a("k", "up_arrow"), a("l", "right_arrow")])
    let r = try ConfigWriter().apply(p)
    print("applied: \(r.ruleCount) rule(s) -> \(r.configPath); backup: \(r.backupPath ?? "none (no previous file)")")
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--emit"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var projects: [(String, Project)] = Presets.all.map { pr in var p = Project(); p.add(pr); return (pr.name.replacingOccurrences(of: " ", with: "_").filter { $0.isLetter || $0.isNumber || $0 == "_" }, p) }
    // kitchen sink: every feature at once
    let nav = Layer(id: "nav", name: "Nav", colorHex: "#4F8EF7", triggerKeys: ["grave_accent_and_tilde"], tapAction: [.key(KeyCombo(key: "grave_accent_and_tilde", modifiers: ["shift"]))])
    let hyper = Layer(id: "hyper", name: "Hyper", colorHex: "#E5484D", triggerKeys: ["left_command", "left_control", "left_shift"])
    let tog = Layer(id: "tog", name: "Toggle", colorHex: "#30A46C", mode: .toggle, triggerKeys: ["f19"])
    let sink = Project(name: "Sink", layers: [nav, hyper, tog], bindings: [
        KeyBinding(layerId: "nav", fromKeys: ["h"], onPress: [.key(KeyCombo(key: "left_arrow"))]),
        KeyBinding(layerId: "nav", fromKeys: ["h"], fromModifiers: ["command"], onPress: [.key(KeyCombo(key: "home"))]),
        KeyBinding(layerId: "hyper", fromKeys: ["t"], onPress: [.openApp("com.apple.Terminal"), .delay(300), .key(KeyCombo(key: "n", modifiers: ["command"]))]),
        KeyBinding(layerId: "tog", fromKeys: ["a"], onPress: [.shell("say 'it works'"), .consumer("mute"), .stickyModifier("left_shift")]),
        KeyBinding(fromKeys: ["left_shift"], onTap: [.key(KeyCombo(key: "a"))], onDoubleTap: [.key(KeyCombo(key: "caps_lock"))]),
        KeyBinding(fromKeys: ["f"], onTap: [.key(KeyCombo(key: "f"))], onHold: [.key(KeyCombo(key: "g"))], onRelease: [.openURL("https://example.com")],
                   apps: ["com.apple.Terminal"], appsExclude: true, devices: [DeviceID(vendorId: 1452, productId: 834)]),
        KeyBinding(fromKeys: ["j", "k"], onPress: [.key(KeyCombo(key: "escape"))], onTap: [.key(KeyCombo(key: "escape"))]),
        KeyBinding(fromKeys: ["d"], onPress: [.mouse("button1"), .inputSource("com.apple.keylayout.US")]),
    ])
    projects.append(("KitchenSink", sink))
    for (name, p) in projects { try KarabinerCompiler.jsonString(KarabinerCompiler.compile(p)).write(to: dir.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8) }
    print("emitted \(projects.count) files"); exit(0)
}
var failures = 0
func expect(_ ok: Bool, _ line: Int = #line) { if !ok { failures += 1; print("  FAIL at test line \(line)") } }
let t = CompilerTests()
let cases: [(String, () throws -> Void)] = [
  ("superKeyTapHoldLayer", t.testSuperKeyTapHoldLayer), ("hyperChordTrigger", t.testHyperChordTrigger),
  ("toggleLayer", t.testToggleLayerHasOffManipulatorFirst), ("delayAndShellChain", t.testDelayAndShellChain),
  ("holdReleaseAppCondition", t.testHoldReleaseAndAppCondition), ("doubleTap", t.testDoubleTapProducesTwoManipulators),
  ("keyCodesUnique", t.testKeyCodesAreUnique), ("applyMergesAndKeepsUserRules", t.testApplyMergesAndKeepsUserRules),
  ("presets", testPresetsCompileAndAreClean), ("conflictShadowedTrigger", testConflictShadowedTrigger), ("importerSkipsComplex", testImporterSkipsComplex), ("simulator", testSimulator), ("inputModifiers", testInputModifiers), ("variants", testVariantsOrderedAndResolved), ("layoutsDoNotOverlap", testLayoutsDoNotOverlap), ("jisKeys", testJISHasItsOwnKeys), ("extendedKeys", testExtendedKeysAndMediaRow), ("customConfigFile", testCustomConfigFileAndProjectRoundTrip), ("copyPaste", testCopyPasteKeySettings), ("tapKeepsOriginal", testTapKeepsOriginalFunction), ("topRow", testTopRowMatchesFunctionAndMediaKeys), ("removeLayers", testRemoveSeveralLayers), ("mouse", testMouseButtons), ("deviceCondition", testDeviceCondition), ("duplicateBinding", testDuplicateBindingWarning), ("chords", testChordsPrecedeSingleKeys), ("layerReorder", testLayerReorder), ("legendsFit", testLegendsFitAtMinimumUnit), ("capTextFits", testCapTextFitsAndNeverEllipsizes)]
for (name, fn) in cases {
  let before = failures
  do { try fn() } catch { failures += 1; print("  ERROR \(error)") }
  print(failures == before ? "PASS \(name)" : "FAIL \(name)")
}
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
