import AppKit

/// Local-only diagnostics: records main-thread stalls (> 30 ms) and the last input event, so slowness can be traced.
/// Written to ~/Library/Logs/KaKLayers/perf.log. Nothing leaves the machine.
final class PerfLog {
    static let shared = PerfLog()
    private var observer: CFRunLoopObserver?
    private var wake = CFAbsoluteTimeGetCurrent()
    private var lastEvent = "launch"
    private var lastEventAt = CFAbsoluteTimeGetCurrent()
    private var handle: FileHandle?
    private var counts: [String: Int] = [:]

    func start() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/KaKLayers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("perf.log")
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("perf-previous.log"))
        try? FileManager.default.moveItem(at: url, to: dir.appendingPathComponent("perf-previous.log"))
        FileManager.default.createFile(atPath: url.path, contents: Data("--- \(Date()) ---\n".utf8))
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()

        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown, .scrollWheel, .mouseEntered, .mouseExited]) { [weak self] ev in
            self?.lastEvent = Self.name(ev.type); self?.lastEventAt = CFAbsoluteTimeGetCurrent(); return ev
        }
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity([.afterWaiting, .beforeWaiting]).rawValue, true, 0) { [weak self] _, act in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if act == .afterWaiting { self.wake = now; return }
            let ms = (now - self.wake) * 1000
            self.counts[self.lastEvent, default: 0] += 1
            if ms > 30 {
                let age = (now - self.lastEventAt) * 1000
                self.write(String(format: "%6.0f ms stall | last input: %@ (%.0f ms before end)\n", ms, self.lastEvent, age))
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        write("logger started; window frames will be listed as stalls\n")
    }

    private func write(_ s: String) { handle?.write(Data(s.utf8)) }

    static func name(_ t: NSEvent.EventType) -> String {
        switch t {
        case .mouseMoved: "mouseMoved"; case .leftMouseDown: "click"; case .leftMouseUp: "clickUp"; case .leftMouseDragged: "drag"
        case .keyDown: "keyDown"; case .scrollWheel: "scroll"; case .mouseEntered: "enter"; case .mouseExited: "exit"
        default: "other"
        }
    }
}
