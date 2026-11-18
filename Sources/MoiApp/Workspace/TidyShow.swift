import AppKit
import SwiftUI

/// moi's signature moment: it hops out of the notch, picks the files up off your desktop (the real
/// icons disappear as it does), and hops back. Icon positions come from Finder when macOS allows it;
/// otherwise moi follows the usual right-hand columns. With Reduce Motion it just tidies.
@MainActor
final class TidyShow: ObservableObject {
    static let shared = TidyShow()
    struct Flyer: Identifiable { let id = UUID(); var icon: NSImage; var from: CGPoint }
    @Published var moi = CGPoint.zero
    @Published var lift: CGFloat = 0
    @Published var flyers: [Flyer] = []
    @Published var landed = false
    @Published var bubble = ""
    @Published var mood: MoiCharacterState = .happy
    @Published var opacity = 0.0
    /// The photo moi is carrying up to hang as the wallpaper, and whether it's grown to fill the screen.
    @Published var picture: NSImage?
    @Published var pictureFull = false
    @Published var screenSize = CGSize.zero
    private var panel: NSPanel?

    struct Outcome { var record: DesktopTidy.Record?; var failures: [String] = []; var quit: [MacControl.OpenApp] = []; var waiting: [MacControl.OpenApp] = [] }

    /// Quits the apps (moi hops to each window as it goes) and moves the files (moi picks them up
    /// as they move). One record for the files, so Put back undoes them all.
    func run(files plan: DesktopTidy.Plan?, apps: [MacControl.OpenApp]) async -> Outcome {
        var outcome = Outcome()
        let plan = plan.flatMap { $0.moves.isEmpty ? nil : $0 }
        guard let screen = NSScreen.screens.first, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            _ = MacControl.quit(apps); await settle(apps, into: &outcome)
            if let plan { let r = DesktopTidy.apply(plan); outcome.record = r.record; outcome.failures = r.failures }
            return outcome
        }
        let size = screen.frame.size
        let home = CGPoint(x: size.width / 2, y: 18)
        let hidden = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
        hidden.forEach { $0.orderOut(nil) } // moi's own window would hide the desktop
        show(on: screen)
        moi = home; lift = 0; flyers = []; mood = .happy
        bubble = "Tidy time!"
        withAnimation(.easeOut(duration: 0.25)) { opacity = 1 }
        MoiChatter.shared.blip(); try? await Task.sleep(for: .seconds(0.8))
        bubble = ""
        // Apps: moi visits each window and asks the app to quit.
        if !apps.isEmpty {
            let windows = Self.windowSpots(size: size)
            let visits = apps.filter { windows[$0.id] != nil }.sorted { (windows[$0.id]?.x ?? 0) > (windows[$1.id]?.x ?? 0) }.prefix(8)
            for app in visits {
                await hop(to: windows[app.id]!)
                mood = .working; bubble = "Bye, \(app.name)!"
                _ = MacControl.quit([app]); MoiChatter.shared.blip()
                try? await Task.sleep(for: .milliseconds(420))
            }
            bubble = ""
            let rest = apps.filter { app in !visits.contains { $0.id == app.id } }
            if !rest.isEmpty { _ = MacControl.quit(rest) }
            await settle(apps, into: &outcome)
        }
        // Files: moi picks them up off the desktop as they move.
        if let plan {
            let positions = Self.iconPositions(for: plan.moves.map(\.from), screen: size)
            var done: [DesktopTidy.Move] = []
            for stop in Self.stops(plan.moves, positions: positions) {
                await hop(to: stop.point)
                mood = .working
                flyers = stop.moves.prefix(8).map { Flyer(icon: NSWorkspace.shared.icon(forFile: $0.from), from: positions[$0.from] ?? stop.point) }
                landed = false
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeIn(duration: 0.32)) { landed = true }
                let result = DesktopTidy.apply(DesktopTidy.Plan(folder: plan.folder, moves: stop.moves, left: []))
                done += result.record.moves; outcome.failures += result.failures
                MoiChatter.shared.blip()
                try? await Task.sleep(for: .milliseconds(380))
                flyers = []
            }
            outcome.record = DesktopTidy.Record(date: Date(), folder: plan.folder.path, moves: done)
        }
        mood = .success
        let files = outcome.record?.moves.count ?? 0, closed = outcome.quit.count
        bubble = "All tidy!" + (files > 0 ? " \(files) \(files == 1 ? "file" : "files") sorted" : "") + (closed > 0 ? (files > 0 ? ", " : " ") + "\(closed) \(closed == 1 ? "app" : "apps") closed" : "") + "."
        MoiChatter.shared.blip()
        try? await Task.sleep(for: .seconds(1.6))
        bubble = ""
        await hop(to: home)
        withAnimation(.easeIn(duration: 0.3)) { opacity = 0 }
        try? await Task.sleep(for: .milliseconds(320))
        panel?.orderOut(nil); panel = nil
        hidden.forEach { $0.orderFront(nil) }
        return outcome
    }

    /// Waits up to three seconds for the apps to close, then notes which did (the rest are asking to save).
    private func settle(_ apps: [MacControl.OpenApp], into outcome: inout Outcome) async {
        func gone(_ app: MacControl.OpenApp) -> Bool { NSRunningApplication(processIdentifier: app.id)?.isTerminated ?? true }
        for _ in 0..<12 where !apps.allSatisfy(gone) { try? await Task.sleep(for: .milliseconds(250)) }
        outcome.quit = apps.filter(gone)
        outcome.waiting = apps.filter { !gone($0) }
    }

    /// The top middle of each app's biggest window (top-left coordinates, like the overlay).
    /// Window positions need no permission; window titles aren't read.
    static func windowSpots(size: CGSize) -> [pid_t: CGPoint] {
        var best: [pid_t: CGRect] = [:]
        for w in (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []) where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = Optional(CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)), rect.width > 120, rect.height > 80 else { continue }
            if rect.width * rect.height > (best[pid].map { $0.width * $0.height } ?? 0) { best[pid] = rect }
        }
        return best.mapValues { CGPoint(x: min(max($0.midX, 60), size.width - 60), y: min(max($0.minY + 40, 60), size.height - 60)) }
    }

    /// moi carries the photo up from the bottom and hangs it: the picture grows to fill the screen
    /// just as it becomes the wallpaper. `apply` does the real change.
    func hang(_ image: NSImage?, apply: () async throws -> Void) async throws {
        guard let image, let screen = NSScreen.screens.first, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { try await apply(); return }
        let size = screen.frame.size
        let hidden = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
        hidden.forEach { $0.orderOut(nil) }
        show(on: screen)
        screenSize = size; picture = image; pictureFull = false
        moi = CGPoint(x: size.width / 2, y: size.height + 60); lift = 0; mood = .happy; bubble = ""
        withAnimation(.easeOut(duration: 0.2)) { opacity = 1 }
        await hop(to: CGPoint(x: size.width / 2, y: size.height * 0.55))
        bubble = "This one!"; MoiChatter.shared.blip()
        try? await Task.sleep(for: .milliseconds(700))
        bubble = ""
        withAnimation(.easeInOut(duration: 0.6)) { pictureFull = true }
        defer { panel?.orderOut(nil); panel = nil; picture = nil; hidden.forEach { $0.orderFront(nil) } }
        try await apply()
        try? await Task.sleep(for: .milliseconds(650))
        mood = .success
        withAnimation(.easeIn(duration: 0.5)) { picture = nil }
        await hop(to: CGPoint(x: size.width / 2, y: 18))
        withAnimation(.easeIn(duration: 0.3)) { opacity = 0 }
        try? await Task.sleep(for: .milliseconds(320))
    }

    /// Big quick hops, with a boing each.
    private func hop(to target: CGPoint) async {
        let distance = hypot(target.x - moi.x, target.y - moi.y)
        let hops = max(1, Int(distance / 230))
        let step = CGPoint(x: (target.x - moi.x) / CGFloat(hops), y: (target.y - moi.y) / CGFloat(hops))
        for _ in 0..<hops {
            MoiChatter.shared.hop()
            withAnimation(.easeOut(duration: 0.12)) { moi.x += step.x / 2; moi.y += step.y / 2; lift = -34 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeIn(duration: 0.12)) { moi.x += step.x / 2; moi.y += step.y / 2; lift = 0 }
            try? await Task.sleep(for: .milliseconds(130))
        }
        moi = target
    }

    private func show(on screen: NSScreen) {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TidyShowView(show: self))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    // MARK: Where the icons are

    /// Finder knows where each desktop icon sits (top-left origin, like the overlay). macOS asks once
    /// before moi may ask Finder; without it, icons are assumed in the usual columns from the top right.
    static func iconPositions(for paths: [String], screen: CGSize) -> [String: CGPoint] {
        var found: [String: CGPoint] = [:]
        let script = """
        tell application "Finder"
            set out to ""
            repeat with f in (get items of desktop)
                try
                    set p to desktop position of f
                    set out to out & (POSIX path of (f as alias)) & tab & (item 1 of p) & tab & (item 2 of p) & linefeed
                end try
            end repeat
            return out
        end tell
        """
        var error: NSDictionary?
        let synthetic = ProcessInfo.processInfo.environment["MOI_TIDY_DESKTOP"] != nil // tests: no Finder, made-up files
        if !synthetic, let text = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "\t").map(String.init)
                guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { continue }
                found[parts[0].hasSuffix("/") ? String(parts[0].dropLast()) : parts[0]] = CGPoint(x: x, y: y + 20)
            }
        }
        let rows = max(1, Int((screen.height - 120) / 100))
        for (i, path) in paths.enumerated() where found[path] == nil {
            found[path] = CGPoint(x: screen.width - 70 - CGFloat(i / rows) * 100, y: 90 + CGFloat(i % rows) * 100)
        }
        return found
    }

    /// Files near each other become one stop (at most eight), visited in a sweep from the top right.
    static func stops(_ moves: [DesktopTidy.Move], positions: [String: CGPoint]) -> [(point: CGPoint, moves: [DesktopTidy.Move])] {
        let cells = Dictionary(grouping: moves) { move -> String in
            let p = positions[move.from] ?? .zero
            return "\(Int(p.x / 260)),\(Int(p.y / 260))"
        }
        var stops = cells.values.map { group -> (point: CGPoint, moves: [DesktopTidy.Move]) in
            let points = group.compactMap { positions[$0.from] }
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(max(1, points.count)), y: points.map(\.y).reduce(0, +) / CGFloat(max(1, points.count)))
            return (center, group)
        }.sorted { ($0.point.x, -$0.point.y) > ($1.point.x, -$1.point.y) }
        while stops.count > 8 { // ponytail: merges the two last stops; a smarter clustering only matters for huge desktops
            let last = stops.removeLast()
            stops[stops.count - 1].moves += last.moves
        }
        return stops
    }
}

private struct TidyShowView: View {
    @ObservedObject var show: TidyShow
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let picture = show.picture {
                // Carried above moi's head, then filling the screen.
                Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: show.pictureFull ? show.screenSize.width : 150, height: show.pictureFull ? show.screenSize.height : 100)
                    .clipShape(RoundedRectangle(cornerRadius: show.pictureFull ? 0 : 10, style: .continuous))
                    .shadow(color: .black.opacity(show.pictureFull ? 0 : 0.35), radius: 8, y: 4)
                    .position(show.pictureFull ? CGPoint(x: show.screenSize.width / 2, y: show.screenSize.height / 2) : CGPoint(x: show.moi.x, y: show.moi.y - 90 + show.lift))
                    .transition(.opacity)
            }
            ForEach(show.flyers) { flyer in
                Image(nsImage: flyer.icon).resizable().frame(width: 56, height: 56)
                    .scaleEffect(show.landed ? 0.15 : 1)
                    .opacity(show.landed ? 0 : 1)
                    .position(show.landed ? show.moi : flyer.from)
            }
            MoiCharacter(state: show.mood, size: 74, sticker: true, essential: true)
                .offset(y: show.lift)
                .position(show.moi)
            if !show.bubble.isEmpty {
                Text(show.bubble).font(MoiType.display(15, weight: 640)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.black.opacity(0.82), in: Capsule())
                    .position(x: show.moi.x, y: show.moi.y + 66)
                    .transition(.opacity)
            }
        }
        .opacity(show.opacity)
        .allowsHitTesting(false)
    }
}
