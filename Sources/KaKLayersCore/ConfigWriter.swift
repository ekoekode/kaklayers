import Foundation

public struct ApplyResult {
    public var configPath: String
    public var backupPath: String?
    public var exportPath: String?      // nil when applying to a custom file
    public var ruleCount: Int
}

/// Merges generated rules into the user's karabiner.json without touching
/// anything we didn't create (rules are identified by `KarabinerCompiler.rulePrefix`).
public struct ConfigWriter {
    public let dir: URL
    /// A karabiner.json somewhere else (a dotfiles repo, a second profile file). nil = `dir/karabiner.json`.
    public let configFile: URL?

    public static var defaultDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/karabiner")
    }

    public init(dir: URL = ConfigWriter.defaultDir, configFile: URL? = nil) { self.dir = dir; self.configFile = configFile }

    var configURL: URL { configFile ?? dir.appendingPathComponent("karabiner.json") }
    public var configPath: String { configURL.path }
    /// Backups live next to whichever file is being edited.
    var backupDir: URL { configURL.deletingLastPathComponent().appendingPathComponent("layers-backups") }
    var exportURL: URL { dir.appendingPathComponent("assets/complex_modifications/kaklayers.json") }

    public func apply(_ project: Project) throws -> ApplyResult {
        let fm = FileManager.default
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var root: JSON
        var backup: String?
        if fm.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? JSON else {
                throw NSError(domain: "KaKLayers", code: 1, userInfo: [NSLocalizedDescriptionKey: "karabiner.json is not a JSON object"])
            }
            root = parsed
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let dest = backupDir.appendingPathComponent("karabiner-\(stamp).json")
            try data.write(to: dest)
            backup = dest.path
        } else {
            root = ["profiles": [["name": "Default profile", "selected": true,
                                  "complex_modifications": ["rules": [JSON]()]] as JSON]]
        }

        var profiles = (root["profiles"] as? [JSON]) ?? []
        if profiles.isEmpty { profiles = [["name": "Default profile", "selected": true]] }
        let idx = profiles.firstIndex { ($0["selected"] as? Bool) == true } ?? 0

        var profile = profiles[idx]
        var cm = (profile["complex_modifications"] as? JSON) ?? [:]
        let existing = (cm["rules"] as? [JSON]) ?? []
        let kept = existing.filter { !KarabinerCompiler.isOurs($0["description"] as? String ?? "") }
        let ours = KarabinerCompiler.rules(for: project)
        cm["rules"] = ours + kept        // our rules first so layers win over generic rules
        profile["complex_modifications"] = cm
        profiles[idx] = profile
        root["profiles"] = profiles

        try write(root, to: configURL)
        var exported: String?
        if configFile == nil {      // the Karabiner assets copy only makes sense for the real config folder
            try fm.createDirectory(at: exportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(KarabinerCompiler.compile(project), to: exportURL)
            exported = exportURL.path
        }
        return ApplyResult(configPath: configURL.path, backupPath: backup, exportPath: exported, ruleCount: ours.count)
    }

    /// Restore the most recent backup made by `apply`.
    @discardableResult
    public func restoreLatestBackup() throws -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: backupDir.path).sorted(), let last = files.last else { return nil }
        let src = backupDir.appendingPathComponent(last)
        try Data(contentsOf: src).write(to: configURL, options: .atomic)
        return src.path
    }

    private func write(_ obj: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
