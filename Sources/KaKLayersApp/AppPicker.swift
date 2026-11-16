import SwiftUI
import AppKit

struct InstalledApp: Identifiable, Hashable {
    let id: String        // bundle identifier
    let name: String
    let path: String
}

/// Installed applications, scanned once in the background.
@MainActor
final class InstalledApps: ObservableObject {
    static let shared = InstalledApps()
    @Published private(set) var apps: [InstalledApp] = []
    private var started = false

    func loadIfNeeded() {
        guard !started else { return }
        started = true
        Task.detached(priority: .utility) {
            let found = InstalledApps.scan()
            await MainActor.run { InstalledApps.shared.apps = found }
        }
    }

    nonisolated static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var seen = Set<String>(); var out: [InstalledApp] = []
        for d in dirs {
            for item in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where item.hasSuffix(".app") && !item.hasPrefix(".") {
                let path = d + "/" + item
                guard let id = Bundle(path: path)?.bundleIdentifier, seen.insert(id).inserted else { continue }
                out.append(InstalledApp(id: id, name: String(item.dropLast(4)), path: path))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Name and path for a bundle id, even if the app is outside the scanned folders.
    func lookup(_ bundleId: String) -> (name: String, path: String)? {
        if let a = apps.first(where: { $0.id == bundleId }) { return (a.name, a.path) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return (url.deletingPathExtension().lastPathComponent, url.path)
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(path: String) -> NSImage {
        if let i = cache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path); i.size = NSSize(width: 20, height: 20)
        cache[path] = i; return i
    }
}

struct AppIconView: View {
    @ObservedObject private var installed = InstalledApps.shared
    let bundleId: String
    var body: some View {
        if let found = installed.lookup(bundleId) {
            Image(nsImage: AppIcons.icon(path: found.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "questionmark.app").foregroundStyle(.secondary).frame(width: 18, height: 18)
        }
    }
}

/// Label for a chosen app: icon and name (or the raw bundle id when the app isn't installed).
struct AppLabel: View {
    @ObservedObject private var installed = InstalledApps.shared
    let bundleId: String
    var body: some View {
        HStack(spacing: 6) {
            AppIconView(bundleId: bundleId)
            Text(installed.lookup(bundleId)?.name ?? (bundleId.isEmpty ? "Choose app" : bundleId)).fixedSize()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .onAppear { installed.loadIfNeeded() }
    }
}

/// Searchable list of installed apps plus Browse… for anything else.
struct AppPickerList: View {
    @ObservedObject private var installed = InstalledApps.shared
    @StateObject private var query = TextBox()
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        let q = query.text.trimmingCharacters(in: .whitespaces)
        let rows = q.isEmpty ? installed.apps : installed.apps.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search apps", text: $query.text).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
                Button("Browse…") { browse() }.controlSize(.small)
            }.padding(10)
            Divider()
            if installed.apps.isEmpty {
                Text("Loading apps…").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                Text("No match. Use Browse… to find an app anywhere on this Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { a in
                            Button { pick(a.id) } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: AppIcons.icon(path: a.path)).resizable().frame(width: 22, height: 22)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(a.name).font(.system(size: 13)).fixedSize()
                                        Text(a.id).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                                    }
                                    Spacer(minLength: 8)
                                    if a.id == selected { Image(systemName: "checkmark") }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 380)
        .onAppear { installed.loadIfNeeded() }
    }

    func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an application"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        pick(id)
    }
}
