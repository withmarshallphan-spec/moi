import AppKit
import Carbon
import Combine

struct InstalledApplication: Identifiable {
    var id: String { url.path }
    var name: String
    var bundleID: String
    var url: URL
}
enum CommandShortcut: String, CaseIterable, Identifiable {
    case controlOptionSpace = "⌃⌥ Space", controlShiftSpace = "⌃⇧ Space", commandShiftSpace = "⌘⇧ Space"
    var id: String { rawValue }
    var modifiers: UInt32 { switch self { case .controlOptionSpace: UInt32(controlKey | optionKey); case .controlShiftSpace: UInt32(controlKey | shiftKey); case .commandShiftSpace: UInt32(cmdKey | shiftKey) } }
}
@MainActor
final class MoiWorkspace: ObservableObject {
    static let shared = MoiWorkspace()
    @Published var error: String?
    @Published var message = ""
    @Published var applications: [InstalledApplication] = []
    @Published var shortcutError: String?
    @Published var theme: String { didSet { UserDefaults.standard.set(theme, forKey: "moi.theme") } }
    @Published var companionEnabled: Bool { didSet { UserDefaults.standard.set(companionEnabled, forKey: "moi.companion"); companion?.sync() } }
    @Published var companionSize: Double { didSet { UserDefaults.standard.set(companionSize, forKey: "moi.companionSize"); companion?.sync() } }
    @Published var animate: Bool { didSet { UserDefaults.standard.set(animate, forKey: "moi.animate") } }
    @Published var shortcut: CommandShortcut { didSet { UserDefaults.standard.set(shortcut.rawValue, forKey: "moi.commandShortcut"); configureHotkeys() } }
    @Published var onboarding = false
    @Published var notchEditor = false
    @Published var about = false
    @Published var planMode = "List"
    private var configured = false
    private(set) weak var store: AppStore?
    private var commandPanel: CommandPanelController?
    private var companion: CompanionController?
    private var sleepObserver: NSObjectProtocol?
    init() {
        let defaults = UserDefaults.standard
        theme = defaults.string(forKey: "moi.theme") ?? "Dark"
        companionEnabled = defaults.object(forKey: "moi.companion") as? Bool ?? false // optional; the Pocket is moi's sticky home on the desktop
        companionSize = defaults.object(forKey: "moi.companionSize") as? Double ?? 64
        animate = defaults.object(forKey: "moi.animate") as? Bool ?? true
        shortcut = CommandShortcut(rawValue: defaults.string(forKey: "moi.commandShortcut") ?? "") ?? .controlOptionSpace
    }
    func configure(store: AppStore) {
        guard !configured else { return }
        configured = true; self.store = store
        Task { await Intelligence.shared.checkBrains() } // free: lists models, never chats
        MacControl.startWatchingAppUse() // so "apps you're not using" means something
        if let text = ProcessInfo.processInfo.environment["MOI_ASK"], MoiPaths.isDevelopment { // development: one request, logged
            Task { try? await Task.sleep(for: .seconds(2)); Intelligence.shared.draft = text; Intelligence.shared.respond(store: store) }
        }
        commandPanel = CommandPanelController(workspace: self, store: store)
        companion = CompanionController(workspace: self)
        companion?.sync(); configureHotkeys()
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }),
           !NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(window.frame) }) { fitMainWindow() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in VoiceService.shared.cancel(); Intelligence.shared.cancel() }
        }
        onboarding = !UserDefaults.standard.bool(forKey: "moi.onboardingComplete")
        // MOI_ONBOARDING=1 replays the introduction from the start (handy during development).
        if ProcessInfo.processInfo.environment["MOI_ONBOARDING"] == "1" { UserDefaults.standard.set(0, forKey: "moi.onboardingStep"); onboarding = true }
        if ProcessInfo.processInfo.environment["MOI_NOTCH_EDITOR"] == "1", MoiPaths.isDevelopment { onboarding = false; showMain(.settings); notchEditor = true }
        if let text = ProcessInfo.processInfo.environment["MOI_PHOTO_SEARCH"], MoiPaths.isDevelopment { TidyStore.shared.tab = .photos; showMain(.clean); PhotoFinder.shared.search(text) }
        // MOI_SECTION=<rawValue> opens a section at launch (development screenshots).
        if let raw = ProcessInfo.processInfo.environment["MOI_SECTION"], let section = SidebarSection(rawValue: raw) { onboarding = false; showMain(section); if section == .clean { TidyStore.shared.preview() } }
        refreshApplications()
    }
    func configureHotkeys() {
        guard configured else { return }
        var errors: [String] = []
        if !HotKeyCenter.shared.register(.command, keyCode: UInt32(kVK_Space), modifiers: shortcut.modifiers, action: { [weak self] in self?.showCommand() }) { errors.append("The Ask moi shortcut is in use. Choose another combination.") }
        if UserDefaults.standard.bool(forKey: "moi.voiceShortcutEnabled") {
            if !HotKeyCenter.shared.register(.voice, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), action: {
                Task { await VoiceService.shared.talk() }
            }, release: { VoiceService.shared.finish() }) { errors.append("Voice shortcut ⌃⌥V is in use.") }
        } else { HotKeyCenter.shared.unregister(.voice) }
        shortcutError = errors.isEmpty ? nil : errors.joined(separator: " ")
    }
    /// The Ask moi panel, from the global shortcut or the menu.
    func showCommand() { commandPanel?.toggle() }
    func showMain(_ section: SidebarSection? = nil) {
        if let section { store?.selectedSection = section }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
    func resetCompanionPosition() { UserDefaults.standard.removeObject(forKey: "moi.companionPosition"); companion?.sync(reset: true) }
    func fitMainWindow() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }),
              let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 20, dy: 20)
        let width = min(1240, available.width), height = min(820, available.height)
        window.setFrame(NSRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height), display: true)
    }
    func openApplication(_ identifier: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { throw MoiError.message("Application not installed: \(identifier)") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if app != nil { continuation.resume() }
                else { continuation.resume(throwing: MoiError.message("Application launch did not return a running app.")) }
            }
        }
    }
    func refreshApplications() {
        applications = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"].flatMap { path in
            (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.pathExtension == "app" }.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            return InstalledApplication(name: url.deletingPathExtension().lastPathComponent, bundleID: id, url: url)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
