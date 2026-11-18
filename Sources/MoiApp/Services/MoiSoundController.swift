import AppKit
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
