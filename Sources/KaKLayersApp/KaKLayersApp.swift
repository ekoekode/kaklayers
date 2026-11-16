import SwiftUI
import AppKit
import KaKLayersCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}

@main
struct KaKLayersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = CommandLine.arguments.contains("--demo")
        ? { let a = AppState(project: Snapshot.demoProject(), persist: false); 
            func arg(_ n: String) -> String? { CommandLine.arguments.firstIndex(of: n).flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } }
            let l = arg("--layer"); a.activeLayer = l == "base" ? nil : (l ?? "nav"); a.selectedKey = arg("--key") ?? "h"
            if let m = arg("--mods") { a.variantMods = m.split(separator: ",").map(String.init) }
            if CommandLine.arguments.contains("--media") { a.mediaRow = true }
            if CommandLine.arguments.contains("--all-layers") { a.showAllLayers = true }
            return a }()
        : AppState()
    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(to: CommandLine.arguments[i + 1]); exit(0)
        }
        if CommandLine.arguments.contains("--bench") {
            let st = AppState(project: Snapshot.stressProject(), persist: false); st.activeLayer = "nav"; st.showAllLayers = true
            let t0 = CFAbsoluteTimeGetCurrent(); for _ in 0..<200 { _ = st.capModels(unit: 62) }
            print("capModels: \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - t0) / 200 * 1000)) ms per redraw")
            let t1 = CFAbsoluteTimeGetCurrent(); for _ in 0..<200 { _ = ConflictChecker.check(st.project) }
            print("checker:   \(String(format: "%.3f", (CFAbsoluteTimeGetCurrent() - t1) / 200 * 1000)) ms")
            let t2 = CFAbsoluteTimeGetCurrent(); let found = InstalledApps.scan()
            print("apps found: \(found.count) in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t2) * 1000)) ms; first: \(found.prefix(4).map { "\($0.name) [\($0.id)]" })")
            var edited = AppState.legacyStarter(); edited.layers[0].name = "Mine"
            print("legacy detected:", AppState.isLegacyStarter(AppState.legacyStarter()), "| edited project kept:", !AppState.isLegacyStarter(edited), "| default empty:", AppState.starter().layers.isEmpty)
            exit(0)
        }
        if CommandLine.arguments.contains("--dark") { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--light") { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        PerfLog.shared.start()
    }
    var body: some Scene {
        WindowGroup("🍰 KāKLayers") {
            ContentView().environmentObject(state).frame(minWidth: CGFloat(Metrics.minWindowWidth), minHeight: 780)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { state.undo() }.keyboardShortcut("z").disabled(!state.canUndo)
                Button("Redo") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!state.canRedo)
            }
        }
    }
}
