import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

enum LauncherService {
    @MainActor
    static func open(_ item: LauncherItem) {
        let workspace = NSWorkspace.shared
        switch item.kind {
        case .application:
            guard let url = workspace.urlForApplication(withBundleIdentifier: item.target) else {
                presentError("\(item.title) is not installed or could not be found.")
                return
            }
            workspace.openApplication(at: url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { presentError(error.localizedDescription) } }
            }
        case .url:
            guard let url = URL(string: item.target) else { presentError("Invalid URL."); return }
            workspace.open(url)
        case .file, .folder:
            workspace.open(URL(fileURLWithPath: item.target))
        }
    }

    @MainActor
    static func openWorkspace(ids: [UUID], data: AppData) {
        for item in data.launcherItems.filter({ ids.contains($0.id) }) { open(item) }
    }

    @MainActor
    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not open item"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
final class SoftBlocker {
    static let shared = SoftBlocker()
    private var observer: NSObjectProtocol?
    private weak var store: AppStore?

    private init() {}

    func begin(store: AppStore) {
        self.store = store
        guard store.data.settings.softBlockEnabled, observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in self?.handleLaunch(notification) }
        }
    }

    func end() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        store = nil
    }

    private func handleLaunch(_ notification: Notification) {
        guard let store,
              store.data.settings.softBlockEnabled, store.activeFocus?.pausedAt == nil, store.activeFocus != nil,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              store.data.settings.blockedBundleIDs.contains(bundleID) else { return }
        store.incrementDistractionAttempts()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Focus session active"
        alert.informativeText = "\(app.localizedName ?? "This app") is on your blocked list. Return to the current objective?"
        alert.addButton(withTitle: "Return to Focus")
        alert.addButton(withTitle: "Allow This Time")
        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn, store.data.settings.quitBlockedApps { _ = app.terminate() }
    }
}

enum LoginItemService {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        }
    }
}

enum DataTransferService {
    @MainActor
    static func exportJSON(data: AppData) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Moi Backup \(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(ComprehensiveBackup(appData: data, assistant: AssistantStore.shared.makeArchive())).write(to: url, options: .atomic)
        } catch { show(error) }
    }

    @MainActor
    static func importJSON(into store: AppStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bytes = try Data(contentsOf: url)
            let complete = try? decoder.decode(ComprehensiveBackup.self, from: bytes)
            let legacy = complete == nil ? try decoder.decode(PersistedEnvelope.self, from: bytes) : nil
            let confirmation = NSAlert()
            confirmation.messageText = "Replace local data?"
            confirmation.informativeText = "The current local database will be replaced by this backup. Export first if you need a recovery copy."
            confirmation.addButton(withTitle: "Import")
            confirmation.addButton(withTitle: "Cancel")
            if confirmation.runModal() == .alertFirstButtonReturn {
                if let complete { try store.replaceData(complete.appData, assistant: complete.assistant) }
                else if let legacy { try store.replaceData(legacy.data) }
            }
        } catch { show(error) }
    }

    @MainActor
    static func exportCSV(data: AppData) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Moi Tasks and Deadlines.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var rows = ["Type,Title,Date,Category,Priority,Completed"]
        for task in data.tasks {
            rows.append(csv(["Task", task.title, task.date?.ISO8601Format() ?? "", task.category.rawValue, task.priority.rawValue, task.isCompleted ? "yes" : "no"]))
        }
        for deadline in data.deadlines {
            rows.append(csv(["Deadline", deadline.title, deadline.date.ISO8601Format(), deadline.category.rawValue, deadline.priority.rawValue, deadline.completedAt == nil ? "no" : "yes"]))
        }
        do { try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { show(error) }
    }

    private static func csv(_ fields: [String]) -> String {
        fields.map { field in let safe = "=+-@\t\r".contains(field.first ?? " ") ? "\'" + field : field; return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
    }

    @MainActor private static func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
