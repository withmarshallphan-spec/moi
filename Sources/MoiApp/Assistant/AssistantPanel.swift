import AppKit
import Carbon
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A non-activating panel's controls must act on the first click. Without this the first
/// click only focuses the panel, which made the glance's buttons feel broken.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The notch grows out of the hardware notch: one black shape that widens into "wings" for a
/// peek and drops down for the full glance. All sizes derive from the real notch size.
enum NotchLayout {
    static let wing: CGFloat = 78
    static let shoulder: CGFloat = 8
    static let width: CGFloat = 600
    static let pad: CGFloat = 18
    static let greeting: CGFloat = 46
    static let player: CGFloat = 138
    static let now: CGFloat = 30
    static let next: CGFloat = 42
    static let actions: CGFloat = 32
    static let gap: CGFloat = 10
    static let recent: CGFloat = 74
    static let recentPrompt: CGFloat = 30
    static let calendar: CGFloat = 46
    static let weather: CGFloat = 42
    /// The mini notch's wings: just room for album art on one side and bars or a timer on the other.
    static let liveWing: CGFloat = 46

    static func height(of part: NotchPart, showsNow: Bool, recentHeight: CGFloat) -> CGFloat {
        switch part {
        case .music: player
        case .tasks: (showsNow ? now : 0) + next
        case .calendar: calendar
        case .weather: weather
        case .files: recentHeight
        }
    }

    /// `parts` are the visible parts in order; hover shows only the first.
    static func size(_ mode: NotchController.Mode, notch: CGSize, parts: [NotchPart], showsNow: Bool = true, recentHeight: CGFloat = 0) -> CGSize {
        switch mode {
        case .collapsed: return notch
        case .live: return CGSize(width: notch.width + 2 * (liveWing + shoulder), height: notch.height)
        case .peek:
            let first = parts.first.map { height(of: $0, showsNow: showsNow, recentHeight: recentHeight) } ?? 0
            return CGSize(width: max(400, notch.width + 2 * (wing + shoulder)), height: notch.height + (first > 0 ? 8 + first + 14 : 0))
        case .expanded:
            let others = parts.filter { $0 != .music }
            let side = others.map { height(of: $0, showsNow: showsNow, recentHeight: recentHeight) + gap }.reduce(0, +) - (others.isEmpty ? 0 : gap)
            let body = max(parts.contains(.music) ? player : 0, min(190, side), parts.isEmpty ? actions : 0)
            let columns = parts.contains(.music) && !others.isEmpty
            return CGSize(width: columns ? width : 400, height: notch.height + 8 + body + 14)
        }
    }
}

/// Idle: an invisible, click-through trigger exactly over the notch.
/// Hover: the medium glance, just the music (or now/next when nothing is playing).
/// Click/shortcut: the biggest glance, with greeting, music, now/next and actions.
@MainActor
final class NotchController: NSObject, ObservableObject {
    /// collapsed: invisible. live: the mini notch while music plays or Focus runs (iPhone-style).
    enum Mode { case collapsed, live, peek, expanded }
    @Published private(set) var mode: Mode = .collapsed
    /// The physical notch (or, on displays without one, a menu-bar-high zero-width slot).
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    /// Bumped on every layout so a delayed shrink can tell it's been superseded.
    private var layoutGeneration = 0
    /// The player row shows whenever the chosen player is open, playing or not.
    @Published private(set) var showsPlayer = false
    /// "Now" only earns a row when something is actually happening (focus or a scheduled block).
    @Published private(set) var showsNow = false
    /// The parts that have something to show, in the person's order.
    @Published private(set) var visibleParts: [NotchPart] = []
    /// The notch editor's copy: always open, never a window of its own.
    private(set) var isPreview = false
    /// Newest downloads and screenshots. Off until the person turns it on, because reading those
    /// folders is what makes macOS ask for access.
    @Published private(set) var recent: [URL] = []
    @Published private(set) var recentEnabled = UserDefaults.standard.bool(forKey: "moi.recentFiles")
    var recentHeight: CGFloat { !recentEnabled ? NotchLayout.recentPrompt : recent.isEmpty ? 0 : NotchLayout.recent }
    let spotify = SpotifyNowPlaying.shared
    private var panel: NotchPanel?
    private weak var store: AppStore?
    private var hoverDwellTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var pointerIsInside = false
    /// Opened by the shortcut: stays until the shortcut, a click elsewhere, or Escape.
    private var sticky = false
    private weak var activeScreen: NSScreen?
    /// Recomputed only when displays change, so the global mouse monitor does no screen math per event.
    private var triggerRects: [NSRect] = []

    // Without a notch, only a thin sliver at the very top-center edge counts.
    private let fallbackTriggerWidth: CGFloat = 180
    private let fallbackTriggerHeight: CGFloat = 3
    /// Long enough that sweeping past the notch on the way to the menu bar doesn't open it.
    private let hoverDwell: Duration = .milliseconds(350)

    /// The glance itself is open (the mini notch doesn't count).
    var isOpen: Bool { mode == .peek || mode == .expanded }

    /// A stand-in for the notch editor's preview, open and live with real data.
    static func preview() -> NotchController {
        let c = NotchController()
        c.isPreview = true; c.mode = .expanded; c.notchSize = CGSize(width: 185, height: 32)
        c.refreshRecent(); c.refreshContent()
        return c
    }

    /// Something worth a mini notch is happening.
    private var hasLive: Bool {
        NotchPreferences().liveActivity && NotchPreferences().panelEnabled && (spotify.snapshot?.isPlaying == true || store?.activeFocus != nil)
    }

    func configure(store: AppStore) {
        guard panel == nil else { return }
        self.store = store
        MoiHaloController.shared.configure(store: store)
        refreshTriggerRects()
        let panel = NotchPanel(contentRect: notchTriggerRect(on: NSScreen.main), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = FirstMouseHostingView(rootView: NotchPanelView(controller: self, spotify: spotify).environmentObject(store))
        self.panel = panel
        if NotchPreferences().panelEnabled {
            panel.orderFrontRegardless()
            installMouseMonitors()
        }
        installHotKey()
        // The introduction ends with moi "moving in": the notch peeks open for a moment.
        NotificationCenter.default.publisher(for: Notification.Name("MoiPeekNotch"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sticky = true; self.open(.peek)
                Task { try? await Task.sleep(for: .seconds(3)); if self.mode == .peek { self.collapse() } }
            }
            .store(in: &subscriptions)
        // Display changes and wake invalidate every frame we computed; start over collapsed.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshTriggerRects(); self?.collapse() }
            .store(in: &subscriptions)
        // Music starting/stopping or data changing while open resizes or closes the glance.
        // Deferred a runloop so the sink reads the values after @Published's willSet.
        spotify.$snapshot.map { _ in () }
            .merge(with: spotify.$isRunning.map { _ in () }, store.$data.map { _ in () }, store.$now.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.contentChanged() }
            .store(in: &subscriptions)
#if DEBUG
        if ProcessInfo.processInfo.environment["MOI_PRESENCE_SMOKE_TEST"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.sticky = true; self?.open(.peek)
                try? await Task.sleep(for: .seconds(2.5))
                self?.expand(sticky: true)
                try? await Task.sleep(for: .seconds(3))
                self?.collapse()
            }
        }
#endif
    }

    func toggleExpanded() { mode == .expanded ? collapse() : expand(sticky: true) }

    func expand(sticky: Bool) {
        self.sticky = sticky
        open(.expanded)
    }

    /// moi peeks out on hover, even with nothing to report: notch-height wings cover nothing.
    private func peek() {
        sticky = false
        open(.peek)
    }

    private func open(_ newMode: Mode) {
        guard let panel else { return }
        hoverDwellTask?.cancel()
        hoverExitTask?.cancel()
        if !isOpen { prepareGlance() }
        mode = newMode
        panel.hasShadow = false // a window shadow outlines the shape, including its top edge
        panel.ignoresMouseEvents = false
        layout()
        panel.orderFrontRegardless()
    }

    func collapse() {
        guard let panel else { return }
        hoverDwellTask?.cancel()
        hoverExitTask?.cancel()
        sticky = false
        mode = hasLive ? .live : .collapsed
        if mode == .live { measureNotch() }
        spotify.stop(client: "notch")
        panel.hasShadow = false
        panel.ignoresMouseEvents = mode == .collapsed
        layout()
        panel.resignKey()
        if NotchPreferences().panelEnabled { panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            collapse()
            installMouseMonitors()
        } else {
            collapse()
            pointerIsInside = false
            removeMouseMonitors()
            panel?.orderOut(nil)
        }
    }

    /// Music starting or stopping moves between invisible and the mini notch; open glances resize.
    private func contentChanged() {
        if !isOpen, (mode == .live) != hasLive { collapse(); return }
        guard mode != .collapsed else { return }
        layout()
    }

    /// Re-reads which parts are on (the editor calls this after a change).
    func partsChanged() {
        refreshContent()
        if isOpen || mode == .live { layout() }
    }

    private func refreshContent() {
        showsPlayer = spotify.isRunning || spotify.snapshot != nil
        if let store {
            if store.activeFocus != nil { showsNow = true }
            else if case .active = ScheduleEngine.state(at: store.now, data: store.data, calendar: store.calendar) { showsNow = true }
            else { showsNow = false }
        }
        visibleParts = NotchPreferences().parts.filter { part in
            switch part {
            case .music: showsPlayer
            case .files: recentHeight > 0
            default: true
            }
        }
    }

    /// The window never animates (that raced with collapse and could strand a large invisible
    /// panel over the menu bar). It grows to the larger frame at once; the SwiftUI shape springs
    /// inside it; shrinking waits until the spring has finished, unless something newer happened.
    private func layout() {
        refreshContent()
        guard let panel else { return }
        layoutGeneration += 1
        let generation = layoutGeneration
        let target: NSRect
        if mode == .collapsed { target = notchTriggerRect(on: activeScreen ?? screenContainingMouse() ?? NSScreen.main) }
        else { let size = NotchLayout.size(mode, notch: notchSize, parts: visibleParts, showsNow: showsNow, recentHeight: recentHeight); target = attachedFrame(width: size.width, height: size.height) }
        guard panel.frame != target else { return }
        let grows = target.width >= panel.frame.width && target.height >= panel.frame.height
        if grows || !panel.isVisible { panel.setFrame(target, display: true); return }
        panel.setFrame(panel.frame.union(target), display: true)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 380))
            guard let self, self.layoutGeneration == generation else { return }
            panel.setFrame(target, display: true)
        }
    }

    func hoverChanged(_ isInside: Bool) {
        guard !isPreview, pointerIsInside != isInside else { return }
        pointerIsInside = isInside
        if isInside {
            hoverExitTask?.cancel()
            guard !isOpen, NotchPreferences().opensOnHover else { return }
            hoverDwellTask?.cancel()
            hoverDwellTask = Task { [weak self, hoverDwell] in
                try? await Task.sleep(for: hoverDwell)
                guard !Task.isCancelled, let self, self.pointerIsInside, !self.isOpen else { return }
                self.peek()
            }
        } else {
            hoverDwellTask?.cancel()
            guard isOpen, !sticky else { return }
            // The short grace interval prevents a false close while the surface grows from the notch.
            hoverExitTask?.cancel()
            hoverExitTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self, !self.pointerIsInside else { return }
                self.collapse()
            }
        }
    }

    private func pointerMoved(to point: NSPoint) {
        let overNotch = triggerRects.contains { $0.contains(point) }
        if overNotch, mode == .collapsed { activeScreen = NSScreen.screens.first { $0.frame.contains(point) } }
        let overPanel = mode != .collapsed && (panel?.frame.contains(point) ?? false)
        hoverChanged(overNotch || overPanel)
    }

    /// A click at the notch opens the full glance; a click anywhere else closes it.
    private func pointerClicked(at point: NSPoint) {
        if isOpen {
            if !(panel?.frame.contains(point) ?? false) { collapse() }
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              notchTriggerRect(on: screen).contains(point) else { return }
        activeScreen = screen
        pointerIsInside = true
        expand(sticky: false)
    }

    private func installMouseMonitors() {
        guard monitors.isEmpty else { return }
        // Event monitors run on the main thread; no Task hop per mouse event.
        let moved: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved(to: NSEvent.mouseLocation) } }
        let clicked: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerClicked(at: NSEvent.mouseLocation) } }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved),
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { moved($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: clicked),
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { clicked($0); return $0 },
        ].compactMap { $0 }
    }

    private func removeMouseMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func refreshTriggerRects() { triggerRects = NSScreen.screens.map { notchTriggerRect(on: $0) } }

    /// Exactly the physical notch — nothing beside it and nothing below it, so reaching for
    /// browser tabs or a window's title bar never opens the glance. Positioned from the
    /// screen frame (the notch is always centered) so it holds on any display arrangement.
    private func notchTriggerRect(on screen: NSScreen?) -> NSRect {
        guard let screen else { return NSRect(x: 0, y: 0, width: fallbackTriggerWidth, height: fallbackTriggerHeight) }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
            let width = right.minX - left.maxX
            let height = max(left.height, right.height)
            return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        }
        return NSRect(x: screen.frame.midX - fallbackTriggerWidth / 2, y: screen.frame.maxY - fallbackTriggerHeight, width: fallbackTriggerWidth, height: fallbackTriggerHeight)
    }

    /// Settles the glance's layout before it opens, so it appears at its final size.
    private func prepareGlance() {
        measureNotch()
        spotify.start(client: "notch")
        refreshRecent()
        if visibleParts.contains(.calendar) || NotchPreferences().parts.contains(.calendar) { CalendarGlance.shared.refresh() }
        if NotchPreferences().parts.contains(.weather) { Task { await WeatherGlance.shared.refresh() } }
    }

    private func measureNotch() {
        let screen = activeScreen ?? screenContainingMouse() ?? NSScreen.main
        activeScreen = screen
        if let screen, screen.safeAreaInsets.top > 0 {
            let rect = notchTriggerRect(on: screen)
            notchSize = CGSize(width: rect.width, height: rect.height)
        } else {
            notchSize = CGSize(width: 0, height: NSStatusBar.system.thickness)
        }
    }

    func refreshRecent() {
        guard recentEnabled else { recent = []; return }
        let folders = ProcessInfo.processInfo.environment["MOI_RECENT_DIRS"].map { $0.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) } } // synthetic folders for testing
        recent = RecentFiles.latest(in: folders ?? [RecentFiles.downloads, RecentFiles.screenshotFolder()], limit: 5)
    }

    func setRecentEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "moi.recentFiles")
        recentEnabled = on
        refreshRecent()
        layout()
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func attachedFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let frame = (activeScreen ?? screenContainingMouse() ?? panel?.screen ?? NSScreen.main)?.frame ?? .zero
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    private func installHotKey() {
        let shortcut = NotchPreferences().shortcut
        HotKeyCenter.shared.register(.notchGlance, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.toggleExpanded()
        }
    }

    func refreshHotKey() { installHotKey() }

    deinit {
        hoverDwellTask?.cancel()
        hoverExitTask?.cancel()
        monitors.forEach(NSEvent.removeMonitor)
    }
}
