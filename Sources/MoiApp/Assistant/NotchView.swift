import AppKit
import SwiftUI

/// moi's home on the Mac. Collapsed it's invisible (exactly the hardware notch); on hover the
/// notch grows wings with moi peeking out and one short chip; on click it drops down into the
/// full glance. One continuous black shape with concave shoulders, so it reads as the notch
/// itself growing, never a separate panel underneath.
struct NotchPanelView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var controller: NotchController
    @ObservedObject var spotify: SpotifyNowPlaying
    @ObservedObject private var voice = VoiceService.shared
    @ObservedObject private var intelligence = Intelligence.shared
    @ObservedObject private var calendar = CalendarGlance.shared
    @ObservedObject private var weather = WeatherGlance.shared
    /// Apple's system font in the notch, so it sits naturally beside the menu bar. Redraws on change.
    @AppStorage("moi.notchSystemFont") private var systemFont = true
    @State private var dragPosition: Double?
    @State private var flash: MoiCharacterState?

    private var size: CGSize { NotchLayout.size(controller.mode, notch: controller.notchSize, parts: controller.visibleParts, showsNow: controller.showsNow, recentHeight: controller.recentHeight, nudge: controller.nudge != nil) }
    private var shape: NotchShape { NotchShape(shoulder: NotchLayout.shoulder, bottomRadius: controller.mode == .expanded ? 22 : controller.notchSize.height / 2.4) }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(MoiStyle.notch)
            content
                .padding(.horizontal, NotchLayout.shoulder)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8), value: controller.mode)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8), value: controller.showsPlayer)
        .onHover { controller.hoverChanged($0) }
        .onExitCommand { controller.collapse() }
        .contextMenu {
            Button("Edit the notch…") { MoiWorkspace.shared.showMain(); MoiWorkspace.shared.notchEditor = true }
            Button("Open my plan") { MoiWorkspace.shared.showMain(.tasks) }
            Button("Open moi") { MoiWorkspace.shared.showMain() }
        }
    }

    @ViewBuilder private var content: some View {
        switch controller.mode {
        case .collapsed: Color.clear
        case .live:
            liveWings
                .contentShape(Rectangle())
                .onTapGesture { controller.expand(sticky: false) }
                .transition(.opacity)
        case .peek:
            VStack(alignment: .leading, spacing: 0) {
                wings
                if let nudge = controller.nudge {
                    nudgeRow(nudge).frame(height: NotchLayout.nudge).padding(.horizontal, NotchLayout.pad - NotchLayout.shoulder).padding(.top, 8)
                } else if let first = controller.visibleParts.first {
                    part(first).padding(.horizontal, NotchLayout.pad - NotchLayout.shoulder).padding(.top, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if controller.nudge == nil { controller.expand(sticky: false) } }
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        case .expanded:
            VStack(alignment: .leading, spacing: 0) {
                wings
                expandedBody.padding(.horizontal, NotchLayout.pad - NotchLayout.shoulder).padding(.top, 8)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    /// moi offering to help with something it noticed.
    private func nudgeRow(_ nudge: Nudge) -> some View {
        HStack(spacing: 10) {
            Text(nudge.text).font(NotchFont.ui(13.5, weight: 600)).foregroundStyle(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button("Not now") { MoiNudges.shared.snooze(nudge); controller.collapse() }
                .buttonStyle(.plain).font(NotchFont.ui(12, weight: 560)).foregroundStyle(.white.opacity(0.6))
            Button { controller.collapse(); MoiNudges.shared.act(nudge) } label: {
                Text(nudge.action).font(NotchFont.ui(12.5, weight: 650)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7).background(MoiStyle.accent, in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Wings (notch height)

    /// The mini notch, like an iPhone playing music: the cover on the left, bars or a timer on the right.
    private var liveWings: some View {
        HStack(spacing: 0) {
            Group {
                if spotify.snapshot?.isPlaying == true, let artwork = spotify.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    MoiCharacter(state: moiState, size: controller.notchSize.height * 0.9, pose: .peek, dancing: spotify.snapshot?.isPlaying == true, essential: true)
                        .offset(y: controller.notchSize.height * 0.14)
                }
            }
            .frame(width: NotchLayout.liveWing, height: controller.notchSize.height).clipped()
            Spacer(minLength: controller.notchSize.width)
            rightChip.frame(width: NotchLayout.liveWing, height: controller.notchSize.height)
        }
        .padding(.horizontal, 2)
        .frame(height: controller.notchSize.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spotify.snapshot.map { "\($0.isPlaying ? "Playing" : "Paused") \($0.title) by \($0.artist)" } ?? "moi")
    }

    private var wings: some View {
        HStack(spacing: 0) {
            MoiCharacter(state: moiState, size: controller.notchSize.height * 1.08, pose: .peek, dancing: spotify.snapshot?.isPlaying == true, essential: true)
                .offset(y: controller.notchSize.height * 0.16) // peeking up from below the edge
                .frame(width: NotchLayout.wing, height: controller.notchSize.height, alignment: .center)
                .clipped()
                .help("moi")
            Spacer(minLength: controller.notchSize.width)
            rightChip.frame(width: NotchLayout.wing, height: controller.notchSize.height)
        }
        .frame(height: controller.notchSize.height)
    }

    @ViewBuilder private var rightChip: some View {
        if spotify.snapshot?.isPlaying == true {
            MusicBars(playing: !reduceMotion).frame(width: 22, height: 14)
        } else if let (text, color) = chip {
            Text(text).font(NotchFont.ui(12, weight: 600)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// The one most immediate fact, as short as possible.
    private var chip: (String, Color)? {
        if let focus = store.activeFocus { return (ScheduleEngine.remainingText(until: focus.plannedEnd, from: store.now), MoiStyle.accent) }
        if case let .active(item, _) = ScheduleEngine.state(at: store.now, data: store.data, calendar: store.calendar) { return (ScheduleEngine.remainingText(until: item.end, from: store.now), .white.opacity(0.85)) }
        guard let item = nextItem else { return nil }
        let color: Color = item.urgency == .overdue ? MoiStyle.coral : item.urgency == .today ? MoiStyle.butter : .white.opacity(0.7)
        return (item.countdown ?? "next", color)
    }

    // MARK: Expanded

    private var expandedBody: some View {
        let others = controller.visibleParts.filter { $0 != .music }
        let music = controller.visibleParts.contains(.music)
        return HStack(alignment: .top, spacing: NotchLayout.gap) {
            if music { part(.music).frame(width: others.isEmpty ? nil : 278) }
            if !others.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: NotchLayout.gap) { ForEach(others) { part($0) } }
                }.frame(width: music ? 276 : nil).frame(maxWidth: .infinity)
            }
            if controller.visibleParts.isEmpty {
                action("Ask moi", symbol: "sparkles") { MoiWorkspace.shared.showCommand() }
                Spacer()
                action("Open moi", symbol: "arrow.up.forward.app") { MoiWorkspace.shared.showMain() }
            }
        }
    }

    @ViewBuilder private func part(_ part: NotchPart) -> some View {
        switch part {
        case .music: player.frame(height: NotchLayout.player)
        case .files: recentStrip.frame(height: controller.recentHeight)
        case .tasks:
            VStack(spacing: 0) {
                if controller.showsNow { nowRow.frame(height: NotchLayout.now) }
                nextRow.frame(height: NotchLayout.next)
            }
        case .calendar: calendarRow.frame(height: NotchLayout.calendar)
        case .weather: weatherRow.frame(height: NotchLayout.weather)
        }
    }

    /// Like the iPhone calendar widget: weekday in red, the day big, then the next event.
    private var calendarRow: some View {
        HStack(spacing: 12) {
            VStack(spacing: -1) {
                Text(store.now.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(NotchFont.ui(9.5, weight: 700)).foregroundStyle(MoiStyle.coral)
                Text(store.now.formatted(.dateTime.day())).font(NotchFont.display(20, weight: 640)).foregroundStyle(.white).monospacedDigit()
            }
            .frame(width: 38, height: 40).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !calendar.allowed {
                Text("See your next event here").font(NotchFont.ui(13, weight: 560)).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 4)
                Button("Allow") { calendar.requestAccess() }.buttonStyle(.plain).font(NotchFont.ui(12, weight: 600)).foregroundStyle(MoiStyle.accent)
            } else if let event = calendar.next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(NotchFont.ui(13.5, weight: 560)).foregroundStyle(.white).lineLimit(1)
                    Text(event.allDay ? (Calendar.current.isDateInToday(event.start) ? "All day" : "Tomorrow, all day") : (Calendar.current.isDateInToday(event.start) ? "" : "Tomorrow ") + event.start.formattedTime(in: store.calendar.timeZone))
                        .font(NotchFont.ui(11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !event.allDay, event.start > store.now, event.start.timeIntervalSince(store.now) < 6 * 3600 { pill("in " + ScheduleEngine.remainingText(until: event.start, from: store.now), color: .white.opacity(0.75)) }
            } else {
                Text("No events today or tomorrow").font(NotchFont.ui(13, weight: 560)).foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
        }
    }

    private var weatherRow: some View {
        HStack(spacing: 12) {
            let uv = weather.uv ?? 0
            let color: Color = uv < 3 ? MoiStyle.mint : uv < 6 ? MoiStyle.butter : uv < 8 ? .orange : uv < 11 ? MoiStyle.coral : .purple
            Image(systemName: uv < 1 && weather.uv != nil ? "moon.stars.fill" : "sun.max.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(color).frame(width: 38)
            if let message = weather.message, weather.uv == nil {
                Text(message).font(NotchFont.ui(12.5, weight: 560)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                Spacer()
            } else if let value = weather.uv {
                VStack(alignment: .leading, spacing: 1) {
                    Text("UV \(Int(value.rounded())) · \(WeatherGlance.level(value))").font(NotchFont.ui(13.5, weight: 600)).foregroundStyle(.white)
                    Text([weather.uvMax.map { "Highest today \(Int($0.rounded()))" }, weather.city.isEmpty ? nil : weather.city].compactMap { $0 }.joined(separator: " · ")).font(NotchFont.ui(11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if value >= 3 { pill("Sunscreen", color: color) }
                if let t = weather.temperature { Text("\(Int(t.rounded()))°").font(NotchFont.display(17, weight: 620)).foregroundStyle(.white).monospacedDigit() }
            } else { ProgressView().controlSize(.small); Spacer() }
        }
    }

    private var nowRow: some View {
        let (title, trailing, color) = nowText
        return HStack(spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).frame(width: 22)
            Text(title).font(NotchFont.ui(13.5, weight: 560)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 8)
            if !trailing.isEmpty { pill(trailing, color: .white.opacity(0.75)) }
        }
        .accessibilityElement(children: .combine)
    }

    private var nowText: (String, String, Color) {
        if let focus = store.activeFocus { return ("Focusing on \(focus.title)", "\(ScheduleEngine.remainingText(until: focus.plannedEnd, from: store.now)) left", MoiStyle.accent) }
        switch ScheduleEngine.state(at: store.now, data: store.data, calendar: store.calendar) {
        case let .active(item, _): return (item.title, "\(ScheduleEngine.remainingText(until: item.end, from: store.now)) left", item.source.category.color)
        case let .gap(_, next), let .beforeDay(next):
            return ("Free right now", next.map { "\($0.title) · \($0.start.formattedTime(in: store.calendar.timeZone))" } ?? "", .white.opacity(0.35))
        case .afterDay: return ("Nothing else scheduled today", "", .white.opacity(0.35))
        }
    }

    @ViewBuilder private var nextRow: some View {
        HStack(spacing: 10) {
            if let item = nextItem {
                Button { complete(item) } label: {
                    Circle().stroke(item.urgency >= .today ? MoiStyle.butter : .white.opacity(0.55), lineWidth: 1.6).frame(width: 15, height: 15).frame(width: 22, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Mark done").accessibilityLabel("Mark \(item.title) done")
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(NotchFont.ui(13.5, weight: 560)).foregroundStyle(.white).lineLimit(1)
                    Text(item.detail + (item.minutes.map { " · ~\($0) min" } ?? "")).font(NotchFont.ui(11.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                .id(item.id).transition(.opacity)
                Spacer(minLength: 8)
                if let countdown = item.countdown { pill(countdown, color: item.urgency >= .today ? MoiStyle.butter : .white.opacity(0.7)) }
            } else {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(MoiStyle.mint).frame(width: 22)
                Text("Nothing waiting on you.").font(NotchFont.ui(13.5, weight: 560)).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: nextItem?.id)
    }

    private func action(_ title: String?, symbol: String, help: String? = nil, run: @escaping () -> Void) -> some View {
        Button { controller.collapse(); run() } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if let title { Text(title) }
            }
            .font(NotchFont.ui(12, weight: 580)).foregroundStyle(.white.opacity(0.88)).lineLimit(1).fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain).help(help ?? title ?? "").accessibilityLabel(help ?? title ?? "")
    }

    /// The macOS Screenshot tool (the ⇧⌘5 bar). It needs no permission for moi, and saves where
    /// you've told macOS to, so the picture then appears in the recent strip.
    static func openScreenshotApp() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Recent files

    @ViewBuilder private var recentStrip: some View {
        if !controller.recentEnabled {
            Button { controller.setRecentEnabled(true) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").frame(width: 22)
                    Text("Show my newest downloads and screenshots here").lineLimit(1)
                    Spacer(minLength: 4)
                    Text("Turn on").foregroundStyle(MoiStyle.accent)
                }
                .font(NotchFont.ui(12.5, weight: 560)).foregroundStyle(.white.opacity(0.75)).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("macOS will ask once for access to Downloads and Desktop")
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) { ForEach(controller.recent, id: \.self) { url in RecentTile(url: url) } }
            }.scrollIndicators(.hidden)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text).font(NotchFont.ui(11.5, weight: 600)).monospacedDigit().foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.08), in: Capsule())
    }

    // MARK: Music

    @ViewBuilder private var player: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Button { openPlayer() } label: { albumArt }.buttonStyle(.plain).accessibilityLabel("Open \(SpotifyNowPlaying.playerName)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(spotify.snapshot?.title ?? SpotifyNowPlaying.playerName).font(NotchFont.ui(14.5, weight: 620)).foregroundStyle(.white).lineLimit(2)
                    Text(spotify.snapshot?.artist ?? (spotify.isRunning ? "Choose a track" : "Not open")).font(NotchFont.ui(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let snapshot = spotify.snapshot, snapshot.durationSeconds > 0 { scrubber(snapshot) }
            HStack { Spacer(); transport; Spacer() }
            if let error = spotify.error { Text(error).font(NotchFont.ui(10.5)).foregroundStyle(MoiStyle.butter).lineLimit(1) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The cover, plain and straight, like Now Playing on an iPhone.
    private var albumArt: some View {
        ZStack {
            if let artwork = spotify.artwork { Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill) }
            else { MoiStyle.accent.opacity(0.18); Image(systemName: "music.note").font(.system(size: 18, weight: .semibold)).foregroundStyle(MoiStyle.accent) }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var transport: some View {
        let playing = spotify.snapshot?.isPlaying == true
        return HStack(spacing: 30) {
            round("backward.fill", label: "Previous track") { spotify.previousTrack() }
            round(playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play", prominent: true) { spotify.playPause() }
            round("forward.fill", label: "Next track") { spotify.nextTrack() }
        }
    }

    private func round(_ symbol: String, label: String, prominent: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            // Plain white symbols, like Now Playing on an iPhone.
            Image(systemName: symbol).font(.system(size: prominent ? 22 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.moiGhost).accessibilityLabel(label)
    }

    /// Dragging overrides the live position so the thumb doesn't jump; release commits the seek.
    private func scrubber(_ snapshot: SpotifyPlaybackSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = dragPosition ?? snapshot.interpolatedPosition(at: context.date)
            HStack(spacing: 6) {
                Text(Self.time(position)).font(NotchFont.ui(10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                GeometryReader { geometry in
                    let fraction = min(1, max(0, position / max(snapshot.durationSeconds, 1)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14)).frame(height: dragPosition == nil ? 4 : 6)
                        Capsule().fill(.white.opacity(0.85)).frame(width: max(4, geometry.size.width * fraction), height: dragPosition == nil ? 4 : 6)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragPosition = min(1, max(0, $0.location.x / geometry.size.width)) * snapshot.durationSeconds }
                        .onEnded { _ in if let value = dragPosition { spotify.seek(toSeconds: value) }; dragPosition = nil })
                }
                .frame(height: 14)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue(Self.time(position))
                .accessibilityAdjustableAction { direction in spotify.seek(toSeconds: max(0, position + (direction == .increment ? 10 : -10))) }
                Text("-" + Self.time(max(0, snapshot.durationSeconds - position))).font(NotchFont.ui(10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private static func time(_ seconds: Double) -> String { let t = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", t / 60, t % 60) }

    private func openPlayer() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyNowPlaying.bundleID) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }

    // MARK: moi

    private var nextItem: NextUpItem? { NextUpEngine.items(data: store.data, now: store.now, calendar: store.calendar, limit: 1).first }

    /// What moi is doing up here, from real state only.
    private var moiState: MoiCharacterState {
        if let flash { return flash }
        if voice.recording { return .listening }
        if voice.speaking { return .speaking }
        if intelligence.busy { return .working }
        if let item = nextItem, item.urgency >= .today { return .attention }
        if spotify.snapshot?.isPlaying == true { return .happy }
        if case .afterDay = ScheduleEngine.state(at: store.now, data: store.data, calendar: store.calendar), nextItem == nil, Calendar.current.component(.hour, from: store.now) >= 22 { return .sleeping }
        return .idle
    }

    private func complete(_ item: NextUpItem) {
        store.complete(item.target)
        flash = .success
        Task { try? await Task.sleep(for: .seconds(1.4)); flash = nil }
    }
}

/// Body with concave shoulders where it meets the top edge, so it continues the hardware notch.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat
    var animatableData: CGFloat { get { bottomRadius } set { bottomRadius = newValue } }
    func path(in rect: CGRect) -> Path {
        let s = shoulder, w = rect.width, h = rect.height
        let r = min(bottomRadius, (w - 2 * s) / 2, max(0, h - s))
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: s, y: s), control: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: s, y: h - r))
        p.addQuadCurve(to: CGPoint(x: s + r, y: h), control: CGPoint(x: s, y: h))
        p.addLine(to: CGPoint(x: w - s - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - s, y: h - r), control: CGPoint(x: w - s, y: h))
        p.addLine(to: CGPoint(x: w - s, y: s))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - s, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Four little bars that dance while music plays. 15 fps, and only while visible.
private struct MusicBars: View {
    var playing: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(MoiStyle.accent)
                        .frame(width: 3, height: playing ? 4 + 10 * abs(sin(t * (3.1 + Double(i) * 0.9) + Double(i))) : 6)
                }
            }
        }
        .accessibilityLabel("Music playing")
    }
}

/// One recent file: a real thumbnail, its name, drag it anywhere, click to open.
private struct RecentTile: View {
    let url: URL
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 4) {
            FileThumbnail(url: url, size: CGSize(width: 70, height: 46))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(hovering ? 0.5 : 0.12)))
            Text(url.lastPathComponent).font(NotchFont.ui(10.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).truncationMode(.middle).frame(width: 74)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL]) }
        }
        .help("\(url.lastPathComponent) — click to open, or drag it somewhere")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// The notch's type: Apple's system font by default (native beside the menu bar), or moi's own.
enum NotchFont {
    static var system: Bool { UserDefaults.standard.object(forKey: "moi.notchSystemFont") as? Bool ?? true }
    static func ui(_ size: CGFloat = 13, weight: CGFloat = 440) -> Font { system ? .system(size: size, weight: map(weight)) : MoiType.ui(size, weight: weight) }
    static func display(_ size: CGFloat, weight: CGFloat = 620) -> Font { system ? .system(size: size, weight: map(weight)) : MoiType.display(size, weight: weight) }
    private static func map(_ w: CGFloat) -> Font.Weight { w < 500 ? .regular : w < 590 ? .medium : w < 650 ? .semibold : .bold }
}
