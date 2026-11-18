import AppKit
import AVFoundation
import Foundation
import UserNotifications

enum MoiSound: String, CaseIterable {
    case summon
    case notification
    case success
    case attention

    var filename: String { "moi_\(rawValue)" }
}

/// Moi's single audio gateway. Short identity sounds use `NSSound`, which plays
/// asynchronously without keeping an audio engine alive between events.
@MainActor
final class MoiSoundController: NSObject, NSSoundDelegate {
    static let shared = MoiSoundController()

    private var playing: [MoiSound: NSSound] = [:]

    private override init() { super.init() }

    func play(_ event: MoiSound, settings: UserSettings) {
        guard settings.moiSoundsEnabled, settings.isSoundEnabled(event), playing[event] == nil,
              let url = resourceURL(for: event),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }

        sound.delegate = self
        playing[event] = sound
        if !sound.play() { playing[event] = nil }
    }

    func stopAll() {
        for sound in playing.values {
            sound.delegate = nil
            sound.stop()
        }
        playing.removeAll()
    }

    nonisolated static func notificationSound(for event: MoiSound, settings: UserSettings) -> UNNotificationSound? {
        guard settings.moiSoundsEnabled, settings.isSoundEnabled(event),
              Bundle.main.url(forResource: event.filename, withExtension: "wav") != nil else { return nil }
        return UNNotificationSound(named: UNNotificationSoundName("\(event.filename).wav"))
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        Task { @MainActor [weak self] in
            self?.playing = self?.playing.filter { $0.value !== sound } ?? [:]
        }
    }

    private func resourceURL(for event: MoiSound) -> URL? {
        let bundles = [Bundle.moi, Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(forResource: event.filename, withExtension: "wav", subdirectory: "Sounds") { return url }
            if let url = bundle.url(forResource: event.filename, withExtension: "wav") { return url }
        }
        return nil
    }

}

private extension UserSettings {
    func isSoundEnabled(_ sound: MoiSound) -> Bool {
        switch sound {
        case .summon: moiSummonSoundEnabled
        case .notification: moiNotificationSoundEnabled
        case .success: moiSuccessSoundEnabled
        case .attention: moiAttentionSoundEnabled
        }
    }
}

/// moi's little sound effects in the introduction: soft blips while a line types out, a boing on
/// each hop, a thud when it lands. Synthesised on the fly (no voice, no audio files). Off with the
/// intro's speaker button.
@MainActor
final class MoiChatter {
    static let shared = MoiChatter()
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "moi.chatterOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "moi.chatterOn") }
    }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var idle: Task<Void, Never>?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// One "syllable": a short, slightly random chirp, like a small creature talking.
    func blip() { play(tone(from: .random(in: 560...820), to: .random(in: 620...900), seconds: 0.045, volume: 0.10)) }
    /// A hop: a quick rising boing.
    func hop() { play(tone(from: 260, to: 640, seconds: 0.11, volume: 0.12)) }
    /// Landing: a soft low bump.
    func thud() { play(tone(from: 180, to: 90, seconds: 0.14, volume: 0.2)) }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard Self.enabled, let buffer else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
        // The engine sleeps two seconds after the last sound, so nothing keeps running.
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.player.stop(); self.engine.stop()
        }
    }

    /// A sine sweep with a fast attack and a gentle decay.
    private func tone(from f0: Double, to f1: Double, seconds: Double, volume: Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / Double(frames)
            phase += 2 * .pi * (f0 + (f1 - f0) * t) / format.sampleRate
            let envelope = min(1, t * 20) * pow(1 - t, 2)
            out[i] = Float(sin(phase) * envelope) * volume
        }
        return buffer
    }
}
