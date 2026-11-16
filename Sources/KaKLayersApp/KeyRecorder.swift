import AppKit
import KaKLayersCore

/// Captures a key combo while this app is focused (no special permissions needed).
/// Finishes when every key has been released.
@MainActor
final class KeyRecorder {
    struct Result { var keys: [String]; var main: String?; var modifiers: [String] }

    private var monitor: Any?
    private var pressed: [String] = []
    private var seen: [String] = []
    private var onDone: ((Result) -> Void)?

    func start(_ done: @escaping (Result) -> Void) {
        stop()
        pressed = []; seen = []; onDone = done
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] ev in
            self?.handle(ev); return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ ev: NSEvent) {
        let code = Int(ev.keyCode)
        switch ev.type {
        case .keyDown:
            guard !ev.isARepeat, let k = Keycodes.byMac[code]?.code else { return }
            down(k)
        case .keyUp:
            if let k = Keycodes.byMac[code]?.code { up(k) }
        case .flagsChanged:
            guard let name = Keycodes.modifierMac[code] else { return }
            let flag: NSEvent.ModifierFlags = {
                switch name {
                case "left_command", "right_command": return .command
                case "left_shift", "right_shift": return .shift
                case "left_option", "right_option": return .option
                case "left_control", "right_control": return .control
                case "caps_lock": return .capsLock
                default: return .function
                }
            }()
            if ev.modifierFlags.contains(flag) { down(name) } else { up(name) }
        default: break
        }
    }

    private func down(_ k: String) {
        if !pressed.contains(k) { pressed.append(k) }
        if !seen.contains(k) { seen.append(k) }
    }

    private func up(_ k: String) {
        pressed.removeAll { $0 == k }
        guard pressed.isEmpty, !seen.isEmpty else { return }
        stop()
        let mods = seen.compactMap(Keycodes.genericModifier)
        let nonMod = seen.filter { Keycodes.genericModifier($0) == nil }
        let result = Result(keys: seen, main: nonMod.last ?? seen.last,
                            modifiers: nonMod.isEmpty ? [] : Array(NSOrderedSet(array: mods)) as! [String])
        let cb = onDone; onDone = nil
        cb?(result)
    }
}
