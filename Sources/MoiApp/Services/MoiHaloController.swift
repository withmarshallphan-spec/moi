import AppKit
import Combine
import QuartzCore
import SwiftUI

enum MoiHaloState: Equatable {
    case hidden
    case summon
    case responding
    case success
    case attention
}

final class MoiHaloPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MoiHaloController {
    static let shared = MoiHaloController()

    private weak var store: AppStore?
    private var panel: MoiHaloPanel?
    private var model: MoiHaloModel?
    private var flashTask: Task<Void, Never>?
    private var hideToken: UUID?
    private var observers: [NSObjectProtocol] = []
    private var voiceSubscription: AnyCancellable?

    private init() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in Task { @MainActor in MoiHaloController.shared.hide(animated: false) } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in Task { @MainActor in MoiHaloController.shared.hide(animated: false) } })
    }

    /// The halo means "moi is listening": it's up only while the mic is on, never while moi speaks.
    func configure(store: AppStore) {
        self.store = store
        voiceSubscription = VoiceService.shared.$recording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                guard let self else { return }
                guard recording else { self.hide(); return }
                if self.panel == nil { self.summon(on: NSScreen.main) }
                self.transition(to: .summon)
            }
    }

    func summon(on screen: NSScreen?) {
        guard let settings = store?.data.settings, settings.moiHaloEnabled,
              let screen = screen ?? NSScreen.main else { return }
        ensureOverlay(on: screen, settings: settings)
        transition(to: .summon)
    }

    func transition(to state: MoiHaloState) {
        guard state != .hidden else { hide(); return }
        guard let settings = store?.data.settings, settings.moiHaloEnabled, let model else { return }
        model.apply(state: state, settings: settings)
    }

    func signalSuccess() { flash(.success) }
    func signalAttention() { flash(.attention) }

    func refreshSettings() {
        guard let settings = store?.data.settings else { return }
        guard settings.moiHaloEnabled else { hide(); return }
        model?.apply(state: model?.state ?? .responding, settings: settings)
    }

    func hide(animated: Bool = true) {
        flashTask?.cancel()
        flashTask = nil
        guard let panel else { return }
        model?.state = .hidden // Pauses TimelineView before the fade begins.

        let token = UUID()
        hideToken = token
        let finish = { [weak self, weak panel] in
            guard let self, self.hideToken == token else { return }
            panel?.orderOut(nil)
            panel?.contentView = nil
            self.panel = nil
            self.model = nil
            self.hideToken = nil
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { Task { @MainActor in finish() } }
    }

    private func ensureOverlay(on screen: NSScreen, settings: UserSettings) {
        hideToken = nil
        if let panel, panel.screen === screen {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            model?.apply(state: .summon, settings: settings)
            return
        }
        hide(animated: false)

        let model = MoiHaloModel(settings: settings)
        let panel = MoiHaloPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: MoiHaloView(model: model))
        panel.setFrame(screen.frame, display: true)
        self.model = model
        self.panel = panel
        panel.orderFrontRegardless()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func flash(_ state: MoiHaloState) {
        guard model != nil else { return }
        flashTask?.cancel()
        transition(to: state)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(760))
            guard !Task.isCancelled else { return }
            self?.transition(to: .responding)
        }
    }
}

@MainActor
private final class MoiHaloModel: ObservableObject {
    @Published var state: MoiHaloState = .summon
    @Published var intensity: MoiHaloIntensity

    init(settings: UserSettings) {
        intensity = settings.moiHaloIntensity
    }

    func apply(state: MoiHaloState, settings: UserSettings) {
        intensity = settings.moiHaloIntensity
        self.state = state
    }

    var continuouslyAnimates: Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        return switch state {
        case .summon: true
        case .hidden, .responding, .success, .attention: false
        }
    }
}

private struct MoiHaloView: View {
    @ObservedObject var model: MoiHaloModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !model.continuouslyAnimates)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let motion = model.continuouslyAnimates ? time : 0
                let profile = HaloProfile(state: model.state, intensity: model.intensity)
                ZStack {
                    perimeter(colors: profile.baseColors, angle: 4 * sin(motion / 5.4), width: profile.coreWidth)
                        .blur(radius: profile.bloomRadius)
                        .opacity(profile.bloomOpacity)
                    perimeter(colors: profile.cyanLobe, angle: -18 + 7 * sin(motion / 4.6), width: profile.coreWidth * 1.55)
                        .blur(radius: profile.bloomRadius * 0.7)
                    perimeter(colors: profile.violetLobe, angle: 118 + 8 * sin(motion / 6.1 + 1.7), width: profile.coreWidth * 1.35)
                        .blur(radius: profile.bloomRadius * 0.64)
                    perimeter(colors: profile.pinkLobe, angle: 238 + 6 * sin(motion / 5.7 + 3.1), width: profile.coreWidth)
                        .blur(radius: profile.bloomRadius * 0.52)
                    perimeter(colors: profile.edgeColors, angle: 3 * sin(motion / 7.2), width: profile.coreWidth * 0.42)
                        .opacity(profile.edgeOpacity)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .drawingGroup(opaque: false, colorMode: .linear)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background(Color.clear)
    }

    private func perimeter(colors: [Color], angle: Double, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .inset(by: 2)
            .stroke(
                AngularGradient(
                    colors: colors,
                    center: .center,
                    startAngle: .degrees(angle),
                    endAngle: .degrees(angle + 360)
                ),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
    }
}

private struct HaloProfile {
    let coreWidth: CGFloat
    let bloomRadius: CGFloat
    let bloomOpacity: Double
    let edgeOpacity: Double
    let baseColors: [Color]
    let cyanLobe: [Color]
    let violetLobe: [Color]
    let pinkLobe: [Color]
    let edgeColors: [Color]

    init(state: MoiHaloState, intensity: MoiHaloIntensity) {
        let scale: CGFloat = switch intensity {
        case .subtle: 0.72
        case .standard: 1
        case .vivid: 1.28
        }
        let stateEnergy: CGFloat = switch state {
        case .hidden: 0
        case .summon: 1.12
        case .responding: 0.64
        case .success, .attention: 1.04
        }
        coreWidth = 9 * scale * stateEnergy
        bloomRadius = 13 * scale * stateEnergy
        bloomOpacity = Double(0.58 * scale)
        edgeOpacity = Double(min(0.95, 0.7 * scale))

        // moi's colours only: butter, honey, gold and blush. No cyan/violet "AI glow".
        let persimmon = Color(red: 1.0, green: 0.84, blue: 0.42)
        let ember = Color(red: 0.96, green: 0.70, blue: 0.27)
        let gold = Color(red: 1.0, green: 0.78, blue: 0.30)
        let blush = Color(red: 1.0, green: 0.68, blue: 0.62)
        let clear = Color.clear

        switch state {
        case .success: baseColors = [gold, persimmon, gold, blush, gold, persimmon, gold, gold]
        case .attention: baseColors = [persimmon, ember, persimmon, gold, persimmon, ember, persimmon, persimmon]
        default: baseColors = [persimmon, blush, ember, persimmon, gold, persimmon, blush, persimmon]
        }
        cyanLobe = [persimmon, blush, clear, clear, clear, clear, persimmon.opacity(0.25), persimmon]
        violetLobe = [clear, clear, gold, persimmon.opacity(0.7), clear, clear, clear, clear]
        pinkLobe = [clear, clear, clear, clear, blush, gold.opacity(0.65), clear, clear]
        edgeColors = [persimmon, blush, gold, persimmon, ember, persimmon, blush, persimmon]
    }
}
