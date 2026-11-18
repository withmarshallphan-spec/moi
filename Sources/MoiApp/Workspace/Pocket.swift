import AppKit
import Carbon
import Combine
import SwiftUI

/// moi's Pocket: a slim bar that sticks on every desktop, on top. One line says what's happening;
/// click it and it opens into "ask or tell me" plus things moi can do. ⌃⌥H shows or hides it.
@MainActor
final class PocketController: NSObject, ObservableObject {
    @Published var expanded = false { didSet { resize() } }
    private var panel: NSPanel?
    private weak var store: AppStore?
    private weak var notch: NotchController?
    private var subscriptions: Set<AnyCancellable> = []
    static let width: CGFloat = 400

    func configure(store: AppStore, notch: NotchController) {
        guard panel == nil else { return }
        self.store = store; self.notch = notch
        let panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("MoiPocket2")
        panel.contentView = FirstMouseHostingView(rootView: PocketView(controller: self).environmentObject(store))
        if !panel.setFrameUsingName("MoiPocket2"), let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - Self.width - 24, y: screen.visibleFrame.minY + 24))
        }
        self.panel = panel
        HotKeyCenter.shared.register(.pocket, keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey)) { [weak self] in self?.toggle() }
        // Steps aside while the notch is open, so moi is never in two places at once.
        notch.$mode.receive(on: RunLoop.main).sink { [weak self] _ in self?.sync() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .moiPocketChanged).receive(on: RunLoop.main).sink { [weak self] _ in self?.sync() }.store(in: &subscriptions)
        sync()
    }

    var enabled: Bool { store?.data.settings.hudEnabled ?? true }
    func toggle() { store?.update { $0.settings.hudEnabled.toggle() }; sync() }
    func setEnabled(_ on: Bool) { store?.update { $0.settings.hudEnabled = on }; sync() }

    func sync() {
        guard let panel else { return }
        let wanted = enabled && notch?.isOpen != true
        if wanted, !panel.isVisible { panel.orderFrontRegardless() } else if !wanted, panel.isVisible { panel.orderOut(nil) }
    }

    /// Grows upward from where it sits, so the bar doesn't jump.
    private func resize() {
        guard let panel else { return }
        let height: CGFloat = expanded ? 470 : 52
        var frame = panel.frame
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? frame
        frame.size.height = height
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - height }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        panel.setFrame(frame, display: true)
        if expanded { NSApp.activate(ignoringOtherApps: true); panel.makeKey() }
    }
}

extension Notification.Name { static let moiPocketChanged = Notification.Name("MoiPocketChanged") }

struct PocketView: View {
    @ObservedObject var controller: PocketController
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var voice = VoiceService.shared
    @ObservedObject private var intelligence = Intelligence.shared
    var body: some View {
        VStack(spacing: 0) {
            if controller.expanded {
                CompanionActions(workspace: MoiWorkspace.shared) { controller.expanded = false }
                    .frame(maxHeight: .infinity, alignment: .top)
                Divider().opacity(0.4)
            }
            bar
        }
        .frame(width: PocketController.width)
        .background(MoiStyle.background.opacity(0.97), in: RoundedRectangle(cornerRadius: controller.expanded ? 18 : 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: controller.expanded ? 18 : 26, style: .continuous).stroke(MoiStyle.border))
        .environment(\.colorScheme, .dark)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var bar: some View {
        HStack(spacing: 10) {
            MoiCharacter(state: state, size: 30, pose: .peek, essential: true).frame(width: 34, height: 34).clipped()
            VStack(alignment: .leading, spacing: 1) {
                Text(line.0).font(MoiType.ui(13, weight: 600)).lineLimit(1)
                Text(line.1).font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet).lineLimit(1)
            }
            Spacer(minLength: 6)
            TalkButton(size: 30)
            Button { withAnimation(.easeOut(duration: 0.15)) { controller.expanded.toggle() } } label: {
                Image(systemName: controller.expanded ? "chevron.down" : "chevron.up").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 30).background(MoiStyle.surface, in: Circle())
            }
            .buttonStyle(.plain).help(controller.expanded ? "Close" : "Ask or tell moi something")
        }
        .padding(.horizontal, 10).frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { controller.expanded.toggle() } }
        .contextMenu {
            Button("Open moi") { MoiWorkspace.shared.showMain() }
            Button("Hide the Pocket  ⌃⌥H") { controller.setEnabled(false) }
        }
    }

    private var state: MoiCharacterState {
        if voice.recording { return .listening }
        if voice.speaking { return .speaking }
        if intelligence.busy { return .working }
        return .idle
    }

    /// What moi is saying right now: its last reply for a moment, else focus, the current block, or what's next.
    private var line: (String, String) {
        if voice.recording { return (voice.transcript.isEmpty ? "Listening…" : voice.transcript, "Pause when you're done") }
        if intelligence.busy { return ("Thinking…", intelligence.provider.name) }
        if let focus = store.activeFocus { return ("Focusing on \(focus.title)", ScheduleEngine.remainingText(until: focus.plannedEnd, from: store.now) + " left") }
        if case let .active(item, _) = ScheduleEngine.state(at: store.now, data: store.data, calendar: store.calendar) { return (item.title, ScheduleEngine.remainingText(until: item.end, from: store.now) + " left") }
        if let next = NextUpEngine.items(data: store.data, now: store.now, calendar: store.calendar, limit: 1).first { return (next.title, "Next" + (next.countdown.map { " · \($0)" } ?? "")) }
        return ("Ask or tell me anything", "“clean up my downloads”, “quit everything except Safari”")
    }
}
