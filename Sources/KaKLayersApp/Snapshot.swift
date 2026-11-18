import SwiftUI
import AppKit
import KaKLayersCore

/// `Layers --snapshot <dir>` renders the window to PNGs (no screen-recording permission needed).
@MainActor
enum Snapshot {
    /// A tidy sample project for screenshots (`--demo`). Never saved to disk.
    static func demoProject() -> Project {
        func k(_ c: String, _ m: [String] = []) -> Action { .key(KeyCombo(key: c, modifiers: m)) }
        let nav = Layer(id: "nav", name: "Navigate", colorHex: "#4F8EF7", triggerKeys: ["caps_lock"], tapAction: [k("escape")])
        let hyper = Layer(id: "hyper", name: "Hyper", colorHex: "#E5484D", triggerKeys: ["left_command", "left_control", "left_shift", "left_option"])
        let num = Layer(id: "num", name: "Numpad", colorHex: "#F5A524", triggerKeys: ["right_option"])
        var bs: [KeyBinding] = []
        for (f, t) in [("h", "left_arrow"), ("j", "down_arrow"), ("k", "up_arrow"), ("l", "right_arrow"),
                       ("u", "page_down"), ("i", "page_up"), ("y", "home"), ("o", "end")] {
            bs.append(KeyBinding(layerId: "nav", fromKeys: [f], onPress: [k(t)]))
        }
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["h"], fromModifiers: ["command"], onPress: [k("left_arrow", ["command"])]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["spacebar"], onPress: [k("return_or_enter")], onHold: [.delay(150), k("tab")]))
        for (f, app) in [("t", "com.apple.Terminal"), ("s", "com.apple.Safari"), ("m", "com.apple.mail"), ("n", "com.apple.Notes")] {
            bs.append(KeyBinding(layerId: "hyper", fromKeys: [f], onPress: [.openApp(app)]))
        }
        bs.append(KeyBinding(layerId: "hyper", fromKeys: ["d"], onPress: [.shell("open ~/Downloads")]))
        bs.append(KeyBinding(layerId: "hyper", fromKeys: ["f19"], onPress: [k("f13")]))
        for (f, t) in [("m", "keypad_0"), ("j", "keypad_1"), ("k", "keypad_2"), ("l", "keypad_3"), ("u", "keypad_4"), ("i", "keypad_5"), ("o", "keypad_6"),
                       ("7", "keypad_7"), ("8", "keypad_8"), ("9", "keypad_9")] {
            bs.append(KeyBinding(layerId: "num", fromKeys: [f], onPress: [k(t)]))
        }
        bs.append(KeyBinding(fromKeys: ["f13"], onPress: [.consumer("mission_control")]))
        bs.append(KeyBinding(fromKeys: ["button4"], onPress: [k("open_bracket", ["command"])]))
        bs.append(KeyBinding(fromKeys: ["button5"], onPress: [k("close_bracket", ["command"])]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["button1"], onPress: [k("return_or_enter")], onHold: [k("escape")]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["button2"], onPress: [k("tab", ["control"])]))
        bs.append(KeyBinding(fromKeys: ["button3"], onTap: [k("tab", ["control"])], onHold: [.consumer("mission_control")]))
        bs.append(KeyBinding(fromKeys: ["mute"], onPress: [.consumer("play_or_pause")]))
        bs.append(KeyBinding(fromKeys: ["right_command"], onTap: [k("return_or_enter")]))
        return Project(name: "Demo", layers: [nav, hyper, num], bindings: bs)
    }

    static func stressProject() -> Project {
        func k(_ c: String, _ m: [String] = []) -> Action { .key(KeyCombo(key: c, modifiers: m)) }
        let nav = Layer(id: "nav", name: "Nav", colorHex: "#4F8EF7", triggerKeys: ["grave_accent_and_tilde"], tapAction: [k("grave_accent_and_tilde", ["shift"])])
        let hyper = Layer(id: "hyper", name: "Hyper", colorHex: "#E5484D", triggerKeys: ["left_command", "left_control", "left_shift"])
        let vim = Layer(id: "vim", name: "Vim", colorHex: "#30A46C", triggerKeys: ["semicolon"], tapAction: [k("semicolon")])
        let apps = Layer(id: "apps", name: "Launcher", colorHex: "#9B5DE5", mode: .toggle, triggerKeys: ["f19"])
        let num = Layer(id: "num", name: "Numpad", colorHex: "#F5A524", triggerKeys: ["right_option"])
        var bs: [KeyBinding] = []
        for (f, t) in [("h", "left_arrow"), ("j", "down_arrow"), ("k", "up_arrow"), ("l", "right_arrow")] { bs.append(KeyBinding(layerId: "nav", fromKeys: [f], onPress: [k(t)])) }
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["h"], fromModifiers: ["command"], onPress: [k("home")]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["u"], onPress: [k("page_down", ["command", "control", "option", "shift"]), .delay(300), .shell("open -a 'Some Very Long Application Name' --args --flag"), .openApp("com.apple.Terminal"), k("a"), k("b")]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["i"], onPress: [k("f10", ["command", "shift", "option"])], onTap: [k("a")], onHold: [k("b")], onRelease: [.openURL("https://example.com")], onDoubleTap: [k("c")]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["y"], onPress: [.consumer("display_brightness_increment")]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["j", "k"], onPress: [k("escape")]))
        bs.append(KeyBinding(layerId: "hyper", fromKeys: ["t"], onPress: [.openApp("com.apple.Terminal")]))
        bs.append(KeyBinding(layerId: "nav", fromKeys: ["spacebar"], onPress: [.delay(12000)]))
        bs.append(KeyBinding(fromKeys: ["caps_lock"], onPress: [k("left_control")], onTap: [k("escape")]))
        bs.append(KeyBinding(fromKeys: ["delete_forward"], onPress: [k("delete_or_backspace", ["command"])]))
        bs.append(KeyBinding(fromKeys: ["keypad_enter"], onPress: [k("return_or_enter")]))
        return Project(name: "Stress", layers: [nav, hyper, vim, apps, num], bindings: bs)
    }

    /// `n` layers with `per` bindings each, on a spread of letter keys.
    static func manyLayers(_ n: Int, per: Int = 25) -> Project {
        let keys = ["q","w","e","r","t","y","u","i","o","p","a","s","d","f","g","h","j","k","l","z","x","c","v","b","n","m","1","2","3","4","5"]
        var layers: [Layer] = [], bindings: [KeyBinding] = []
        for i in 0..<n {
            let id = "l\(i)"
            layers.append(Layer(id: id, name: "Layer \(i + 1)", colorHex: layerPalette[i % layerPalette.count], triggerKeys: [keys[i % keys.count]]))
            for k in keys.prefix(per) {
                bindings.append(KeyBinding(layerId: id, fromKeys: [k], onPress: [.key(KeyCombo(key: "left_arrow")), .delay(40)], onHold: [.shell("echo hi")]))
            }
        }
        return Project(name: "Many", layers: layers, bindings: bindings)
    }

    /// Times the pieces that scale with layer count.
    static func bench(layers n: Int) {
        func ms(_ reps: Int, _ f: () -> Void) -> String {
            let t = CFAbsoluteTimeGetCurrent(); for _ in 0..<reps { f() }
            return String(format: "%.2f ms", (CFAbsoluteTimeGetCurrent() - t) / Double(reps) * 1000)
        }
        for count in [3, n] {
            let st = AppState(project: manyLayers(count), persist: false); st.activeLayer = "l0"
            print("== \(count) layers, \(st.project.bindings.count) bindings")
            print("capModels:           ", ms(100) { _ = st.capModels(unit: 62) })
            st.showAllLayers = true
            print("capModels (all on):  ", ms(100) { _ = st.capModels(unit: 62) })
            print("conflict check:      ", ms(100) { _ = ConflictChecker.check(st.project) })
            print("compile:             ", ms(20) { _ = KarabinerCompiler.rules(for: st.project) })
            for (label, w) in [("window 1440", CGFloat(1440)), ("window 1240", 1240)] {
                let view = ContentView().environmentObject(st).frame(width: w, height: 860).environment(\.snapshot, true)
                print("full render \(label):", ms(3) { let r = ImageRenderer(content: view); r.scale = 1; _ = r.nsImage })
            }
        }
    }

    static func run(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cases: [(String, CGFloat, CGFloat, Keycodes.LayoutKind, String?, String, Bool)] = [
            ("w1240-ansi-nav", 1240, 780, .ansi, "nav", "u", false),
            ("w1440-ansi-nav", 1440, 860, .ansi, "nav", "i", false),
            ("w1920-ansi-nav", 1920, 1000, .ansi, "nav", "u", false),
            ("w1440-iso-base", 1440, 860, .iso, nil, "caps_lock", true),
            ("w1440-jis-nav", 1440, 860, .jis, "nav", "h", true),
        ]
        for (name, w, h, layout, layer, key, all) in cases {
            let state = AppState(project: stressProject(), persist: false)
            state.layoutKind = layout; state.activeLayer = layer; state.selectedKey = key; state.showAllLayers = all
            let view = ContentView().environmentObject(state).frame(width: w, height: h).environment(\.colorScheme, .light).environment(\.snapshot, true)
            let r = ImageRenderer(content: view); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")); print("wrote \(name).png")
            } else { print("FAILED \(name)") }
        }
        // empty default project
        let empty = AppState(project: Project(name: "My Layers"), persist: false); empty.layoutKind = .ansi; empty.selectedKey = "a"
        let re = ImageRenderer(content: ContentView().environmentObject(empty).frame(width: 1440, height: 860).environment(\.colorScheme, .light).environment(\.snapshot, true)); re.scale = 2
        if let img = re.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("empty.png")); print("wrote empty")
        }
        // dark
        let state = AppState(project: stressProject(), persist: false); state.layoutKind = .ansi; state.activeLayer = "nav"; state.selectedKey = "u"
        let r = ImageRenderer(content: ContentView().environmentObject(state).frame(width: 1440, height: 860).environment(\.colorScheme, .dark).environment(\.snapshot, true)); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("w1440-ansi-nav-dark.png")); print("wrote dark")
        }
    }
}
