import AppKit
import AVFoundation
import Speech
import CoreAudio
import AudioToolbox

struct MoiAudioDevice: Identifiable { var id: AudioDeviceID; var name: String }
@MainActor
final class VoiceService: NSObject, ObservableObject {
    static let shared = VoiceService()
    @Published private(set) var recording = false
    @Published private(set) var speaking = false
    @Published private(set) var preparing = false
    @Published var transcript = ""
    @Published var error: String?
    @Published var locale = UserDefaults.standard.string(forKey: "moi.voiceLocale") ?? Locale.current.identifier
    @Published var selectedInput: AudioDeviceID = 0
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var finishTimeout: Task<Void, Never>?
    /// Talk mode: what's heard goes straight to moi, which answers in the chat.
    private var talking = false
    private var silenceWatch: Task<Void, Never>?
    override init() { super.init() }
    var permission: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "Microphone allowed"
        case .denied, .restricted: "Microphone denied — review System Settings"
        default: "Microphone not requested"
        }
    }
    var inputDevices: [MoiAudioDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { id in
            var streamAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var count = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &count, &name) == noErr else { return nil }
            return MoiAudioDevice(id: id, name: name?.takeRetainedValue() as String? ?? "Audio input")
        }
    }
    func start() async {
        guard !recording, !preparing else { return }
        cancel(); preparing = true; error = nil
        let id = generation
        defer { if generation == id { preparing = false } }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == id else { return }
        guard mic else { error = "Microphone access denied. Text input still works."; return }
        let authorization = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == id else { return }
        guard authorization == .authorized else { error = "Speech recognition permission denied."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "Offline recognition is unavailable for this locale/device. Select an installed supported locale or use text. Audio was not uploaded."; return
        }
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            if selectedInput != 0, let unit = input.audioUnit {
                var device = selectedInput
                guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else { throw MoiError.message("Input device unavailable. Select System Default.") }
            }
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MoiError.message("The input device has no usable audio stream.") }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            self.engine = engine; self.request = request; transcript = ""
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == id else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil {
                        self.stopCapture(); self.recognition = nil; self.finishTimeout?.cancel(); self.silenceWatch?.cancel()
                        let heard = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if self.talking { self.talking = false; if !heard.isEmpty { Intelligence.shared.heard(heard); return } }
                        if let error { self.error = error.localizedDescription }
                    }
                }
            }
            engine.prepare(); try engine.start(); recording = true
        } catch { self.error = error.localizedDescription; stopCapture(); recognition?.cancel(); recognition = nil }
    }
    private func stopCapture() {
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil; recording = false
        request?.endAudio(); request = nil
    }
    /// Tap to talk: listen, stop by itself after a short pause, then hand it to moi.
    func talk() async {
        talking = true
        await start()
        guard recording else { talking = false; return }
        let id = generation
        silenceWatch?.cancel()
        silenceWatch = Task {
            var last = "", quietSince = Date()
            while !Task.isCancelled, generation == id, recording {
                try? await Task.sleep(for: .milliseconds(250))
                if transcript != last { last = transcript; quietSince = Date() }
                else if !last.isEmpty, Date().timeIntervalSince(quietSince) > 1.4 { finish(); return }
                else if last.isEmpty, Date().timeIntervalSince(quietSince) > 8 { cancel(); return }
            }
        }
    }

    func finish() {
        if preparing { cancel(); return }
        stopCapture()
        let id = generation
        finishTimeout?.cancel()
        finishTimeout = Task { try? await Task.sleep(for: .seconds(4)); guard !Task.isCancelled, generation == id else { return }; recognition?.cancel(); recognition = nil }
    }
    func cancel() {
        generation = UUID(); preparing = false; talking = false; silenceWatch?.cancel(); stopCapture()
        recognition?.cancel(); recognition = nil; finishTimeout?.cancel(); finishTimeout = nil
        speaking = false
    }
}
