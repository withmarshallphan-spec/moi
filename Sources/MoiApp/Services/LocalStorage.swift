import Foundation

enum MoiPaths {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["MOI_DATA_DIR"] { return URL(fileURLWithPath: path, isDirectory: true) }
        // One folder per app flavour: "Moi", "Moi Development", "Moi First Run" (a clean first-launch build).
        let id = Bundle.main.bundleIdentifier ?? ""
        let name = id.hasSuffix(".development") ? "Moi Development" : id.hasSuffix(".firstrun") ? "Moi First Run" : "Moi"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name, isDirectory: true)
    }
    static var isDevelopment: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".development") == true || ProcessInfo.processInfo.environment["MOI_DATA_DIR"] != nil }
}

enum LocalStorage {
    private struct RestoreEntry: Codable { var path: String; var snapshot: String? }
    private struct RestoreManifest: Codable { var entries: [RestoreEntry]; var committed = false }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
    static func load<T: Decodable>(_ type: T.Type, from url: URL, default value: @autoclosure () -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return value() }
        return try decoder().decode(type, from: Data(contentsOf: url))
    }
    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    @discardableResult static func snapshot(_ url: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let dest = url.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true).appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
    static func recoverRestore(in root: URL) throws {
        let pending = root.appendingPathComponent("Recovery/PendingRestore")
        let manifestURL = pending.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: pending.path) else { return }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            // No manifest means no target writes were started.
            try FileManager.default.removeItem(at: pending)
            return
        }
        let manifest = try load(RestoreManifest.self, from: manifestURL, default: RestoreManifest(entries: []))
        if !manifest.committed {
            for entry in manifest.entries {
                let target = root.appendingPathComponent(entry.path).standardizedFileURL
                guard target.path.hasPrefix(root.standardizedFileURL.path + "/"),
                      !entry.path.hasPrefix("Recovery/"),
                      !entry.path.split(separator: "/").contains("..") else { throw MoiError.message("Invalid restore journal. Original data is write-locked.") }
                if let name = entry.snapshot {
                    let saved = pending.appendingPathComponent(name).standardizedFileURL
                    guard saved.deletingLastPathComponent() == pending else { throw MoiError.message("Invalid recovery snapshot path.") }
                    try Data(contentsOf: saved).write(to: target, options: .atomic)
                } else if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
            }
        }
        let kept = root.appendingPathComponent("Recovery/Restore-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: pending, to: kept)
    }
    static func restore(_ files: [String: Data], in root: URL) throws {
        try recoverRestore(in: root)
        let pending = root.appendingPathComponent("Recovery/PendingRestore")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var manifest = RestoreManifest(entries: [])
        for (path, _) in files.sorted(by: { $0.key < $1.key }) {
            let target = root.appendingPathComponent(path).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/"),
                  !path.hasPrefix("Recovery/"), !path.split(separator: "/").contains("..") else { throw MoiError.message("Invalid restore target.") }
            var entry = RestoreEntry(path: path)
            if FileManager.default.fileExists(atPath: target.path) {
                let name = UUID().uuidString + ".snapshot"
                try FileManager.default.copyItem(at: target, to: pending.appendingPathComponent(name))
                entry.snapshot = name
            }
            manifest.entries.append(entry)
        }
        try save(manifest, to: pending.appendingPathComponent("manifest.json"))
        do {
            for (path, bytes) in files {
                let target = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target, options: .atomic)
            }
            manifest.committed = true
            try save(manifest, to: pending.appendingPathComponent("manifest.json"))
            try recoverRestore(in: root)
        } catch {
            do { try recoverRestore(in: root) }
            catch { throw MoiError.message("Restore failed and rollback needs attention. Recovery journal preserved: " + error.localizedDescription) }
            throw error
        }
    }
}

enum MoiError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

extension AppData {
    func validate() throws {
        guard schemaVersion <= 6 else { throw MoiError.message("This data was saved by a newer moi. The original is preserved; install a compatible version.") }
        for ids in [tasks.map(\.id), projects.map(\.id), deadlines.map(\.id), scheduleBlocks.map(\.id), launcherItems.map(\.id), modes.map(\.id)] {
            guard Set(ids).count == ids.count else { throw MoiError.message("The backup contains duplicate identifiers.") }
        }
        for block in scheduleBlocks {
            guard (0...23).contains(block.startTime.hour), (0...23).contains(block.endTime.hour), (0...59).contains(block.startTime.minute), (0...59).contains(block.endTime.minute), block.recurrence.weekdays.isSubset(of: Set(1...7)) else { throw MoiError.message("A schedule block has invalid times or weekdays.") }
        }
        guard settings.hudOpacity.isFinite, (0...1).contains(settings.hudOpacity), TimeZone(identifier: settings.timeZoneID) != nil else { throw MoiError.message("Invalid opacity or time zone in imported settings.") }
    }
}
