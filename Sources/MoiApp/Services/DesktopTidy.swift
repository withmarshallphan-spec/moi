import CoreServices
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Tidies the loose files on the Desktop by moving them into one dated folder, sorted by kind.
/// Moving is the whole trick: nothing is deleted, renamed or overwritten, the files stay on the
/// same disk (a rename, so dates, tags and iCloud state are untouched), and every tidy can be
/// put back exactly. Folders, apps, links, hidden files and anything still being written stay put.
enum DesktopTidy {
    enum Kind: String, CaseIterable, Codable {
        case screenshots = "Screenshots", images = "Images", documents = "Documents", media = "Audio & video", archives = "Installers & archives", other = "Other"
        var symbol: String {
            switch self {
            case .screenshots: "camera.viewfinder"
            case .images: "photo"
            case .documents: "doc.text"
            case .media: "play.rectangle"
            case .archives: "shippingbox"
            case .other: "doc"
            }
        }
    }

    struct Move: Codable, Hashable { var from: String; var to: String }
    struct Plan { var folder: URL; var moves: [Move]; var left: [String] }
    struct Record: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var folder: String
        var moves: [Move]
        var undone = false
        /// Moved to the Trash (by explicit choice) instead of into a folder. Optional so older history still loads.
        var trashed: Bool?
    }

    static let documentExtensions: Set<String> = ["pdf", "txt", "md", "rtf", "doc", "docx", "pages", "key", "ppt", "pptx", "numbers", "xls", "xlsx", "csv", "odt", "epub"]
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]

    static func kind(of url: URL, isScreenshot: Bool) -> Kind {
        if isScreenshot { return .screenshots }
        let ext = url.pathExtension.lowercased()
        if documentExtensions.contains(ext) { return .documents }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audiovisualContent) { return .media }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) || ext == "pkg" { return .archives }
        return .other
    }

    /// Spotlight knows which files are screen captures in any language; names are the fallback.
    static func isScreenshot(_ url: URL) -> Bool {
        if let item = MDItemCreateWithURL(nil, url as CFURL), let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, flag { return true }
        return looksLikeScreenshot(url.lastPathComponent)
    }

    static func looksLikeScreenshot(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["screenshot", "screen shot", "screen recording", "cleanshot"].contains { n.hasPrefix($0) }
    }

    static func folderName(_ date: Date) -> String { "Tidied " + date.formatted(.dateTime.day().month(.abbreviated).year()) }

    /// What a tidy would do, without touching anything. `left` names what stays and why.
    static func plan(desktop: URL, now: Date = Date(), isScreenshot: (URL) -> Bool = isScreenshot) throws -> Plan {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let items = try fm.contentsOfDirectory(at: desktop, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var folder = desktop.appendingPathComponent(folderName(now), isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: folder.path) { folder = desktop.appendingPathComponent("\(folderName(now)) \(n)", isDirectory: true); n += 1 }
        var moves: [Move] = [], left: [String] = []
        for url in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue } // folders and apps are already organised
            if values?.isSymbolicLink == true { left.append("\(url.lastPathComponent) (a link)"); continue }
            if partialExtensions.contains(url.pathExtension.lowercased()) || (values?.contentModificationDate).map({ now.timeIntervalSince($0) < 120 }) == true {
                left.append("\(url.lastPathComponent) (still being saved)"); continue
            }
            let kind = kind(of: url, isScreenshot: isScreenshot(url))
            moves.append(Move(from: url.path, to: folder.appendingPathComponent(kind.rawValue, isDirectory: true).appendingPathComponent(url.lastPathComponent).path))
        }
        return Plan(folder: folder, moves: moves, left: left)
    }

    /// Exact copies among these files (same size, then same SHA-256), oldest first in each group.
    /// Files over 500 MB are skipped so a preview never stalls on a huge video.
    static func duplicateGroups(_ paths: [String]) -> [[String]] {
        let fm = FileManager.default
        func size(_ p: String) -> Int64 { (try? fm.attributesOfItem(atPath: p)[.size] as? Int64) ?? -1 }
        func created(_ p: String) -> Date { (try? fm.attributesOfItem(atPath: p)[.creationDate] as? Date) ?? .distantFuture }
        func digest(_ p: String) -> String? {
            guard let handle = FileHandle(forReadingAtPath: p) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let bySize = Dictionary(grouping: paths.filter { (1...500_000_000).contains(size($0)) }, by: size).values.filter { $0.count > 1 }
        return bySize.flatMap { same in Dictionary(grouping: same) { digest($0) ?? UUID().uuidString }.values.filter { $0.count > 1 } }
            .map { $0.sorted { created($0) < created($1) } }
    }

    /// Moves what's still where the preview saw it. Never overwrites (`moveItem` refuses).
    static func apply(_ plan: Plan, now: Date = Date()) -> (record: Record, failures: [String]) {
        let fm = FileManager.default
        var done: [Move] = [], failures: [String] = []
        for move in plan.moves {
            let name = URL(fileURLWithPath: move.from).lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: move.from, isDirectory: &isDir), !isDir.boolValue else { failures.append("\(name) was moved or removed since the preview"); continue }
            do {
                try fm.createDirectory(at: URL(fileURLWithPath: move.to).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(atPath: move.from, toPath: move.to)
                done.append(move)
            } catch { failures.append("\(name): \(error.localizedDescription)") }
        }
        if done.isEmpty { removeIfEmpty(plan.folder) }
        return (Record(date: now, folder: plan.folder.path, moves: done), failures)
    }

    /// Moves exactly these files to the Trash, only ever by the person's explicit choice. The Trash
    /// is never emptied by moi, and the record allows putting them back.
    static func trash(_ paths: [String], now: Date = Date()) -> (record: Record, failures: [String]) {
        var done: [Move] = [], failures: [String] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var result: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                if let to = result?.path { done.append(Move(from: path, to: to)) }
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return (Record(date: now, folder: "", moves: done, trashed: true), failures)
    }

    /// Puts every file back where it was, if that spot is still free. Removes the tidy folder only if it ends up empty.
    static func undo(_ record: Record) -> (restored: Int, failures: [String]) {
        let fm = FileManager.default
        var restored = 0, failures: [String] = []
        for move in record.moves.reversed() {
            let name = URL(fileURLWithPath: move.from).lastPathComponent
            guard fm.fileExists(atPath: move.to) else { failures.append("\(name) is no longer in the tidy folder"); continue }
            guard !fm.fileExists(atPath: move.from) else { failures.append("\(name): something new is already on the Desktop with that name"); continue }
            do { try fm.moveItem(atPath: move.to, toPath: move.from); restored += 1 }
            catch { failures.append("\(name): \(error.localizedDescription)") }
        }
        guard record.trashed != true, !record.folder.isEmpty else { return (restored, failures) }
        let folder = URL(fileURLWithPath: record.folder)
        for kind in Kind.allCases { removeIfEmpty(folder.appendingPathComponent(kind.rawValue)) }
        removeIfEmpty(folder)
        return (restored, failures)
    }

    /// Only ever removes a folder with nothing in it (Finder's .DS_Store aside).
    private static func removeIfEmpty(_ folder: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: folder.path), contents.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? fm.removeItem(at: folder)
    }
}

/// The newest things that landed on this Mac: downloads and screenshots, for the notch.
enum RecentFiles {
    /// Where macOS saves screenshots (Screenshot app → Options → Save to), Desktop by default.
    static func screenshotFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    static var downloads: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true) }

    /// Newest first by when each file arrived in its folder. Top level only; skips folders and partial downloads.
    static func latest(in folders: [URL], limit: Int) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .addedToDirectoryDateKey, .creationDateKey]
        var seen = Set<String>()
        let files = folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        }.filter { url in
            guard seen.insert(url.standardizedFileURL.path).inserted else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true && !DesktopTidy.partialExtensions.contains(url.pathExtension.lowercased())
        }
        func added(_ url: URL) -> Date {
            let v = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            return v?.addedToDirectoryDate ?? v?.creationDate ?? .distantPast
        }
        return Array(files.map { ($0, added($0)) }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
    }
}
