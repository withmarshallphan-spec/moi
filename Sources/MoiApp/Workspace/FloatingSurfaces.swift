import SwiftUI
import AppKit

@MainActor
final class CommandPanelController {
    private let panel: NSPanel
    init(workspace: MoiWorkspace, store: AppStore) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 358, height: 380), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Ask moi"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CompanionActions(workspace: workspace) { [weak panel] in panel?.orderOut(nil) }.background(MoiStyle.background).environmentObject(store))
        panel.isMovableByWindowBackground = true
    }
    func toggle() {
        if panel.isVisible { panel.orderOut(nil); return }
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2 + 80)) }
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
}
struct CompanionView: View {
    @ObservedObject var workspace: MoiWorkspace
    @ObservedObject private var voice = VoiceService.shared
    @ObservedObject private var intelligence = Intelligence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var gaze: CompanionGaze
    @State private var dozing = false
    @State private var justWoke = false
    @State private var showActions = false
    var drag: (Bool) -> Void
    var state: MoiCharacterState {
        if justWoke { return .curious }
        if voice.recording { return .listening }
        if voice.speaking { return .speaking }
        if voice.preparing || intelligence.busy { return .working }
        if intelligence.error != nil || voice.error != nil { return .error }
        if !intelligence.reply.isEmpty { return .success }
        return dozing ? .sleeping : .idle
    }
    var body: some View {
        Button { NSApp.activate(ignoringOtherApps: true); showActions.toggle() } label: {
            MoiCharacter(state: state, size: workspace.companionSize, gaze: dozing ? .zero : gaze.vector, lively: workspace.animate, essential: true).padding(8)
        }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("moi, \(state.label). Show actions.")
            .help(dozing ? "moi is dozing. Click for things moi can do." : "Click for things moi can do · Drag to move · Right-click for controls")
            .popover(isPresented: $showActions, arrowEdge: .leading) { CompanionActions(workspace: workspace) { showActions = false } }
            .onAppear { if ProcessInfo.processInfo.environment["MOI_COMPANION_ACTIONS"] == "1" { showActions = true } } // development screenshots
            .simultaneousGesture(DragGesture().onChanged { _ in drag(false) }.onEnded { _ in drag(true) })
            .contextMenu {
                Button("Open moi") { workspace.showMain() }
                Button("Settings") { workspace.showMain(.settings) }
                Button("Hide Companion") { workspace.companionEnabled = false }
            }
            // Ignored for ten minutes, moi dozes off. Bringing the pointer near wakes it, a little startled.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if !dozing, Date().timeIntervalSince(gaze.lastNear) > 600 { dozing = true }
                }
            }
            .onChange(of: gaze.lastNear) { _, _ in
                guard dozing else { return }
                dozing = false; justWoke = true
                Task { try? await Task.sleep(for: .seconds(1.6)); justWoke = false }
            }
    }
}
/// What clicking moi offers: say anything (ask, or add "gym tomorrow 4:30pm"), and one-click
/// things to do to your Mac. Anything that needs review opens the main window.
struct CompanionActions: View {
    @ObservedObject var workspace: MoiWorkspace
    var close: () -> Void
    @ObservedObject private var intelligence = Intelligence.shared
    @State private var text = ""
    @FocusState private var typing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Ask or tell me: “gym tomorrow 4:30pm”", text: $text)
                    .textFieldStyle(.plain).font(MoiType.ui(14)).focused($typing)
                    .onSubmit(send)
                TalkButton(size: 24)
                if intelligence.busy { ProgressView().controlSize(.small) }
                else { Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)) }.buttonStyle(.plain).foregroundStyle(MoiStyle.accent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("Send") }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(MoiStyle.border))
            if !intelligence.reply.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(intelligence.reply).font(MoiType.ui(13.5)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let store = workspace.store {
                        if intelligence.pending != nil {
                            HStack {
                                Button(intelligence.pendingVerb) { intelligence.approvePending(store: store) }.buttonStyle(.moiPrimary)
                                Button("No") { intelligence.pending = nil }.buttonStyle(.moiGhost)
                            }
                        } else if intelligence.canUndo {
                            Button("Undo") { intelligence.undo(store: store) }.buttonStyle(.moiGhost)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 2) {
                row("Take a screenshot", "camera.viewfinder", "Opens the macOS screenshot bar") { NotchPanelView.openScreenshotApp() }
                row("Clean up my Desktop", "square.stack.3d.down.right", "Shows the files first. Nothing changes until you choose") { workspace.showMain(.clean); TidyStore.shared.preview() }
                row("Start focusing", "timer", "A timer, and moi steers you away from distracting apps") { workspace.showMain(.focus) }
                row("Open my plan", "calendar", "Tasks, deadlines and calendar") { workspace.showMain(.tasks) }
                row("Open moi", "macwindow", nil) { workspace.showMain() }
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { typing = true }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let store = workspace.store else { return }
        intelligence.draft = t; intelligence.respond(store: store); text = ""
    }

    private func row(_ title: String, _ symbol: String, _ detail: String?, run: @escaping () -> Void) -> some View {
        Button { close(); run() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 20).foregroundStyle(MoiStyle.quiet)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(MoiType.ui(13.5, weight: 560))
                    if let detail { Text(detail).font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
/// Where the pointer is relative to the companion: eyes follow it, and coming near counts as attention.
@MainActor
final class CompanionGaze: ObservableObject {
    @Published var vector: CGSize = .zero
    @Published var lastNear = Date()
    private var lastUpdate = Date.distantPast
    func pointer(_ mouse: NSPoint, center: NSPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) > 0.05 else { return } // ≤ 20 updates/s
        lastUpdate = now
        let dx = mouse.x - center.x, dy = mouse.y - center.y
        let next = CGSize(width: max(-1, min(1, dx / 320)), height: max(-1, min(1, -dy / 320)))
        if abs(next.width - vector.width) + abs(next.height - vector.height) > 0.04 { vector = next }
        if hypot(dx, dy) < 220, now.timeIntervalSince(lastNear) > 1 { lastNear = now }
    }
}
@MainActor
final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor
final class CompanionController {
    private let panel: NSPanel
    private weak var workspace: MoiWorkspace?
    /// Panel origin and pointer position (screen coordinates) when a drag began.
    private var dragStart: (origin: NSPoint, mouse: NSPoint)?
    private var screensObserver: NSObjectProtocol?
    private let gaze = CompanionGaze()
    private var pointerMonitors: [Any] = []
    init(workspace: MoiWorkspace) {
        self.workspace = workspace
        panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "moi Companion"
        panel.isExcludedFromWindowsMenu = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let moved: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.gaze.pointer(NSEvent.mouseLocation, center: NSPoint(x: self.panel.frame.midX, y: self.panel.frame.midY))
            }
        }
        pointerMonitors = [NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved), NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { moved($0); return $0 }].compactMap { $0 }
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sync() } }
    }
    func sync(reset: Bool = false) {
        guard let workspace else { return }
        guard workspace.companionEnabled else { NSApp.removeWindowsItem(panel); panel.orderOut(nil); panel.contentViewController = nil; return }
        if panel.contentViewController == nil {
            panel.contentViewController = NSHostingController(rootView: CompanionView(workspace: workspace, gaze: gaze) { [weak self] ended in self?.drag(ended: ended) })
        }
        let side = min(128, max(32, workspace.companionSize)) + 16
        panel.setContentSize(NSSize(width: side, height: side))
        let screens = NSScreen.screens
        let saved = UserDefaults.standard.string(forKey: "moi.companionPosition").map(NSPointFromString)
        let screen = saved.flatMap { point in screens.first { $0.visibleFrame.contains(point) } } ?? NSScreen.main ?? screens[0]
        let frame = screen.visibleFrame
        let origin = !reset ? saved : nil
        let point = origin ?? NSPoint(x: frame.maxX - side - 24, y: frame.maxY - side - 20)
        panel.setFrameOrigin(clamp(point, in: frame)); panel.orderFrontRegardless()
        NSApp.addWindowsItem(panel, title: "moi Companion", filename: false)
    }
    private func clamp(_ point: NSPoint, in frame: NSRect) -> NSPoint {
        var result = NSPoint(x: min(frame.maxX - panel.frame.width, max(frame.minX, point.x)), y: min(frame.maxY - panel.frame.height, max(frame.minY, point.y)))
        let reservedNotch = NSRect(x: frame.midX - 242, y: frame.maxY - 280, width: 484, height: 280)
        if NSRect(origin: result, size: panel.frame.size).intersects(reservedNotch) {
            if reservedNotch.maxX + 12 + panel.frame.width <= frame.maxX { result.x = reservedNotch.maxX + 12 }
            else { result.y = max(frame.minY, reservedNotch.minY - panel.frame.height - 12) }
        }
        return result
    }
    /// Uses screen-space mouse positions: a SwiftUI drag translation is measured inside the
    /// view, which moves with the panel, so it fed back into itself and jittered.
    private func drag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (panel.frame.origin, mouse) }
        guard let start = dragStart else { return }
        let point = NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
        guard let frame = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(clamp(point, in: frame))
        if ended { UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "moi.companionPosition"); dragStart = nil }
    }
}
