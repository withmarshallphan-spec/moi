import AppKit
import ApplicationServices

/// Native Mac actions: open apps and websites, quit or hide apps, edit the Dock. No screen
/// scraping or clicking around, so it's instant and each change can be undone.
@MainActor
enum MacControl {
    struct OpenApp: Identifiable, Hashable {
        var id: pid_t
        var name: String
        var bundleID: String
        var url: URL?
        var windows: Int
        var hidden: Bool
    }

    /// Apps with a Dock icon, plus how many windows each has (across every desktop).
    static func openApps() -> [OpenApp] {
        let me = ProcessInfo.processInfo.processIdentifier
        var counts: [pid_t: Int] = [:]
        for w in (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []) where (w[kCGWindowLayer as String] as? Int) == 0 {
            let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            guard (bounds["Width"] ?? 0) > 80, (bounds["Height"] ?? 0) > 60, let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            counts[pid, default: 0] += 1
        }
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated }
            .map { OpenApp(id: $0.processIdentifier, name: $0.localizedName ?? "App", bundleID: $0.bundleIdentifier ?? "", url: $0.bundleURL, windows: counts[$0.processIdentifier] ?? 0, hidden: $0.isHidden) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: When each app was last used

    /// When each app was last in front, by bundle ID. Kept on this Mac (UserDefaults), never sent anywhere.
    private static let lastUsedKey = "moi.appLastUsed"
    private static var watching: NSObjectProtocol?
    /// Since when moi has been watching, so "not used for 30 minutes" is only claimed when it can know.
    static let watchingSince = Date()

    static func startWatchingAppUse() {
        guard watching == nil else { return }
        noteUse(NSWorkspace.shared.frontmostApplication)
        watching = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { noteUse(app) }
        }
    }

    private static func noteUse(_ app: NSRunningApplication?) {
        guard let id = app?.bundleIdentifier else { return }
        var all = UserDefaults.standard.dictionary(forKey: lastUsedKey) as? [String: Double] ?? [:]
        all[id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: lastUsedKey)
    }

    static func lastUsed(_ bundleID: String) -> Date? {
        (UserDefaults.standard.dictionary(forKey: lastUsedKey) as? [String: Double])?[bundleID].map(Date.init(timeIntervalSince1970:))
    }

    /// Why an app looks safe to quit (nil = it's in use). No windows, or not in front for 30+ minutes.
    static func idleReason(_ app: OpenApp, now: Date = Date()) -> String? {
        if app.bundleID == NSWorkspace.shared.frontmostApplication?.bundleIdentifier { return nil }
        if app.windows == 0 { return "No windows open" }
        let used = lastUsed(app.bundleID)
        if let used, now.timeIntervalSince(used) >= 1800 { return "Not used for " + RelativeDateTimeFormatter().localizedString(for: used, relativeTo: now).replacingOccurrences(of: " ago", with: "") }
        if used == nil, now.timeIntervalSince(watchingSince) >= 1800 { return "Not used today" }
        return nil
    }

    /// Finder can't be quit like an app; it's left alone by "quit everything".
    static func targets(_ names: [String], allExcept: [String]?) -> [OpenApp] {
        let apps = openApps().filter { $0.bundleID != "com.apple.finder" }
        func hit(_ app: OpenApp, _ list: [String]) -> Bool { list.contains { app.name.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(app.name) } }
        if let keep = allExcept { return apps.filter { !hit($0, keep) } }
        return apps.filter { hit($0, names) }
    }

    /// Asks each app to quit the normal way, so apps with unsaved work still ask to save.
    static func quit(_ apps: [OpenApp]) -> [OpenApp] {
        apps.filter { app in
            guard let running = NSRunningApplication(processIdentifier: app.id), running.bundleIdentifier == app.bundleID else { return false }
            return running.terminate()
        }
    }

    static func hide(_ apps: [OpenApp]) { apps.forEach { NSRunningApplication(processIdentifier: $0.id)?.hide() } }

    static func reopen(_ apps: [OpenApp]) {
        for app in apps { if let url = app.url { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } }
    }

    // MARK: Websites

    /// Opens a website, in a specific browser and/or a private window when asked.
    static func open(_ url: URL, browser: String?, private isPrivate: Bool) throws {
        let fallback = NSWorkspace.shared.urlForApplication(toOpen: url)
        let appURL = browser.flatMap { name in NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(forBrowser: name) ?? "") } ?? fallback
        guard let appURL else { throw MoiError.message("I couldn't find a browser to open it in.") }
        let appName = appURL.deletingPathExtension().lastPathComponent
        guard isPrivate else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let flag = Web.privateFlag(forBrowser: appName) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            configuration.arguments = [flag, url.absoluteString]
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return
        }
        guard appName.lowercased().contains("safari") else { throw MoiError.message("\(appName) doesn't let other apps open private windows. Try Safari, Chrome, Brave or Firefox.") }
        // Safari has no private-window switch: moi presses ⇧⌘N for you, which macOS only allows with Accessibility.
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
            throw MoiError.message("To open a private Safari window, macOS needs to let me press keys for you (System Settings → Privacy & Security → Accessibility → moi). Then ask me again.")
        }
        let script = """
        tell application "Safari" to activate
        delay 0.4
        tell application "System Events" to keystroke "n" using {command down, shift down}
        delay 0.5
        tell application "Safari" to set URL of front document to "\(url.absoluteString.replacingOccurrences(of: "\"", with: "%22"))"
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { throw MoiError.message("Safari didn't open the private window: \(error[NSAppleScript.errorMessage] as? String ?? "unknown error"). macOS may ask to let moi control Safari.") }
    }

    private static func bundleID(forBrowser name: String) -> String? {
        ["safari": "com.apple.Safari", "google chrome": "com.google.Chrome", "chrome": "com.google.Chrome", "brave": "com.brave.Browser", "firefox": "org.mozilla.firefox", "edge": "com.microsoft.edgemac", "arc": "company.thebrowser.Browser", "opera": "com.operasoftware.Opera", "vivaldi": "com.vivaldi.Vivaldi"][name.lowercased()]
    }

    // MARK: The Dock

    private static let dockDomain = "com.apple.dock" as CFString
    private static let dockKey = "persistent-apps" as CFString

    static func dockItems() -> [DockLayout.Item] {
        CFPreferencesAppSynchronize(dockDomain)
        return CFPreferencesCopyAppValue(dockKey, dockDomain) as? [DockLayout.Item] ?? []
    }

    /// Writes a new app list and restarts the Dock to show it. The caller keeps the old list for undo.
    static func setDockItems(_ items: [DockLayout.Item]) {
        CFPreferencesSetAppValue(dockKey, items as CFArray, dockDomain)
        CFPreferencesAppSynchronize(dockDomain)
        let killall = Process(); killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); killall.arguments = ["Dock"]
        try? killall.run()
    }

    // MARK: Wallpaper

    /// Sets the picture on every screen; returns what each screen had, so it can be put back.
    @discardableResult
    static func setWallpaper(_ url: URL) throws -> [NSScreen: URL] {
        var before: [NSScreen: URL] = [:]
        for screen in NSScreen.screens {
            if let old = NSWorkspace.shared.desktopImageURL(for: screen) { before[screen] = old }
        }
        do {
            for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]) }
        } catch {
            let failures = restoreWallpaper(before)
            throw MoiError.message("Wallpaper change failed: " + error.localizedDescription + (failures.isEmpty ? " Previous wallpapers restored." : " Some displays could not be restored: " + failures.joined(separator: "; ")))
        }
        return before
    }

    @discardableResult static func restoreWallpaper(_ before: [NSScreen: URL]) -> [String] {
        var failures: [String] = []
        for (screen, url) in before {
            guard NSScreen.screens.contains(screen) else { failures.append("A previous display is disconnected"); continue }
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]) }
            catch { failures.append(error.localizedDescription) }
        }
        return failures
    }

    static func appURL(named name: String) -> URL? {
        MoiWorkspace.shared.applications.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.url
            ?? MoiWorkspace.shared.applications.first { $0.name.localizedCaseInsensitiveContains(name) }?.url
    }
}
