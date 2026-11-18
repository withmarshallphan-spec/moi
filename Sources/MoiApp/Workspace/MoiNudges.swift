import AppKit

/// Something moi noticed and can do in one tap.
struct Nudge: Equatable {
    enum Kind: String { case desktop, apps, wrapUp }
    var kind: Kind
    var text: String
    var action: String
}

/// moi notices things and offers, in the notch, to help: a cluttered desktop, apps you've left
/// running, the end of the day. Gentle by design: at most one every 45 minutes, never during Focus,
/// "Not now" snoozes that kind for a day, and the desktop is only looked at once you've allowed it.
@MainActor
final class MoiNudges {
    static let shared = MoiNudges()
    static var enabled: Bool { UserDefaults.standard.object(forKey: "moi.nudges") as? Bool ?? true }
    private weak var notch: NotchController?
    private weak var store: AppStore?
    private var timer: Timer?
    private var last = Date.distantPast

    func start(notch: NotchController, store: AppStore) {
        self.notch = notch; self.store = store
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in MainActor.assumeIsolated { MoiNudges.shared.check() } }
        Task { try? await Task.sleep(for: .seconds(90)); check() }
        if MoiPaths.isDevelopment, ProcessInfo.processInfo.environment["MOI_NUDGE"] != nil { // development: show one now
            Task { try? await Task.sleep(for: .seconds(3)); notch.show(Nudge(kind: .desktop, text: "26 loose files on your desktop.", action: "Tidy them")) }
        }
    }

    func check(now: Date = Date()) {
        guard Self.enabled, let notch, !notch.isOpen, store?.activeFocus == nil, now.timeIntervalSince(last) >= 2700 else { return }
        if let nudge = suggestion(now: now) { last = now; mark(nudge.kind, now: now); notch.show(nudge) }
    }

    private func suggestion(now: Date) -> Nudge? {
        let hour = Calendar.current.component(.hour, from: now)
        if (18..<23).contains(hour), fresh(.wrapUp, now: now) { return Nudge(kind: .wrapUp, text: "Nice work today. Wrap up?", action: "Wrap up") }
        if fresh(.desktop, now: now), desktopAllowed, let loose = try? DesktopTidy.plan(desktop: ScreenTidyStore.shared.desktop).moves.count, loose >= 12 {
            return Nudge(kind: .desktop, text: "\(loose) loose files on your desktop.", action: "Tidy them")
        }
        let idle = MacControl.openApps().filter { $0.bundleID != "com.apple.finder" && MacControl.idleReason($0) != nil }
        if idle.count >= 4, fresh(.apps, now: now) { return Nudge(kind: .apps, text: "\(idle.count) apps you're not using.", action: "Quit them") }
        return nil
    }

    /// Reading the Desktop is what makes macOS ask, so only once access was given.
    private var desktopAllowed: Bool {
        UserDefaults.standard.bool(forKey: "moi.filesAllowed") || !TidyStore.shared.history.isEmpty || ProcessInfo.processInfo.environment["MOI_TIDY_DESKTOP"] != nil
    }

    /// Not shown or snoozed in the last day.
    private func fresh(_ kind: Nudge.Kind, now: Date) -> Bool {
        let at = UserDefaults.standard.double(forKey: "moi.nudge." + kind.rawValue)
        return now.timeIntervalSince1970 - at >= (kind == .wrapUp ? 12 * 3600 : 86_400)
    }
    private func mark(_ kind: Nudge.Kind, now: Date) { UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "moi.nudge." + kind.rawValue) }

    func snooze(_ nudge: Nudge) { mark(nudge.kind, now: Date()) }

    func act(_ nudge: Nudge) {
        let tidy = ScreenTidyStore.shared
        switch nudge.kind {
        case .desktop: tidy.preview(); tidy.quitting = []; Task { await tidy.cleanUp() }
        case .apps: tidy.preview(); tidy.skipped = Set(tidy.plan?.moves.map(\.from) ?? []); Task { await tidy.cleanUp() }
        case .wrapUp: MoiWorkspace.shared.showMain(); MoiWorkspace.shared.wrapUp = true
        }
    }
}
