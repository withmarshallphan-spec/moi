import AppKit
import Foundation

struct SpotifyPlaybackSnapshot: Sendable, Equatable {
    var trackID: String
    var title: String
    var artist: String
    var isPlaying: Bool
    var positionSeconds: Double
    var durationSeconds: Double
    var artworkURL: URL?
    var capturedAt: Date
    func interpolatedPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return positionSeconds }
        return min(durationSeconds, max(0, positionSeconds + date.timeIntervalSince(capturedAt)))
    }

    /// Builds a snapshot from the player's public distributed notification. Spotify sends
    /// `Duration` (ms) and `Playback Position` (s); Apple Music sends `Total Time` (ms) and no
    /// position, so position carries over from `previous` for the same track. Stopped → nil.
    static func from(notification info: [AnyHashable: Any], previous: SpotifyPlaybackSnapshot?, now: Date = Date()) -> SpotifyPlaybackSnapshot? {
        let state = info["Player State"] as? String ?? ""
        guard state == "Playing" || state == "Paused", let title = info["Name"] as? String else { return nil }
        let id = (info["Track ID"] as? String) ?? (info["PersistentID"].map { "\($0)" }) ?? title
        let durationMs = (info["Duration"] as? NSNumber ?? info["Total Time"] as? NSNumber)?.doubleValue ?? 0
        let sameTrack = previous?.trackID == id
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? (sameTrack ? previous?.interpolatedPosition(at: now) ?? 0 : 0)
        return SpotifyPlaybackSnapshot(trackID: id, title: title, artist: info["Artist"] as? String ?? "", isPlaying: state == "Playing",
                                       positionSeconds: position, durationSeconds: durationMs / 1000,
                                       artworkURL: sameTrack ? previous?.artworkURL : nil, capturedAt: now)
    }
}

/// One shared player adapter for the notch and the Music screen.
/// Track/state come from the player's own system-wide notifications (instant, no permission).
/// Controls, exact position and artwork use AppleScript, which needs macOS Automation consent.
@MainActor
final class SpotifyNowPlaying: ObservableObject {
    static let shared = SpotifyNowPlaying()
    nonisolated static var playerName: String { UserDefaults.standard.string(forKey: "moi.musicPlayer") ?? "Spotify" }
    nonisolated static var bundleID: String { playerName == "Apple Music" ? "com.apple.Music" : "com.spotify.client" }
    nonisolated static var connected: Bool { UserDefaults.standard.bool(forKey: "moi.musicConnected") }
    @Published private(set) var error: String?
    @Published private(set) var snapshot: SpotifyPlaybackSnapshot?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isRunning = SpotifyNowPlaying.playerIsRunning
    private var timer: Timer?
    private var clients: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var cachedArtworkTrackID: String?
    /// OSA is not safe to run concurrently; every script goes through this one queue.
    private nonisolated static let scriptQueue = DispatchQueue(label: "moi.music.applescript", qos: .utility)

    // Singleton: observers live as long as the app, so their tokens are never removed.
    private init() {
        let local = NotificationCenter.default, distributed = DistributedNotificationCenter.default(), apps = NSWorkspace.shared.notificationCenter
        _ = local.addObserver(forName: Notification.Name("MoiOfflineChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.artworkTask?.cancel(); self?.artwork = nil; self?.cachedArtworkTrackID = nil }
        }
        for (player, name) in [("Spotify", "com.spotify.client.PlaybackStateChanged"), ("Apple Music", "com.apple.Music.playerInfo")] {
            _ = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.receive(info, from: player) }
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            _ = apps.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { if id == Self.bundleID { self?.playerChanged() } }
            }
        }
    }

    /// Call when the selected player changes or launches/quits.
    func playerChanged() {
        isRunning = Self.playerIsRunning
        snapshot = nil; artwork = nil; cachedArtworkTrackID = nil; error = nil
        refresh()
    }

    private func receive(_ info: [AnyHashable: Any], from player: String) {
        guard player == Self.playerName else { return }
        isRunning = Self.playerIsRunning
        snapshot = SpotifyPlaybackSnapshot.from(notification: info, previous: snapshot)
        if snapshot == nil { artwork = nil; cachedArtworkTrackID = nil }
        refresh() // fills artwork URL / exact position when connected
    }

    /// Precise polling while something on screen shows the scrubber. Clients are named so
    /// repeated start/stop from one surface can't unbalance another.
    func start(client: String) {
        clients.insert(client)
        guard timer == nil, Self.connected else { refresh(); return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }
    func stop(client: String) {
        clients.remove(client)
        guard clients.isEmpty else { return }
        timer?.invalidate(); timer = nil
        refreshTask?.cancel(); refreshTask = nil
    }
    /// Explicit "let moi control music": connects, then a harmless read makes macOS ask once.
    func requestControl() {
        UserDefaults.standard.set(true, forKey: "moi.musicConnected")
        refresh()
    }
    func disconnect() {
        UserDefaults.standard.set(false, forKey: "moi.musicConnected")
        timer?.invalidate(); timer = nil
        artworkTask?.cancel(); artwork = nil; cachedArtworkTrackID = nil
    }

    func refresh() {
        isRunning = Self.playerIsRunning
        guard isRunning else { snapshot = nil; artwork = nil; cachedArtworkTrackID = nil; return }
        guard Self.connected else { return } // notifications still keep `snapshot` current
        refreshTask?.cancel()
        refreshTask = Task {
            let result = await Self.onScriptQueue { Result { try Self.readSnapshot() } }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let value): error = nil; snapshot = value; updateArtworkIfNeeded(for: value)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
    func playPause() { runCommand("playpause") }
    func nextTrack() { runCommand("next track") }
    func previousTrack() { runCommand("previous track") }
    func seek(toSeconds seconds: Double) {
        guard seconds.isFinite, seconds >= 0, seconds <= (snapshot?.durationSeconds ?? 0) else { return }
        runCommand("set player position to \(seconds)")
    }
    /// Pressing a control is explicit consent: it connects, and macOS shows its own Automation prompt once.
    private func runCommand(_ command: String) {
        guard Self.playerIsRunning else { error = "\(Self.playerName) isn't open."; return }
        if !Self.connected { UserDefaults.standard.set(true, forKey: "moi.musicConnected") }
        Task {
            let failure = await Self.onScriptQueue { Self.execute(command) }
            if let failure { self.error = failure } else { refresh() }
        }
    }
    nonisolated static var playerIsRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    private nonisolated static func onScriptQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in scriptQueue.async { continuation.resume(returning: work()) } }
    }
    private nonisolated static func execute(_ command: String) -> String? {
        var error: NSDictionary?
        let source = "with timeout of 5 seconds\n tell application id \"\(bundleID)\" to \(command)\nend timeout"
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { return Self.describe(error) }
        return result == nil ? "Music command could not be executed." : nil
    }
    private nonisolated static func describe(_ error: NSDictionary) -> String {
        // -1743: the user (or policy) declined Automation for this player.
        if (error["NSAppleScriptErrorNumber"] as? Int) == -1743 { return "macOS hasn't allowed moi to control \(playerName). Enable it in System Settings → Privacy & Security → Automation." }
        return error["NSAppleScriptErrorMessage"] as? String ?? "Music command failed."
    }
    private func updateArtworkIfNeeded(for snapshot: SpotifyPlaybackSnapshot?) {
        guard UserDefaults.standard.bool(forKey: "moi.artworkNetwork"), !(UserDefaults.standard.object(forKey: "moi.offline") as? Bool ?? true), let snapshot, let url = snapshot.artworkURL, url.scheme == "https" else {
            artworkTask?.cancel(); cachedArtworkTrackID = nil; artwork = nil; return
        }
        guard snapshot.trackID != cachedArtworkTrackID else { return }
        cachedArtworkTrackID = snapshot.trackID; artwork = nil
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 10_000_000, let image = NSImage(data: data),
                  !Task.isCancelled, self?.cachedArtworkTrackID == snapshot.trackID else { return }
            self?.artwork = image
        }
    }
    private nonisolated static func readSnapshot() throws -> SpotifyPlaybackSnapshot? {
        let duration = playerName == "Apple Music" ? "(round ((duration of current track) * 1000))" : "duration of current track"
        let artwork = playerName == "Apple Music" ? "\"\"" : "artwork url of current track"
        let source = """
        with timeout of 5 seconds
        tell application id "\(bundleID)"
            set playbackState to (player state as text)
            if playbackState is "stopped" then return "stopped"
            set trackTitle to name of current track
            set trackArtist to artist of current track
            set trackID to (id of current track as text)
            set trackDurationMs to \(duration)
            set trackPositionMs to (round ((player position) * 1000))
            set trackArtwork to \(artwork)
            if trackArtwork is missing value then set trackArtwork to ""
            return playbackState & linefeed & trackTitle & linefeed & trackArtist & linefeed & trackID & linefeed & (trackDurationMs as text) & linefeed & (trackPositionMs as text) & linefeed & trackArtwork
        end tell
        end timeout
        """
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { throw MoiError.message(error.map(describe) ?? "No current track.") }
        if output == "stopped" { return nil }
        let parts = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 7 else { throw MoiError.message("Player returned incomplete track information.") }
        return SpotifyPlaybackSnapshot(trackID: parts[3], title: parts[1], artist: parts[2], isPlaying: parts[0] == "playing", positionSeconds: (Double(parts[5]) ?? 0) / 1000, durationSeconds: (Double(parts[4]) ?? 0) / 1000, artworkURL: parts[6].isEmpty ? nil : URL(string: parts[6]), capturedAt: Date())
    }
}
