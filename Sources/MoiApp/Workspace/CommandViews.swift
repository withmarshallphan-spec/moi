import SwiftUI
import AppKit
import CoreAudio
import AVFoundation

struct IntelligenceView: View {
    @EnvironmentObject private var workspace: MoiWorkspace
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var intelligence = Intelligence.shared
    @ObservedObject private var voice = VoiceService.shared
    @FocusState private var typing: Bool
    @State private var showHistory = false
    @State private var showBrains = false
    private let suggestions = ["What's tomorrow?", "Clean up my downloads", "Find my flower photos", "Quit everything except Safari"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if intelligence.messages.isEmpty { emptyState }
                        ForEach(intelligence.messages) { message in bubble(message).id(message.id) }
                        if intelligence.pending != nil { pendingBubble }
                        if intelligence.canUndo, !intelligence.busy, intelligence.pending == nil { Button("Undo moi's last change") { intelligence.undo(store: store) }.buttonStyle(.moiGhost) }
                        if intelligence.busy { typingBubble.id("typing") }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 20)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: intelligence.messages.count) { _, _ in withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(intelligence.messages.last?.id, anchor: .bottom) } }
                .onChange(of: intelligence.busy) { _, busy in if busy { withAnimation { scroll.scrollTo("typing", anchor: .bottom) } } }
            }
            inputBar
        }
        .onAppear { typing = true }
        .task { await intelligence.checkBrains() } // a refused key or dead connection shows before you type
        .sheet(isPresented: $showHistory) { history }
        .sheet(isPresented: $showBrains) { BrainModelsView() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MoiCharacter(state: intelligence.busy ? .working : voice.speaking ? .speaking : .idle, size: 40, pose: .peek)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask moi").font(MoiType.display(22, weight: 660))
                BrainStatusLine()
            }
            Spacer()
            Menu {
                Section("Ready") {
                    ForEach(intelligence.selectableBrains) { p in
                        Menu(p.name) {
                            let names = p.kind == .apple ? ["Apple on-device"] : intelligence.verifiedModels[p.id] ?? []
                            ForEach(Array(names.prefix(30)), id: \.self) { model in
                                Button { if p.kind != .apple { p.model = model }; intelligence.providerID = p.id } label: {
                                    if p.id == intelligence.providerID && (p.kind == .apple || model == p.model) { Label(model, systemImage: "checkmark") } else { Text(model) }
                                }
                            }
                        }
                    }
                    if intelligence.selectableBrains.isEmpty { Text("None ready yet").disabled(true) }
                }
                Button("No AI (moi's own rules)") { intelligence.providerID = "moi" }
                Divider()
                Button("Usage…") { showBrains = true }
                Button("Add a brain…") { workspace.showMain(.settings) }
            } label: {
                Label("Brain", systemImage: "brain").font(MoiType.ui(12.5, weight: 580))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(MoiStyle.surface, in: Capsule()).overlay(Capsule().stroke(MoiStyle.border))
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.moiGhost).help("What I've done (history)")
            if !intelligence.messages.isEmpty { Button { intelligence.clearChat() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.moiGhost).help("New conversation") }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private func providerButton(_ p: AIProvider) -> some View {
        Button { intelligence.providerID = p.id } label: {
            if p.id == intelligence.providerID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MoiCharacter(state: .curious, size: 76, sticker: true).padding(.top, 30)
            Text(MoiVoice.name.isEmpty ? "Ask me anything." : "Ask me anything, \(MoiVoice.name).").font(MoiType.display(24, weight: 650))
            Text("I'm best at your day. I can also do small things for you.").font(MoiType.ui(14)).foregroundStyle(MoiStyle.quiet)
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { text in
                    Button { send(text) } label: {
                        Text(text).font(MoiType.ui(12.5, weight: 560)).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(MoiStyle.surface, in: Capsule()).overlay(Capsule().stroke(MoiStyle.border))
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func bubble(_ message: MoiMessage) -> some View {
        if message.fromMOI {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text).font(MoiType.ui(14.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(MoiStyle.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    HStack(spacing: 10) {
                        if !message.source.isEmpty { Text("moi").font(MoiType.ui(11)).foregroundStyle(MoiStyle.quiet).help("Source: " + message.source) }
                    }.padding(.leading, 6)
                }
                Spacer(minLength: 80)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack {
                Spacer(minLength: 120)
                Text(message.text).font(MoiType.ui(14.5)).foregroundStyle(Color.white).textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(MoiStyle.butterFill, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
            }
        }
    }

    private var typingBubble: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TypingDots().padding(.horizontal, 16).padding(.vertical, 14)
                .background(MoiStyle.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
            Button("Stop") { intelligence.cancel() }.buttonStyle(.moiGhost)
        }
    }

    /// A model wants to delete something: it waits for a yes.
    private var pendingBubble: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text(intelligence.pendingSummary).font(MoiType.ui(14.5, weight: 600))
                HStack {
                    Button(intelligence.pendingVerb) { intelligence.approvePending(store: store) }.buttonStyle(.moiPrimary)
                    Button("No") { intelligence.record("suggestion", "Declined", intelligence.pendingSummary); intelligence.pending = nil }.buttonStyle(.moiGhost)
                }
            }
            .padding(14)
            .background(MoiStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MoiStyle.accent.opacity(0.35)))
            Spacer(minLength: 80)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message moi…", text: $intelligence.draft, axis: .vertical)
                .textFieldStyle(.plain).font(MoiType.ui(15)).lineLimit(1...6).focused($typing)
                .onSubmit { send(intelligence.draft) }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(typing ? MoiStyle.accent.opacity(0.5) : MoiStyle.border))
            TalkButton(size: 38)
            Button { send(intelligence.draft) } label: {
                Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 38, height: 38).background(MoiStyle.butterFill, in: Circle())
            }
            .buttonStyle(.plain).disabled(intelligence.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || intelligence.busy)
            .keyboardShortcut(.return, modifiers: .command).accessibilityLabel("Send")
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .frame(maxWidth: 868)
        .frame(maxWidth: .infinity)
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        intelligence.draft = text
        withAnimation(.easeOut(duration: 0.2)) { intelligence.respond(store: store) }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("What I've done").font(MoiType.display(22, weight: 650)); Spacer(); Button("Done") { showHistory = false }.buttonStyle(.moiSecondary) }
            Text("Every action, with what actually happened.").font(MoiType.ui(13)).foregroundStyle(MoiStyle.quiet)
            List(intelligence.events.prefix(200)) { event in
                HStack { Text(event.tool).font(MoiType.ui(13, weight: 600)); Text(event.status).font(MoiType.ui(12)).foregroundStyle(event.status == "Completed" ? MoiStyle.mint : event.status == "Failed" ? MoiStyle.coral : MoiStyle.quiet); Spacer(); Text(event.detail).font(MoiType.ui(12)).foregroundStyle(MoiStyle.quiet).lineLimit(1) }
            }
            Button("Clear history") { intelligence.clearHistory() }.buttonStyle(.moiGhost)
        }
        .padding(24).frame(width: 640, height: 480)
    }
}

/// Three dots that bounce in turn while moi is thinking.
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(MoiStyle.quiet).frame(width: 7, height: 7).offset(y: reduceMotion ? 0 : -4 * max(0, sin(t * 6 - Double(i) * 0.7)))
                }
            }
        }
        .accessibilityLabel("moi is thinking")
    }
}

/// "Make moi smarter, free": a free Gemini or Groq key in about a minute. Says exactly what's sent.
/// Who's thinking right now, and whether anything is wrong, before you type.
struct BrainStatusLine: View {
    @ObservedObject private var intelligence = Intelligence.shared
    var body: some View {
        let chain = intelligence.brainChain()
        HStack(spacing: 6) {
            Circle().fill(chain.isEmpty ? MoiStyle.quiet : MoiStyle.mint).frame(width: 6, height: 6)
            if let brain = chain.first {
                Text(brain.name + " · " + intelligence.usageSummary(brain)).font(MoiType.small).foregroundStyle(MoiStyle.quiet).lineLimit(1)
            } else {
                Text(intelligence.provider.kind == .none ? "No AI · moi's own rules" : "No brain is ready · moi's own rules for now").font(MoiType.small).foregroundStyle(MoiStyle.quiet).lineLimit(1)
            }
        }
        .help(chain.isEmpty ? "" : "If one runs out, the next answers: " + chain.map(\.name).joined(separator: " → "))
    }
}

/// One box for any AI key: moi works out whose it is, checks it, picks a model and adds it to the chain.
struct BrainKeyCard: View {
    var inSettings = false
    @ObservedObject private var intelligence = Intelligence.shared
    @AppStorage("moi.freeBrainDismissed") private var dismissed = false
    @State private var key = ""
    @State private var status = ""
    @State private var working = false
    @State private var chosen = "gemini"
    private var detected: String? { BrainChain.detect(key: key) }
    private var hasBrain: Bool { intelligence.brainChain().contains { $0.kind != .apple } }

    var body: some View {
        if inSettings || !dismissed {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(hasBrain ? "Add a backup brain, for free" : "Make moi smarter, for free").font(MoiType.ui(14, weight: 650))
                    Spacer()
                    if !inSettings { Button("Not now") { dismissed = true }.buttonStyle(.moiGhost) }
                }
                Text("Free keys take a minute to get. Add two or three and moi switches by itself when one runs out, in the same chat. What you type in Ask moi goes to that company; your files and photos stay on this Mac. (A Gemini key from a Google project with billing turned on can be charged.)")
                    .font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("Get a free key:").font(MoiType.ui(12.5, weight: 600))
                    ForEach(AIProvider.all.filter(\.free)) { p in
                        Button(p.name) { if let url = p.signup { NSWorkspace.shared.open(url) } }
                            .buttonStyle(.moiGhost).overlay(alignment: .topTrailing) { if intelligence.ready(p) { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(MoiStyle.mint) } }
                    }
                }
                HStack(spacing: 8) {
                    SecureField("Paste any key here", text: $key).textFieldStyle(.roundedBorder)
                    Button("Paste") { key = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }.buttonStyle(.moiGhost)
                    if !key.isEmpty, detected == nil {
                        Picker("Whose key?", selection: $chosen) { ForEach(AIProvider.all.filter(\.needsKey)) { Text($0.name).tag($0.id) } }.fixedSize()
                    }
                    Button(working ? "Checking…" : "Add") {
                        working = true
                        Task { status = await intelligence.addKey(key, provider: detected ?? chosen); working = false; key = "" }
                    }.buttonStyle(.moiPrimary).disabled(key.count < 10 || working)
                }
                if let detected, !key.isEmpty { Text("Looks like a \(AIProvider.find(detected).name) key.").font(MoiType.small).foregroundStyle(MoiStyle.quiet) }
                if !status.isEmpty { Text(status).font(MoiType.small) }
            }
            .padding(14)
            .background(MoiStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MoiStyle.accent.opacity(0.25)))
        }
    }
}

/// Settings: every brain moi can use, how it's doing today, and what the provider says is left.
struct BrainsSection: View {
    @ObservedObject private var intelligence = Intelligence.shared
    @AppStorage("moi.allowPaidBackups") private var allowPaid = false
    @State private var checking = false
    var body: some View {
        Section("Your brains, in the order moi tries them") {
            let chain = intelligence.brainChain().map(\.id)
            let known = AIProvider.all.filter { $0.kind != .none && (intelligence.ready($0) || ($0.needsKey && !CredentialStore.get($0.keyAccount).isEmpty)) }
            ForEach(known.sorted { (chain.firstIndex(of: $0.id) ?? 99) < (chain.firstIndex(of: $1.id) ?? 99) }) { p in row(p, inChain: chain.contains(p.id)) }
            HStack {
                Text("Then moi's own rules, which always work.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                Spacer()
                Button(checking ? "Checking…" : "Check all now") { checking = true; Task { await intelligence.checkBrains(force: true); checking = false } }.disabled(checking)
            }
            Toggle("Use paid providers as backups too (may cost money)", isOn: $allowPaid)
            BrainKeyCard(inSettings: true)
        }
    }

    private func row(_ p: AIProvider, inChain: Bool) -> some View {
        let entry = intelligence.ledger[p.id]
        let resting = entry?.restingUntil.map { $0 > Date() } ?? false
        return HStack(spacing: 10) {
            Circle().fill(resting ? MoiStyle.butter : inChain ? MoiStyle.mint : MoiStyle.coral).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name + (p.id == intelligence.providerID ? " · main" : p.free ? " · free" : p.local ? " · on this Mac" : " · paid")).font(MoiType.ui(13, weight: 600))
                Text([Intelligence.shortModel(p.model), intelligence.usageSummary(p)].compactMap { $0 }.joined(separator: " · ")).font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet).lineLimit(2)
            }
            Spacer()
            if resting { Button("Try again") { intelligence.wake(p.id) } }
            if p.id != intelligence.providerID && intelligence.selectableBrains.contains(p) { Button("Make main") { intelligence.providerID = p.id } }
        }
    }
}


struct BrainModelsView: View {
    @ObservedObject private var intelligence = Intelligence.shared
    @Environment(\.dismiss) private var dismiss
    /// Every brain with a key or a model, ready or resting, so it's clear why one isn't answering.
    private var brains: [AIProvider] {
        let order = intelligence.brainChain().map(\.id)
        return AIProvider.all.filter { $0.kind != .none && intelligence.ready($0) }
            .sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Brains").font(MoiType.display(22, weight: 650)); Spacer(); Button("Done") { dismiss() }.buttonStyle(.moiSecondary).keyboardShortcut(.defaultAction) }
            Text("When one runs out, the next takes over, in the same chat.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(brains) { p in
                        let resting = intelligence.ledger[p.id]?.restingUntil.map { $0 > Date() } ?? false
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.name).font(MoiType.ui(14.5, weight: 650))
                                Text(Intelligence.shortModel(p.model) ?? "").font(MoiType.ui(12)).foregroundStyle(MoiStyle.quiet)
                                Spacer()
                                if resting { Button("Try now") { intelligence.wake(p.id) }.buttonStyle(.moiGhost) }
                                else if p.id == intelligence.brainChain().first?.id { Text("Answering").font(MoiType.ui(11.5, weight: 600)).foregroundStyle(MoiStyle.mint) }
                            }
                            Text(intelligence.usageSummary(p)).font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                            if let quota = intelligence.quotas(p).first, !resting { ProgressView(value: quota.usedFraction).tint(quota.usedFraction > 0.85 ? MoiStyle.coral : MoiStyle.accent) }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(resting ? 0.6 : 1)
                    }
                    if brains.isEmpty { Text("No brains yet. Paste a free key in Settings → Brain & voice.").font(MoiType.body).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
            HStack {
                Text("Groq and OpenRouter share how much is left; Google doesn't, so Gemini shows today's replies.").font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet)
                Spacer()
                Button("Check again") { Task { await intelligence.checkBrains(force: true) } }.buttonStyle(.moiGhost)
            }
        }.padding(24).frame(width: 520, height: 460)
    }
}
