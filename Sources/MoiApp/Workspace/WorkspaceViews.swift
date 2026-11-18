import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import Photos
import Speech
import UserNotifications

struct WorkspaceOverview: View {
    @EnvironmentObject private var workspace: MoiWorkspace
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var intelligence = Intelligence.shared
    @State private var ask = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MoiVoice.greeting(at: store.now)).font(MoiType.display(36, weight: 680))
                        Text(DayAnswers.summaryLine(data: store.data, now: store.now, calendar: store.calendar)).font(MoiType.ui(16)).foregroundStyle(MoiStyle.quiet)
                    }
                    Spacer()
                }
                askBox
                if store.isReadOnly { ModuleMessage(text: "Your data is in read-only recovery mode, so nothing gets overwritten. \(store.persistenceError ?? "")") }
                ModuleMessage(text: workspace.shortcutError)
                HStack(alignment: .top, spacing: 16) {
                    Card(fillHeight: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Right now").font(MoiType.display(17, weight: 640))
                            CurrentBlockCard(compact: true)
                            Divider()
                            Text("Up next").font(MoiType.display(17, weight: 640))
                            let items = NextUpEngine.items(data: store.data, now: store.now, calendar: store.calendar, limit: 4)
                            if items.isEmpty { Text(MoiVoice.noTasks).font(MoiType.ui(13.5)).foregroundStyle(MoiStyle.quiet) }
                            ForEach(items) { NextUpRow(item: $0, compact: true) }
                            Button("Add a task") { store.quickAddPresented = true }.buttonStyle(.moiSecondary)
                        }
                    }
                    VStack(spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Coming up").font(MoiType.display(17, weight: 640))
                                let deadlines = DeadlineEngine.upcoming(from: store.data, now: store.now).prefix(3)
                                if deadlines.isEmpty { Text(MoiVoice.noDeadlines).font(MoiType.ui(13.5)).foregroundStyle(MoiStyle.quiet) }
                                ForEach(Array(deadlines)) { DeadlineRow(deadline: $0) }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Shortcuts").font(MoiType.display(17, weight: 640))
                                shortcut("Ask moi from anywhere", workspace.shortcut.rawValue) { workspace.showCommand() }
                                shortcut("Talk to moi", "Hold ⌃⌥V") { workspace.showMain(.settings) }
                                shortcut("Add a task", "⇧⌘N") { store.quickAddPresented = true }
                                shortcut("Show or hide the Pocket", "⌃⌥H") { workspace.showMain(.settings) }
                            }
                        }
                    }.frame(maxWidth: 360)
                }
                if MoiPaths.isDevelopment { Text("Development build · separate data from your installed moi.").font(MoiType.small).foregroundStyle(MoiStyle.quiet) }
            }
            .padding(32)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Ask moi right from Home. Same path as everywhere else: records first, then typed commands, then a model if one is chosen.
    private var askBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble").foregroundStyle(MoiStyle.accent)
                TextField("Ask or tell me: “what's tomorrow?”, “gym tomorrow 16:30”, “move it to 5pm”", text: $ask)
                    .textFieldStyle(.plain).font(MoiType.ui(15))
                    .onSubmit { guard !ask.trimmingCharacters(in: .whitespaces).isEmpty else { return }; intelligence.draft = ask; intelligence.respond(store: store); ask = "" }
                if intelligence.busy { ProgressView().controlSize(.small) }
                TalkButton(size: 30)
            }
            .padding(14)
            .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MoiStyle.border))
            if !intelligence.reply.isEmpty || intelligence.error != nil {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(intelligence.error ?? intelligence.reply).font(MoiType.ui(14)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if !intelligence.replySource.isEmpty { Text(intelligence.replySource).font(MoiType.small).foregroundStyle(MoiStyle.quiet) }
                    }
                    Spacer()
                    Button { intelligence.reply = ""; intelligence.replySource = ""; intelligence.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.moiGhost).accessibilityLabel("Dismiss reply")
                }
                .padding(14)
                .background(MoiStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func shortcut(_ title: String, _ keys: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack { Text(title).font(MoiType.ui(13.5)); Spacer(); Text(keys).font(MoiType.ui(12, weight: 560)).foregroundStyle(MoiStyle.quiet) }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.title2.weight(.semibold).monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) } }
}
struct WorkspaceSettingsView: View {
    @EnvironmentObject private var workspace: MoiWorkspace
    @EnvironmentObject private var store: AppStore
    @ObservedObject var notch: NotchController
    @ObservedObject private var intelligence = Intelligence.shared
    @ObservedObject private var voice = VoiceService.shared
    @ObservedObject private var player = SpotifyNowPlaying.shared
    @AppStorage("moi.offline") private var offline = true
    @AppStorage("moi.sharePlan") private var sharePlan = false
    @AppStorage("moi.ollamaURL") private var ollamaURL = "http://127.0.0.1:11434"
    @AppStorage("moi.cloudURL") private var cloudURL = "https://openrouter.ai/api/v1"
    @AppStorage("moi.voiceShortcutEnabled") private var talkShortcut = false
    @AppStorage("moi.musicPlayer") private var musicPlayer = "Spotify"
    @AppStorage("moi.artworkNetwork") private var artwork = false
    @State private var key = ""
    @State private var keyMessage = ""
    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "slider.horizontal.3") }
            brainAndVoice.tabItem { Label("Brain & voice", systemImage: "brain") }
            music.tabItem { Label("Music", systemImage: "music.note") }
            SettingsView(notch: notch).tabItem { Label("Plan & reminders", systemImage: "calendar") }
            privacy.tabItem { Label("Privacy & data", systemImage: "lock") }
        }.padding(16).navigationTitle("Settings")
    }

    private var general: some View {
        Form {
            Section("moi") {
                Toggle("Show moi around the app", isOn: Binding(get: { UserDefaults.standard.object(forKey: "moi.showCharacter") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "moi.showCharacter") }))
                HStack { Text("moi's colour"); Spacer(); MoiColorPicker() }
                Picker("Appearance", selection: $workspace.theme) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0) } }
            }
            Section("The notch") {
                Button("Edit the notch…") { workspace.notchEditor = true }
                Text("Choose its parts (music, now & next, calendar, UV, recent files), the mini notch while music plays, and the font.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
            Section("moi on your desktop") {
                Toggle("Show the Pocket (⌃⌥H): the sticky bar to ask or tell moi anything", isOn: Binding(get: { store.data.settings.hudEnabled }, set: { on in store.update { $0.settings.hudEnabled = on }; NotificationCenter.default.post(name: .moiPocketChanged, object: nil) }))
                Toggle("Also show moi as a little character", isOn: $workspace.companionEnabled)
                Slider(value: $workspace.companionSize, in: 32...112, step: 4) { Text("Size") }
                Toggle("Blink and look around", isOn: $workspace.animate)
                Button("Put it back in the top corner") { workspace.resetCompanionPosition() }
            }
            Section("Shortcuts") {
                Picker("Ask moi from anywhere", selection: $workspace.shortcut) { ForEach(CommandShortcut.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Hold ⌃⌥V to talk to moi", isOn: $talkShortcut).onChange(of: talkShortcut) { _, _ in workspace.configureHotkeys() }
                ModuleMessage(text: workspace.shortcutError)
            }
            Section("Introduction") { Button("Open the Guide") { store.selectedSection = .guide } }
        }.formStyle(.grouped)
    }

    private var brainAndVoice: some View {
        Form {
                Section("moi's brain") {
                    Picker("Think with", selection: $intelligence.providerID) {
                        Section("On this Mac") { ForEach(AIProvider.all.filter(\.local)) { Text($0.name).tag($0.id) } }
                        Section("Cloud · your own key") { ForEach(AIProvider.all.filter { !$0.local }) { Text($0.name).tag($0.id) } }
                    }
                    .onChange(of: intelligence.providerID) { _, _ in key = ""; keyMessage = ""; intelligence.models = [] }
                    let provider = intelligence.provider
                    switch provider.kind {
                    case .none: Text("moi answers from your records and does what you type. No model is used.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                    case .apple: Text(intelligence.appleAvailability).font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                    default:
                        if provider.id == "ollama" { TextField("Ollama address", text: $ollamaURL) }
                        if provider.id == "custom" { TextField("API address (HTTPS)", text: $cloudURL) }
                        if provider.needsKey {
                            HStack {
                                SecureField(CredentialStore.get(provider.keyAccount).isEmpty ? "Paste your \(provider.name) key" : "Key saved ✓ (paste to replace)", text: $key)
                                Button("Save") { do { try CredentialStore.set(key, account: provider.keyAccount); key = ""; keyMessage = "Saved in your Keychain." } catch { keyMessage = error.localizedDescription } }.disabled(key.isEmpty)
                                Button("Remove") { do { try CredentialStore.set("", account: provider.keyAccount); keyMessage = "Key removed." } catch { keyMessage = error.localizedDescription } }
                            }
                            if !provider.keyHint.isEmpty { Text("Get a key at \(provider.keyHint). Your key, your account: moi never uses anyone else's.").font(MoiType.small).foregroundStyle(MoiStyle.quiet) }
                            if !keyMessage.isEmpty { Text(keyMessage).font(MoiType.small) }
                        }
                        HStack {
                            TextField("Model", text: Binding(get: { provider.model }, set: { provider.model = $0; intelligence.objectWillChange.send() }))
                            Button("Find models") { intelligence.refreshModels() }
                        }
                        if !intelligence.models.isEmpty {
                            Picker("Available models", selection: Binding(get: { provider.model }, set: { provider.model = $0; intelligence.objectWillChange.send() })) {
                                Text("Choose…").tag("")
                                ForEach(intelligence.models, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        if !provider.local {
                            Toggle("Let \(provider.name) see my plan (item names and times)", isOn: $sharePlan)
                            Text("On: it can answer “what should I do first?” and find “the dentist thing”. Off: it still acts, and moi matches names on this Mac.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                        }
                        Text(provider.local ? "Runs on this Mac. moi shares a short summary of your day with it so it can help." : "What you type in Ask moi is sent, after a one-time OK\(sharePlan ? ", plus your plan's item names and times" : ""). Your files, photos and audio never are. Free tiers are limited; your provider's pricing applies.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                    }
                }
                BrainsSection()
                Section("Privacy") {
                    Toggle("Offline mode (blocks every cloud request)", isOn: $offline)
                        .onChange(of: offline) { _, value in if value { intelligence.cancel() } }
                    Text("Your plan, focus and clean-up never need an AI model.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                }
                ModuleMessage(text: intelligence.error)
                VoiceSettingsSection()
        }.formStyle(.grouped)
    }

    private var music: some View {
        Form {
            Section("Player") {
                Picker("Show and control", selection: $musicPlayer) { Text("Spotify").tag("Spotify"); Text("Apple Music").tag("Apple Music") }.pickerStyle(.segmented)
                    .onChange(of: musicPlayer) { _, _ in player.disconnect(); player.playerChanged() }
                Text("The song shows in the notch on its own, with no permission. The first time you press play or skip, macOS asks once to let moi control \(musicPlayer).").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                Toggle("Download album art (Spotify)", isOn: $artwork).onChange(of: artwork) { _, _ in player.refresh() }
                ModuleMessage(text: player.error)
            }
        }.formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("Permissions (each asked only when you use it)") {
                LabeledContent("Microphone", value: voice.permission)
                Button("Notifications…") { NotificationService.shared.requestPermission { _ in NotificationService.shared.reschedule(using: store.data) } }
                Text("Desktop and Downloads: asked the first time you clean up or turn on recent files in the notch.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                Button("Open macOS Privacy settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
            }
            Section("Your data stays on this Mac") {
                Text(MoiPaths.root.path).font(.caption).textSelection(.enabled)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.open(MoiPaths.root) }
                    Button("Export…") { DataTransferService.exportJSON(data: store.data) }
                    Button("Import…") { DataTransferService.importJSON(into: store) }
                }
                Text("No account, no analytics, no tracking. Keys you add stay in your Keychain.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
        }.formStyle(.grouped)
    }
}
/// moi's origin story, acted out. moi tumbles in, tells where it came from, notices you, asks
/// your name, decides to help, asks for its keys (every permission explained and optional),
/// does one real thing with you, and moves into the notch. Skippable; nothing shown is fake data.
struct OnboardingView: View {
    @EnvironmentObject private var workspace: MoiWorkspace
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var voice = VoiceService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("moi.onboardingStep") private var step = 0
    @AppStorage("moi.userName") private var userName = ""
    @State private var nameDraft = ""
    @State private var taskTitle = ""
    @State private var created = false
    @State private var error: String?
    // Stage direction
    @State private var moiX: CGFloat = 0
    @State private var moiY: CGFloat = -420
    @State private var moiScale: CGFloat = 1
    @State private var acting: MoiCharacterState?
    @State private var line = ""
    private let steps = 10
    /// moi's little sound effects (blips while talking, boings while hopping). On unless muted here.
    @AppStorage("moi.chatterOn") private var soundsOn = true
    @State private var showEverywhere = UserDefaults.standard.object(forKey: "moi.showCharacter") as? Bool ?? true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) { ForEach(0..<steps, id: \.self) { i in Capsule().fill(i <= step ? MoiStyle.accent : Color.white.opacity(0.15)).frame(width: i == step ? 18 : 6, height: 6) } }
                    .animation(.easeOut(duration: 0.2), value: step)
                Spacer()
                Button { soundsOn.toggle() } label: { Image(systemName: soundsOn ? "speaker.wave.2" : "speaker.slash") }
                    .buttonStyle(.moiGhost).help(soundsOn ? "Mute moi's sounds" : "Turn moi's sounds on").accessibilityLabel(soundsOn ? "Mute moi's sounds" : "Turn moi's sounds on")
                Button("Skip the story") { finish() }.buttonStyle(.moiGhost).keyboardShortcut(.cancelAction)
            }
            stage.frame(height: 290)
            controls.frame(maxWidth: 600).frame(height: 236, alignment: .top)
            if let error { Text(error).font(MoiType.ui(13)).foregroundStyle(MoiStyle.coral) }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.moiGhost) }
                Spacer()
                Button(primaryTitle) { advance() }.buttonStyle(.moiPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 880, height: 690)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .environment(\.colorScheme, .dark)
        .onAppear { nameDraft = userName; step = min(step, steps - 1) }
        .task(id: step) { await perform(step) }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geo in
            let floor = geo.size.height - 30
            ZStack {
                // A soft floor shadow under moi, so the fall has somewhere to land.
                Ellipse().fill(Color.black.opacity(0.45)).frame(width: 110 * moiScale, height: 16 * moiScale)
                    .position(x: geo.size.width / 2 + moiX, y: floor + 6).opacity(moiY < -60 ? 0.2 : 1)
                MoiCharacter(state: acting ?? moiState, size: 150, gaze: step == 2 ? CGSize(width: 0, height: 0.4) : .zero, sticker: true, essential: true)
                    .scaleEffect(moiScale, anchor: .bottom)
                    .position(x: geo.size.width / 2 + moiX, y: floor - 75 + moiY)
                if !line.isEmpty {
                    SpeechBubble(text: line, chatter: true)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .frame(width: 340, alignment: .leading)
                        .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08)))
                        .position(x: min(geo.size.width - 180, max(180, geo.size.width / 2 + moiX + (moiX > 0 ? -260 : 260))), y: floor - 150)
                        .transition(.opacity)
                }
            }
        }
    }

    private var moiState: MoiCharacterState {
        if voice.speaking { return .speaking }
        switch step {
        case 2: return nameDraft.isEmpty ? .curious : .happy
        case 4: return .attention
        case 6: return .working
        case 7: return created ? .success : taskTitle.isEmpty ? .listening : .working
        case 8: return .permissionRequired
        case 9: return .happy
        default: return .idle
        }
    }

    /// The choreography for each beat. Reduce Motion: moi simply appears in place.
    private func perform(_ step: Int) async {
        error = nil; acting = nil
        func say(_ text: String) {
            withAnimation(.easeOut(duration: 0.2)) { line = text }

        }
        func act(_ state: MoiCharacterState?, for seconds: Double? = nil) async {
            acting = state
            if let seconds { try? await Task.sleep(for: .seconds(seconds)); acting = nil }
        }
        if reduceMotion { moiY = 0; moiScale = 1 }
        let name = userName.isEmpty ? "" : ", \(userName)"
        switch step {
        case 0:
            line = ""; moiX = 0; moiScale = 1
            if !reduceMotion {
                moiY = -420
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeIn(duration: 0.42)) { moiY = 0 }
                try? await Task.sleep(for: .milliseconds(420))
                MoiChatter.shared.thud()
                await act(.error, for: 0.9) // the landing
            }
            say("Oof. …That was the landing.\n\nHi! Sorry. I'm a bit new at this.")
            await act(.curious, for: 1.4)
        case 1:
            say("Someone named Marshall made me, to help with the little things on your Mac.")
            await walk(to: -170)
            try? await Task.sleep(for: .seconds(5))
            await act(.happy, for: 1.0)
            say("So here I am. I'm moi.")
        case 2:
            await walk(to: 0)
            await act(.attention, for: 0.8)
            say("Oh. Hello. You look like you could use a hand.\n\nWhat should I call you?")
        case 3:
            await act(.success, for: 0.9)
            say("Nice to meet you\(name)! I've decided: I'm your helper now. Want to pick my colour? I'm not fussy. Mostly.")
        case 4:
            await walk(to: -200)
            await act(.attention, for: 0.6)
            say("I live in the notch: that black bit at the very top of your screen. Rest your pointer on it for your music. Click it for your day.")
        case 5:
            await walk(to: 0)
            say("Need something? Press \(workspace.shortcut.rawValue) from anywhere, or open the Pocket. Tell me “gym tomorrow 4pm” or “clean up my desktop”.")
        case 6:
            await walk(to: -200)
            say("Focus is a timer for one thing. While it runs, if you open an app on your distraction list, I'll ask if you want to get back to work.")
        case 7:
            await walk(to: 0)
            say(created ? "That's our first one together. I'm keeping count." : "You can add things just by typing, like “essay due fri”. Tell me one thing you want to get done.")
        case 8:
            await walk(to: -200)
            say("To help properly I need a few keys. Each one is optional. Allow them now and I won't have to stop and ask later.")
        default:
            await walk(to: 0)
            await trip()
            say("Right. I'll be up in the notch\(name). Press the shortcut any time and I'll come running. See you around!")
        }
    }

    /// A small stumble, because that's who moi is.
    private func trip() async {
        guard !reduceMotion else { return }
        acting = .error
        try? await Task.sleep(for: .milliseconds(500))
        acting = .happy
        try? await Task.sleep(for: .milliseconds(700))
        acting = nil
    }

    /// moi hops across the stage in little bounces.
    private func walk(to target: CGFloat) async {
        guard !reduceMotion else { moiX = target; return }
        let hops = max(1, Int(abs(target - moiX) / 55))
        let stride = (target - moiX) / CGFloat(hops)
        for _ in 0..<hops {
            MoiChatter.shared.hop()
            withAnimation(.easeOut(duration: 0.13)) { moiX += stride / 2; moiY = -26 }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeIn(duration: 0.13)) { moiX += stride / 2; moiY = 0 }
            try? await Task.sleep(for: .milliseconds(140))
        }
        moiX = target
    }

    // MARK: Controls under the stage

    @ViewBuilder private var controls: some View {
        switch step {
        case 2:
            TextField("Your name", text: $nameDraft).textFieldStyle(.plain).font(MoiType.ui(17))
                .padding(14).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)).onSubmit { advance() }
        case 3:
            VStack(alignment: .leading, spacing: 14) {
                MoiColorPicker()
                Toggle("Show me around the app (otherwise I'll stay in the notch)", isOn: $showEverywhere)
                    .onChange(of: showEverywhere) { _, value in UserDefaults.standard.set(value, forKey: "moi.showCharacter") }
                    .font(MoiType.ui(13.5))
            }
        case 4:
            VStack(alignment: .leading, spacing: 12) {
                NotchDiagram()
                HStack(spacing: 10) {
                    Button("Show me the notch") { NotificationCenter.default.post(name: Notification.Name("MoiPeekNotch"), object: nil) }.buttonStyle(.moiSecondary)
                    Text("Shortcut: \(NotchPreferences().shortcut.label). Press it again, or click anywhere else, to close.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                }
            }
        case 5:
            HStack(spacing: 14) {
                KeyCaps(text: workspace.shortcut.rawValue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask or search, from anywhere").font(MoiType.ui(14, weight: 620))
                    Text("Inside moi, ⌘K does the same. ⇧⌘N adds a task.").font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet)
                }
                Spacer()
                Button("Try it") { workspace.showCommand() }.buttonStyle(.moiSecondary)
            }
        case 6:
            FocusSetup()
        case 7:
            if created { Label("Added to your plan", systemImage: "checkmark.circle.fill").font(MoiType.ui(15, weight: 600)).foregroundStyle(MoiStyle.mint) }
            else {
                TextField("For example: essay due fri", text: $taskTitle).textFieldStyle(.plain).font(MoiType.ui(17))
                    .padding(14).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)).onSubmit { advance() }
            }
        case 8:
            MoiKeysGrid(dark: true)
        default: EmptyView()
        }
    }

    private var primaryTitle: String {
        switch step {
        case 0: return "Are you okay?"
        case 1: return "Hi, moi"
        case 2: return nameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? "I'd rather not say" : "Call me \(nameDraft.trimmingCharacters(in: .whitespaces))"
        case 3: return "Looking good"
        case 4: return "Got it"
        case 5: return "Handy"
        case 6: return "Sounds good"
        case 7: return created ? "Nice one" : taskTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Maybe later" : "Add it"
        case 8: return "Done with keys"
        default: return "See you up there"
        }
    }

    private func advance() {
        error = nil
        switch step {
        case 2: userName = String(nameDraft.trimmingCharacters(in: .whitespaces).prefix(40))
        case 7 where !created && !taskTitle.trimmingCharacters(in: .whitespaces).isEmpty:
            guard !store.isReadOnly else { error = "Your data is in read-only recovery mode, so I can't add it right now."; return }
            store.quickAdd(taskTitle.trimmingCharacters(in: .whitespaces))
            if let message = store.persistenceError { error = MoiVoice.failed("save that", reason: message) }
            else { created = true; line = "That's our first one together. I'm keeping count." }
            return
        case 9: moveIn(); return
        default: break
        }
        step = min(step + 1, steps - 1)
    }

    /// moi hops up toward the notch and shrinks away; then the real notch peeks open with moi in it.
    private func moveIn() {
        voice.cancel()
        guard !reduceMotion else { finish(); return }
        line = ""
        withAnimation(.easeIn(duration: 0.45)) { moiY = -330; moiScale = 0.2 }
        Task { try? await Task.sleep(for: .milliseconds(480)); finish() }
    }

    private func finish() {
        voice.cancel()
        UserDefaults.standard.set(true, forKey: "moi.onboardingComplete")
        step = 0
        workspace.onboarding = false
        NotificationCenter.default.post(name: Notification.Name("MoiPeekNotch"), object: nil)
    }
}

/// moi's keys (permissions), each explained, each optional, asked for only when tapped.
/// Used in the introduction and in the Guide, so they can be granted up front instead of mid-task.
struct MoiKeysGrid: View {
    var dark = false
    @EnvironmentObject private var store: AppStore
    @State private var keys = PermissionKeys()
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            key("bell.badge", "Reminders", "So I can tap you when something's due.", keys.notifications) { NotificationService.shared.requestPermission { granted in if granted { store.update { $0.settings.notificationsEnabled = true } }; keys.refresh() } }
            key("mic", "Voice", "So you can talk to me. Audio stays on this Mac.", keys.voice) { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); _ = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }; keys.refresh() } }
            key("photo.on.rectangle", "Photos", "So I can find and sort photos into albums. I never change or delete them.", keys.photos) { Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite); keys.refresh() } }
            key("folder", "Desktop & Downloads", "So I can clean them up, and show new downloads in the notch. Nothing moves until you say.", keys.files) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let ok = ["Desktop", "Downloads"].allSatisfy { (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent($0).path)) != nil }
                UserDefaults.standard.set(ok, forKey: "moi.filesAllowed"); UserDefaults.standard.set(true, forKey: "moi.recentFiles"); keys.refresh()
            }
            key("music.note", "Music", "So I can play, pause and skip for you.", keys.music) { SpotifyNowPlaying.shared.requestControl(); keys.refresh() }
            key("keyboard", "Accessibility", "Only for private Safari windows: macOS makes me press ⇧⌘N for you.", keys.accessibility) { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary); keys.refresh() }
        }
        .onAppear { keys.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in keys.refresh() }
    }

    private func key(_ symbol: String, _ title: String, _ why: String, _ granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(MoiStyle.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MoiType.ui(13.5, weight: 620))
                Text(why).font(MoiType.ui(12)).foregroundStyle(MoiStyle.quiet).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if granted { Image(systemName: "checkmark.circle.fill").foregroundStyle(MoiStyle.mint).help("Allowed") }
            else { Button("Allow", action: request).buttonStyle(.moiSecondary).controlSize(.small) }
        }
        .padding(10)
        .background(dark ? Color.white.opacity(0.05) : MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Which of moi's keys are granted, read fresh (also when you come back from System Settings).
struct PermissionKeys {
    var notifications = false, voice = false, music = false, accessibility = false, screen = false, photos = false, files = false
    mutating func refresh() {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photos = photoStatus == .authorized || photoStatus == .limited
        files = UserDefaults.standard.bool(forKey: "moi.filesAllowed")
        voice = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && SFSpeechRecognizer.authorizationStatus() == .authorized
        music = UserDefaults.standard.bool(forKey: "moi.musicConnected")
        accessibility = AXIsProcessTrusted()
        screen = CGPreflightScreenCaptureAccess()
        notifications = UserDefaults.standard.bool(forKey: "moi.notificationsAllowed")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            UserDefaults.standard.set(settings.authorizationStatus == .authorized, forKey: "moi.notificationsAllowed")
        }
    }
}

/// A little drawing of the notch, labelled with what hovering and clicking do.
private struct NotchDiagram: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)).frame(width: 200, height: 70)
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(.black).frame(width: 64, height: 16)
                    .overlay(alignment: .bottom) { MoiCharacter(state: .happy, size: 18, pose: .peek, essential: true).offset(y: 6) }
                Image(systemName: "cursorarrow").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).offset(x: 18, y: 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Rest your pointer: your music", systemImage: "hand.point.up.left").font(MoiType.ui(13))
                Label("Click: everything else", systemImage: "cursorarrow.click").font(MoiType.ui(13))
            }
        }
    }
}

/// Keyboard shortcut shown as little key caps.
private struct KeyCaps: View {
    let text: String
    var body: some View {
        Text(text).font(MoiType.ui(16, weight: 620)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.18)))
    }
}

/// Focus's distraction list, editable right in the introduction (the same list as Focus → Soft blocking).
struct FocusSetup: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(store.data.settings.blockedBundleIDs, id: \.self) { id in
                    HStack(spacing: 5) {
                        Text(Self.name(id)).font(MoiType.ui(12.5, weight: 560)).lineLimit(1)
                        Button { store.update { $0.settings.blockedBundleIDs.removeAll { $0 == id } } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain).accessibilityLabel("Remove \(Self.name(id))")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.08), in: Capsule())
                }
                Button { addApp() } label: { Label("Add an app", systemImage: "plus").font(MoiType.ui(12.5, weight: 600)) }.buttonStyle(.moiSecondary)
            }
            Toggle("Close the app for me when you say “back to focus”", isOn: Binding(get: { store.data.settings.quitBlockedApps }, set: { value in store.update { $0.settings.quitBlockedApps = value } })).font(MoiType.ui(13))
            Toggle("Use the distraction list during focus", isOn: Binding(get: { store.data.settings.softBlockEnabled }, set: { value in store.update { $0.settings.softBlockEnabled = value } })).font(MoiType.ui(13))
            Text("Start a focus from the notch, Home or the Focus page. Change this list any time in Focus.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
        }
    }
    static func name(_ bundleID: String) -> String {
        if let known = ["com.facebook.archon": "Messenger", "com.reddit.Reddit": "Reddit"][bundleID], NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil { return known }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }
    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true
        panel.prompt = "Add to distraction list"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        store.update { data in for id in ids where !data.settings.blockedBundleIDs.contains(id) { data.settings.blockedBundleIDs.append(id) } }
    }
}

/// moi's speech: display face, text appears briskly as if said (instant with Reduce Motion).
struct SpeechBubble: View {
    let text: String
    /// Soft blips as the words appear, like moi talking.
    var chatter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    var body: some View {
        Text(reduceMotion ? text : String(text.prefix(shown)))
            .font(MoiType.display(19, weight: 600)).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) { Text(text).font(MoiType.display(19, weight: 600)).lineSpacing(3).opacity(0) } // reserves final height
            .accessibilityLabel(text)
            .task(id: text) {
                shown = 0
                guard !reduceMotion else { return }
                while shown < text.count && !Task.isCancelled {
                    shown += 1
                    if chatter, shown % 3 == 1, text[text.index(text.startIndex, offsetBy: shown - 1)].isLetter { MoiChatter.shared.blip() }
                    try? await Task.sleep(for: .milliseconds(text[text.index(text.startIndex, offsetBy: shown - 1)] == "\n" ? 180 : 16))
                }
            }
    }
}

