import AppKit
import CoreAudio
import SwiftUI

/// Tap to talk to moi; tap again (or just pause) to send. Red while listening.
struct TalkButton: View {
    var size: CGFloat
    @ObservedObject private var voice = VoiceService.shared
    var body: some View {
        Button {
            if voice.recording { voice.finish() } else { Task { await voice.talk() } }
        } label: {
            Image(systemName: voice.recording ? "waveform" : "mic.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(voice.recording ? Color.white : Color.primary.opacity(0.8))
                .frame(width: size, height: size)
                .background(voice.recording ? MoiStyle.coral : MoiStyle.surface, in: Circle())
                .symbolEffect(.variableColor.iterative, isActive: voice.recording)
        }
        .buttonStyle(.plain)
        .help(voice.recording ? "Listening… pause or tap to send" : "Talk to moi")
        .accessibilityLabel(voice.recording ? "Stop listening and send" : "Talk to moi")
    }
}

/// Settings → Brain & voice: how moi listens and how it sounds.
/// Settings → Brain & voice: how moi listens. (moi only speaks in the introduction.)
struct VoiceSettingsSection: View {
    @ObservedObject private var voice = VoiceService.shared
    var body: some View {
        Section("Talking to moi") {
            LabeledContent("Microphone", value: voice.permission)
            TextField("Language", text: $voice.locale, prompt: Text("en-US")).onChange(of: voice.locale) { _, value in UserDefaults.standard.set(value, forKey: "moi.voiceLocale") }
            Picker("Input", selection: $voice.selectedInput) { Text("System default").tag(AudioDeviceID(0)); ForEach(voice.inputDevices) { Text($0.name).tag($0.id) } }
            Text("Tap the mic next to any “Ask” box, or hold ⌃⌥V (turn it on in General). Speech is recognised on this Mac; no recording is kept.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            ModuleMessage(text: voice.error)
        }
    }
}
