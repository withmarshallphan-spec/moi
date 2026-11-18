import AppKit
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ToolEvent: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var tool: String
    var status: String
    var detail: String
}
struct MoiMessage: Identifiable, Equatable {
    var id = UUID()
    var fromMOI: Bool
    var text: String
    /// Where a moi message came from ("From your records", "Apple Intelligence", …).
    var source = ""
    var date = Date()
}

/// Every place moi's brain can come from. Keys are per provider, the user's own, in Keychain.
/// Nothing is developer-funded. Local providers stay on this Mac; cloud ones need a one-time OK.
struct AIProvider: Identifiable, Hashable {
    enum Kind { case none, apple, ollama, openAI, anthropic }
    let id: String
    let name: String
    let kind: Kind
    let baseURL: String
    var local = false
    var keyHint = ""

    static let all: [AIProvider] = [
        .init(id: "moi", name: "Just moi (no AI model)", kind: .none, baseURL: "", local: true),
        .init(id: "apple", name: "Apple Intelligence", kind: .apple, baseURL: "", local: true),
        .init(id: "ollama", name: "Ollama", kind: .ollama, baseURL: "http://127.0.0.1:11434", local: true),
        .init(id: "lmstudio", name: "LM Studio", kind: .openAI, baseURL: "http://127.0.0.1:1234/v1", local: true),
        .init(id: "openai", name: "OpenAI", kind: .openAI, baseURL: "https://api.openai.com/v1", keyHint: "platform.openai.com"),
        .init(id: "anthropic", name: "Anthropic (Claude)", kind: .anthropic, baseURL: "https://api.anthropic.com/v1", keyHint: "console.anthropic.com"),
        .init(id: "gemini", name: "Google Gemini", kind: .openAI, baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", keyHint: "aistudio.google.com"),
        .init(id: "openrouter", name: "OpenRouter", kind: .openAI, baseURL: "https://openrouter.ai/api/v1", keyHint: "openrouter.ai/keys"),
        .init(id: "groq", name: "Groq", kind: .openAI, baseURL: "https://api.groq.com/openai/v1", keyHint: "console.groq.com"),
        .init(id: "nvidia", name: "NVIDIA", kind: .openAI, baseURL: "https://integrate.api.nvidia.com/v1", keyHint: "build.nvidia.com"),
        .init(id: "mistral", name: "Mistral", kind: .openAI, baseURL: "https://api.mistral.ai/v1", keyHint: "console.mistral.ai"),
        .init(id: "deepseek", name: "DeepSeek", kind: .openAI, baseURL: "https://api.deepseek.com/v1", keyHint: "platform.deepseek.com"),
        .init(id: "xai", name: "xAI (Grok)", kind: .openAI, baseURL: "https://api.x.ai/v1", keyHint: "console.x.ai"),
        .init(id: "together", name: "Together AI", kind: .openAI, baseURL: "https://api.together.xyz/v1", keyHint: "api.together.ai"),
        .init(id: "custom", name: "Other (OpenAI-compatible)", kind: .openAI, baseURL: ""),
    ]
    static func find(_ id: String) -> AIProvider { all.first { $0.id == id } ?? all[0] }
    var needsKey: Bool { !local && kind != .none }
    /// A free tier with the person's own key (never billed by moi's choice).
    var free: Bool { BrainChain.free.contains(id) }
    /// Where to get a key, for the setup card.
    var signup: URL? {
        ["gemini": "https://aistudio.google.com/apikey", "groq": "https://console.groq.com/keys", "openrouter": "https://openrouter.ai/keys", "nvidia": "https://build.nvidia.com", "mistral": "https://console.mistral.ai/api-keys"][id].flatMap(URL.init(string:))
    }
    var model: String {
        get { UserDefaults.standard.string(forKey: "moi.model.\(id)") ?? (id == "ollama" ? UserDefaults.standard.string(forKey: "moi.ollamaModel") ?? "" : id == "custom" ? UserDefaults.standard.string(forKey: "moi.cloudModel") ?? "" : "") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "moi.model.\(id)") }
    }
    var endpoint: String {
        if id == "custom" { return UserDefaults.standard.string(forKey: "moi.cloudURL") ?? "" }
        if id == "ollama" { return UserDefaults.standard.string(forKey: "moi.ollamaURL") ?? baseURL }
        return baseURL
    }
    /// The custom provider keeps the Keychain account the earlier build used.
    var keyAccount: String { id == "custom" ? "cloud" : id }
}

enum CredentialStore {
    static var service: String { (Bundle.main.bundleIdentifier ?? "local.moi") + ".providers" }
    /// Keys read this launch. The Keychain is asked once per key, not on every redraw (each ask
    /// can make macOS show a password prompt when the app's signature has changed).
    @MainActor private static var cache: [String: String] = [:]
    @MainActor static func get(_ account: String = "cloud") -> String {
        if let known = cache[account] { return known }
        let value = read(account)
        cache[account] = value
        return value
    }
    private static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    @MainActor static func set(_ key: String, account: String = "cloud") throws {
        cache[account] = nil
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if key.isEmpty { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw MoiError.message("Keychain deletion failed (\(status)).") }; return }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw MoiError.message("Keychain write failed (\(added)).") }; return
        }
        guard status == errSecSuccess else { throw MoiError.message("Keychain update failed (\(status)).") }
    }
}

struct HTTPStatusError: LocalizedError {
    var status: Int
    var message: String
    /// What the provider said about waiting: seconds to wait, and whether a daily quota ran out.
    var retryAfter: Double? = nil
    var daily = false
    var errorDescription: String? { message }
}

/// How each brain is doing: today's requests, when it can be tried again, what went wrong,
/// and what the provider says is left (only where it reports it). Kept on this Mac.
struct BrainEntry: Codable, Equatable {
    var day = ""
    var requests = 0
    var restingUntil: Date?
    var problem: String?
    var lastAnswer: Date?
    var remaining: [String: String] = [:]
    var quotaHeaders: [String: String]?
    var quotaObservedAt: Date?
    var quotaModel: String?
}

/// Everything moi can do, told to every brain the same way.
enum MoiActions {
    static let kinds = ["none", "add", "move", "complete", "delete", "cleanup", "photos", "screenshot", "focus", "open", "search", "show_apps", "quit", "quit_all", "hide_all", "dock_add", "dock_remove", "wallpaper"]
    static let guide = "add = put something new on their plan; move = change when an existing item happens; complete = mark an item done; delete = remove an item from the plan; cleanup = tidy a folder (value: desktop, downloads, documents, pictures or home); photos = find photos by what's in them, place or year and gather them into albums or folders (value: e.g. 'flowers', 'trip in italy', 'dog 2023', 'my trips' for every trip sorted by place, or several joined with 'and'); screenshot = take a screenshot; focus = start a focus timer (value: what on); open = open an app or a website (value: name or site, add 'in private' or 'in safari' etc. if asked); search = search the web (value: query); show_apps = show what's open; quit = quit apps (value: comma-separated names); quit_all = quit everything except (value: comma-separated names to keep, may be empty); hide_all = hide everything except (value: names to keep); dock_add / dock_remove = add or take apps out of the Dock (value: app names); wallpaper = find a photo and make it the desktop wallpaper (value: what to look for, e.g. 'flowers' or 'trip in italy'); none = just talking or answering"
    static let valueGuide = "For add: the thing and when, e.g. 'dentist friday 16:30'. For move: only the new day and 24-hour time, e.g. 'tomorrow 16:30'. For the other actions, as described. Otherwise empty."
    static let targetGuide = "For move, complete or delete: the item's name in the user's words, or 'it' for the one just discussed. Otherwise empty."

    /// One OpenAI-style tool, so cloud brains act instead of guessing at JSON.
    static var tool: [String: Any] {
        ["type": "function", "function": [
            "name": "moi_action",
            "description": "Do one thing on the user's Mac or plan. Use only when the user asks for it. For several things, call it several times. " + guide,
            "parameters": ["type": "object", "properties": [
                "action": ["type": "string", "enum": kinds],
                "target": ["type": "string", "description": targetGuide],
                "value": ["type": "string", "description": valueGuide],
            ], "required": ["action"]],
        ]]
    }
}

@MainActor
final class Intelligence: ObservableObject {
    static let shared = Intelligence()
    @Published var providerID: String { didSet { UserDefaults.standard.set(providerID, forKey: "moi.providerID"); resetModelSession() } }
    @Published var draft = ""
    @Published var messages: [MoiMessage] = []
    /// The latest moi message (Home and the companion read it).
    @Published var reply = ""
    @Published var replySource = ""
    @Published var error: String?
    @Published private(set) var busy = false
    /// A model's suggestion that needs a yes first, and how it reads. `pendingMore` waits with it.
    @Published var pending: MoiIntent?
    private var pendingMore: [MoiIntent] = []
    @Published var pendingSummary = ""
    @Published var pendingVerb = "Yes"
    /// The plan just before moi's last change, for one-step Undo.
    @Published private(set) var canUndo = false
    /// How to reverse moi's last change: the plan as it was, reopening quit apps, the old Dock.
    private var undoStep: (() -> Void)?
    /// What "it" means: the last item moi added or changed.
    private(set) var lastItem: PlanItemRef?
    @Published var events: [ToolEvent] = []
    /// Per brain: usage today, resting, problems. See `BrainEntry`.
    @Published private(set) var ledger: [String: BrainEntry] = (try? JSONDecoder().decode([String: BrainEntry].self, from: UserDefaults.standard.data(forKey: "moi.brainLedger") ?? Data())) ?? [:]
    private var lastCheck: Date?
    @Published var models: [String] = []
    @Published private(set) var verifiedModels: [String: [String]] = [:]
    private var job: Task<Void, Never>?
    private var generation = UUID()
    private var eventLoadFailed = false
    private var appleSession: AnyObject?
    private let eventsURL = MoiPaths.root.appendingPathComponent("action-history.json")
    var provider: AIProvider { AIProvider.find(providerID) }

    init() {
        let legacy = ["Local commands": "moi", "Apple on-device": "apple", "Ollama": "ollama", "Cloud · compatible API": "custom"]
        providerID = UserDefaults.standard.string(forKey: "moi.providerID") ?? legacy[UserDefaults.standard.string(forKey: "moi.provider") ?? ""] ?? (Self.appleReady ? "apple" : "moi")
        do { events = try LocalStorage.load([ToolEvent].self, from: eventsURL, default: []) }
        catch { eventLoadFailed = true; self.error = "Original action history preserved; execution disabled. " + error.localizedDescription }
    }
    var canExecute: Bool { !eventLoadFailed }
    /// Apple's on-device model: free, private, no key. The default brain wherever it's available.
    static var appleReady: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }
    var appleAvailability: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Available on this Mac"
            case .unavailable(let reason): return "Unavailable: \(String(describing: reason))"
            }
        }
        #endif
        return "Requires macOS 26 and an Apple Intelligence compatible device"
    }
    func record(_ kind: String, _ status: String, _ detail: String) {
        guard !eventLoadFailed else { return }
        events.insert(ToolEvent(tool: kind, status: status, detail: detail), at: 0)
        do { try LocalStorage.save(events, to: eventsURL) } catch { self.error = error.localizedDescription; eventLoadFailed = true }
    }
    func clearHistory() { guard !busy, !eventLoadFailed else { return }; events = []; record("History", "Cleared", "User cleared previous action history.") }
    func clearChat() { cancel(); messages = []; reply = ""; replySource = ""; error = nil; pending = nil; resetModelSession() }
    func cancel() { generation = UUID(); job?.cancel(); job = nil; busy = false; VoiceService.shared.cancel() }
    private func resetModelSession() { appleSession = nil }

    private func say(_ text: String, source: String) {
        if MoiPaths.isDevelopment, ProcessInfo.processInfo.environment["MOI_ASK"] != nil { // development failover tests read this
            let url = MoiPaths.root.appendingPathComponent("ask-test.log")
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data("ASK [\(source)] \(text)\n".utf8)); try? handle.close() }
        }
        messages.append(MoiMessage(fromMOI: true, text: text, source: source))
        reply = text; replySource = source
    }

    /// What someone said out loud: handled exactly like typing.
    func heard(_ text: String) {
        guard let store = MoiWorkspace.shared.store else { return }
        draft = text
        respond(store: store)
    }

    /// One message in, moi answers. Order: who moi is → things to do → questions about your day → a model.
    func respond(store: AppStore? = nil) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 12_000, !busy else { return }
        draft = ""; error = nil
        messages.append(MoiMessage(fromMOI: false, text: text))
        // "go" after moi showed the desktop clean-up starts it.
        let reply = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if ScreenTidyStore.shared.awaitingGo, pending == nil, ["go", "yes", "yeah", "yep", "do it", "go ahead", "ok", "okay", "clean it", "sure"].contains(reply) {
            say("On it!", source: "moi")
            Task { await ScreenTidyStore.shared.cleanUp() }
            return
        }
        ScreenTidyStore.shared.awaitingGo = false
        if let store, pending != nil {
            let answer = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "do it", "go ahead", "please", "yes please"].contains(answer) { approvePending(store: store); return }
            if ["no", "nope", "nah", "cancel", "don't", "dont", "no thanks", "never mind", "nevermind"].contains(answer) { pending = nil; pendingSummary = ""; say("Okay, I left it as it was.", source: "moi"); return }
        }
        pending = nil; pendingSummary = ""; pendingMore = []
        // These native planners must receive the person's exact request, regardless of brain.
        if let store, let intent = MoiCommand.intent(from: text, now: Date(), calendar: store.calendar) {
            switch intent {
            case .wallpaper, .cleanUp("screen"): perform(intent, store: store, source: "On your Mac"); return
            default: break
            }
        }
        let primary = provider
        func byRules() -> Bool {
            if let line = MoiPersona.answer(to: text) { say(line, source: "moi"); return true }
            if let store, let intent = MoiCommand.intent(from: text, now: Date(), calendar: store.calendar) { perform(intent, store: store, source: "Done on your Mac"); return true }
            if let store, let question = DayAnswers.question(for: text) { say(DayAnswers.answer(question, data: store.data, now: Date(), calendar: store.calendar), source: "From your plan"); return true }
            return false
        }
        if MoiCommand.intent(from: text) == .undo, let store { perform(.undo, store: store, source: "moi"); return }
        // The main brain asks for its one-time OK here, before anything is sent.
        if primary.needsKey, ready(primary), !UserDefaults.standard.bool(forKey: "moi.consent.\(primary.id)"), !consented(to: primary) { say("Okay, I won't send anything to \(primary.name).", source: "moi"); return }
        let chain = brainChain()
        // A real model reads every request first; Apple's small model and "no AI" let moi's rules go first.
        let smart = chain.first.map { $0.kind != .apple } ?? false
        if !smart, byRules() { return }
        guard !chain.isEmpty else {
            say(primary.kind == .none ? MoiVoice.notUnderstood + " Give me a brain in Settings → Brain & voice and I can understand much more." : "None of my brains can answer right now (\(whyUnavailable(primary))). Settings → Brain & voice shows each one.", source: "moi"); return
        }
        let history = Array(messages.suffix(12))
        generation = UUID()
        let requestID = generation
        busy = true
        job = Task {
            defer { if generation == requestID { busy = false } }
            var failed: [(AIProvider, String)] = []
            for brain in chain {
                do {
                    let answer: (reply: String, intents: [MoiIntent])
                    if brain.kind == .apple {
                        let a = try await askApple(system: system(for: brain, store: store), text: text, history: brain.id == primary.id ? [] : history)
                        answer = (a.reply, a.intent.map { [$0] } ?? [])
                    } else { answer = MoiCommand.parseJSONAnswer(try await ask(brain, system: system(for: brain, store: store), history: history)) }
                    try Task.checkCancellation()
                    guard generation == requestID else { return }
                    noteAnswer(brain)
                    // Who answered, and why it wasn't the main brain if it wasn't.
                    let source = [brain.name, brain.kind == .apple ? nil : Self.shortModel(brain.model), failed.first.map { "\($0.0.name) \($0.1)" }].compactMap { $0 }.joined(separator: " · ")
                    // Small models invent actions; theirs must match what was said. Bigger ones are trusted, with Undo.
                    let careful = brain.kind == .apple
                    let intents = careful ? answer.intents.filter { MoiCommand.grounded($0, in: text) } : answer.intents
                    if let store, !intents.isEmpty { run(intents, store: store, source: source, careful: careful) }
                    else { say(answer.reply, source: source) }
                    return
                } catch is CancellationError { if generation == requestID { say("Okay, stopped.", source: "moi") }; return }
                catch {
                    guard generation == requestID else { return }
                    failed.append((brain, noteFailure(brain, error))) // then straight on to the next brain, same conversation
                }
            }
            if byRules() { return } // every brain is unreachable; moi's own rules still work
            let summary = failed.map { "\($0.0.name) \($0.1)" }.joined(separator: ", ")
            self.error = summary
            say("Hm, none of my brains could answer just now: \(summary). I'll try them again as soon as they're back.", source: "moi")
        }
    }

    /// Brains on this Mac see your plan; a cloud brain only if you turned that on.
    private func system(for brain: AIProvider, store: AppStore?) -> String {
        let seesPlan = brain.local || UserDefaults.standard.bool(forKey: "moi.sharePlan")
        let now = "It is " + Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()) + "."
        let context = now + (store.map { seesPlan ? "\n" + MoiPersona.context(data: $0.data, now: Date(), calendar: $0.calendar) + "\n" + Self.itemList($0.data, calendar: $0.calendar) : "" } ?? "")
        return MoiPersona.instructions(name: MoiVoice.name, context: context)
    }

    // MARK: The brain chain

    private var offline: Bool { UserDefaults.standard.object(forKey: "moi.offline") as? Bool ?? true }

    /// Can this brain be asked at all (key, OK, a model, online)? Says nothing about quota.
    func ready(_ p: AIProvider) -> Bool {
        switch p.kind {
        case .none: return false
        case .apple: return Self.appleReady
        case .ollama: return !p.model.isEmpty
        default:
            if p.local { return !p.model.isEmpty }
            return !offline && !CredentialStore.get(p.keyAccount).isEmpty && (p.id != "custom" || !p.endpoint.isEmpty) && (!p.model.isEmpty || p.free)
        }
    }

    /// Backups must already have their OK; only the main brain may ask for one.
    private func usable(_ p: AIProvider) -> Bool { ready(p) && (!p.needsKey || UserDefaults.standard.bool(forKey: "moi.consent.\(p.id)")) }

    var allowPaidBackups: Bool { UserDefaults.standard.bool(forKey: "moi.allowPaidBackups") }

    /// Who would answer right now, in order.
    func brainChain() -> [AIProvider] {
        let ready = Set(AIProvider.all.filter(usable).map(\.id))
        return BrainChain.order(primary: providerID, ready: ready, allowPaid: allowPaidBackups, resting: ledger.compactMapValues(\.restingUntil), now: Date()).map(AIProvider.find)
    }

    /// Brains that have a key or a model but aren't the main one: the backups.
    var backups: [AIProvider] { brainChain().filter { $0.id != providerID } }

    var selectableBrains: [AIProvider] {
        AIProvider.all.filter { p in
            usable(p) && !(ledger[p.id]?.restingUntil.map { $0 > Date() } ?? false)
                && (p.kind == .apple || verifiedModels[p.id]?.isEmpty == false)
        }
    }

    func quotas(_ p: AIProvider) -> [BrainQuota] {
        guard let entry = ledger[p.id], entry.quotaModel == p.model else { return [] }
        return BrainQuota.read(provider: p.id, headers: entry.quotaHeaders ?? [:])
    }

    /// One short line: how much of the provider's limit is used, when it says; otherwise today's replies.
    func usageSummary(_ p: AIProvider) -> String {
        if let until = ledger[p.id]?.restingUntil, until > Date() { return "Out of quota · back " + Self.when(until) }
        if p.local { return p.kind == .apple ? "On this Mac · no limit" : "On this Mac · no limit" }
        if let quota = quotas(p).first { return "\(Int((quota.usedFraction * 100).rounded()))% of " + (quota.label.lowercased().contains("today") ? "today's" : "its") + " limit used" }
        let n = ledger[p.id]?.requests ?? 0
        return n == 0 ? "Ready" : "\(n) \(n == 1 ? "reply" : "replies") today"
    }

    func whyUnavailable(_ p: AIProvider) -> String {
        if p.needsKey, offline { return "offline mode is on" }
        if p.needsKey, CredentialStore.get(p.keyAccount).isEmpty { return "no key yet" }
        if let entry = ledger[p.id], let until = entry.restingUntil, until > Date() { return (entry.problem ?? "resting") + ", back " + Self.when(until) }
        if let problem = ledger[p.id]?.problem { return problem }
        return ready(p) ? "ready" : "not set up"
    }

    static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "at " + date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func shortModel(_ model: String) -> String? {
        guard !model.isEmpty else { return nil }
        return String(model.split(separator: "/").last ?? Substring(model)).replacingOccurrences(of: ":free", with: "")
    }

    private func update(_ id: String, _ body: (inout BrainEntry) -> Void) {
        var entry = ledger[id] ?? BrainEntry()
        let today = Date().formatted(.iso8601.year().month().day())
        if entry.day != today { entry.day = today; entry.requests = 0 }
        body(&entry)
        ledger[id] = entry
        if let data = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(data, forKey: "moi.brainLedger") }
    }

    private func noteAnswer(_ p: AIProvider) { update(p.id) { $0.requests += 1; $0.restingUntil = nil; $0.problem = nil; $0.lastAnswer = Date() } }

    /// Rests the brain for as long as the failure deserves and returns a short reason.
    @discardableResult
    private func noteFailure(_ p: AIProvider, _ error: Error) -> String {
        let http = error as? HTTPStatusError
        let reason: String
        switch http?.status {
        case 429?: reason = http?.daily == true ? "used up today's free quota" : "is busy (rate limit)"
        case 401?, 403?: reason = "refused the key"
        case let s? where s >= 500: reason = "is having trouble"
        case let s?: reason = "couldn't answer (HTTP \(s))"
        default: reason = p.kind == .apple ? "isn't available" : "couldn't be reached"
        }
        let until = BrainChain.rest(status: http?.status, retryAfter: http?.retryAfter, daily: http?.daily ?? false, now: Date())
        update(p.id) { $0.requests += 1; $0.restingUntil = until; $0.problem = reason }
        record("brain", "Failed", "\(p.name) \(reason): \(error.localizedDescription)")
        return reason
    }

    /// Wakes a resting brain (Settings → "Try again").
    func wake(_ id: String) { update(id) { $0.restingUntil = nil; $0.problem = nil } }

    /// Checks every brain that's set up without spending any quota (lists models, never chats),
    /// so a refused key or a dead connection shows before you type. At most every 5 minutes unless forced.
    func checkBrains(force: Bool = false) async {
        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < 300 { return }
        lastCheck = Date()
        for p in AIProvider.all where ready(p) && p.kind != .apple {
            do {
                let result: [String: Any]
                switch p.kind {
                case .ollama: result = try await requestJSON(try ollamaBase().appendingPathComponent("api/tags"))
                case .anthropic: result = try await requestJSON(try endpointURL(p).appendingPathComponent("models"), headers: ["x-api-key": CredentialStore.get(p.keyAccount), "anthropic-version": "2023-06-01"])
                default: result = try await requestJSON(try endpointURL(p).appendingPathComponent("models"), token: p.local ? nil : CredentialStore.get(p.keyAccount))
                }
                verifiedModels[p.id] = p.kind == .ollama ? (result["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } : (result["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                if p.free { verifiedModels[p.id] = MoiCommand.freeModelCandidates(provider: p.id, available: verifiedModels[p.id] ?? []) }
                if p.kind == .ollama { verifiedModels[p.id]?.removeAll { $0.lowercased().contains("cloud") } }
                // Reachable. A quota rest stays: listing models can't tell whether chatting is allowed again.
                if ledger[p.id]?.problem == "refused the key" || ledger[p.id]?.problem == "couldn't be reached" { wake(p.id) }
            } catch { verifiedModels[p.id] = nil; noteFailure(p, error) }
        }
    }

    /// Several things from one request. Photo searches are merged into one (one result page,
    /// a group each). Risky changes wait for a yes; with a small model, so do plan changes.
    private func run(_ intents: [MoiIntent], store: AppStore, source: String, careful: Bool) {
        var list: [MoiIntent] = [], photos: [String] = []
        for intent in intents { if case let .findPhotos(text) = intent { photos.append(text) } else { list.append(intent) } }
        if !photos.isEmpty { list.append(.findPhotos(photos.joined(separator: " and "))) }
        var ask: [MoiIntent] = []
        for intent in list {
            switch intent {
            case .delete, .quitApps, .dockRemove, .dockAdd: ask.append(intent)
            case .add, .move, .when, .complete: if careful { ask.append(intent) } else { perform(intent, store: store, source: source) }
            default: perform(intent, store: store, source: source)
            }
        }
        if !ask.isEmpty { confirm(ask, store: store, source: source) }
    }

    /// The open items, for brains on this Mac, so "move the dentist" can find it.
    static func itemList(_ data: AppData, calendar: Calendar) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "EEE d MMM HH:mm"
        var lines: [String] = []
        for t in data.tasks.filter({ !$0.isCompleted }).prefix(40) { lines.append("- " + t.title + (t.date.map { " (" + f.string(from: $0) + ")" } ?? "")) }
        for d in data.deadlines.filter({ $0.completedAt == nil }).prefix(20) { lines.append("- " + d.title + " (due " + f.string(from: d.date) + ")") }
        return lines.isEmpty ? "" : "Their open items:\n" + lines.joined(separator: "\n")
    }

    /// Does one intent and says exactly what happened. Plan changes can be undone in one step.
    func perform(_ intent: MoiIntent, store: AppStore, source: String) {
        guard canExecute else { say("I can't keep a record of actions right now, so I won't change anything.", source: "moi"); return }
        let cal = store.calendar, now = Date()
        func change(_ body: (inout AppData) -> Void) {
            guard !store.isReadOnly else { say("Your plan is in read-only recovery mode, so I won't change it.", source: "moi"); return }
            let snapshot = store.data; undoStep = { store.update { $0 = snapshot } }; canUndo = true
            store.update(body)
        }
        func find(_ ref: ItemRef) -> PlanItemRef? {
            let item = MoiCommand.resolve(ref, in: store.data, last: lastItem)
            if item == nil { say(ref == .last ? "Which one? Say its name, like “move gym to 5pm”." : "I couldn't find that in your plan. Try its name as it appears in Plan.", source: "moi") }
            return item
        }
        switch intent {
        case let .add(phrase):
            guard !store.isReadOnly else { say("Your plan is in read-only recovery mode, so I won't change it.", source: "moi"); return }
            let snapshot = store.data; undoStep = { store.update { $0 = snapshot } }; canUndo = true
            guard let parsed = store.quickAdd(phrase) else { say("There was nothing to add.", source: "moi"); return }
            lastItem = parsed.isDeadline ? store.data.deadlines.last.map { .deadline($0.id) } : store.data.tasks.last.map { .task($0.id) }
            record("add", "Completed", parsed.title)
            let done = "Added " + MoiCommand.describe(parsed, now: now, calendar: cal) + "."
            say(parsed.date == nil && parsed.time == nil ? done + " When should it happen? You can say “tomorrow at 4pm”." : done, source: source)
        case let .move(ref, phrase):
            guard let item = find(ref) else { return }
            var result: ParsedQuickTask?
            change { result = MoiCommand.move(item, to: phrase, in: &$0, now: now, calendar: cal) }
            guard let result else { say("I didn't catch when. Try “tomorrow at 16:30”.", source: "moi"); return }
            lastItem = item; record("move", "Completed", result.title)
            say("Moved " + MoiCommand.describe(result, now: now, calendar: cal) + ".", source: source)
        case let .when(phrase):
            guard lastItem != nil else { say("When for what? Tell me the thing too, like “gym tomorrow 16:30”.", source: "moi"); return }
            perform(.move(.last, when: phrase), store: store, source: source)
        case let .complete(ref):
            guard let item = find(ref), let title = MoiCommand.title(of: item, in: store.data) else { return }
            change { MoiCommand.complete(item, in: &$0, now: now) }
            lastItem = item; record("complete", "Completed", title)
            say(MoiVoice.completed(count: store.data.tasks.filter { $0.completedAt.map { cal.isDate($0, inSameDayAs: now) } ?? false }.count) + " (“\(title)”)", source: source)
        case let .delete(ref):
            guard let item = find(ref), let title = MoiCommand.title(of: item, in: store.data) else { return }
            change { MoiCommand.delete(item, in: &$0) }
            if lastItem == item { lastItem = nil }
            record("delete", "Completed", title)
            say("Deleted “\(title)”. Say “undo” if that was a mistake.", source: source)
        case let .cleanUp(folder):
            let tidy = TidyStore.shared
            if folder == "screen" || folder == nil || folder == "desktop" { // "clean up my desktop" means the whole thing: files and idle apps
                tidy.tab = .screen
                MoiWorkspace.shared.showMain(.clean); ScreenTidyStore.shared.preview()
                let screen = ScreenTidyStore.shared
                screen.awaitingGo = true
                say("Here's your desktop: \(screen.summary.prefix(1).lowercased() + screen.summary.dropFirst()). Say “go” and I'll tidy it, or change anything first.", source: source)
                return
            }
            tidy.folder = TidyStore.Folder(spoken: folder ?? "desktop")
            tidy.tab = .files
            MoiWorkspace.shared.showMain(.clean); tidy.preview()
            say("Here's what's loose in \(tidy.folder.title). Nothing moves until you choose.", source: source)
        case .screenshot:
            NotchPanelView.openScreenshotApp()
            say("Here's the screenshot bar. It saves where macOS always does.", source: source)
        case let .findPhotos(text):
            TidyStore.shared.tab = .photos
            MoiWorkspace.shared.showMain(.clean)
            PhotoFinder.shared.search(text)
            let titles = PhotoQuery.parseAll(text).map { $0.trips && $0.subjects.isEmpty ? "your trips" : $0.title.lowercased() }
            say("Looking through your photos for \(ListFormatter.localizedString(byJoining: titles)). They'll show up in Clean up, a group each, and nothing changes until you choose: albums in Photos, or folders for files.", source: source)
        case let .wallpaper(text):
            TidyStore.shared.tab = .photos; MoiWorkspace.shared.showMain(.clean)
            say("Looking for your best-looking photo…", source: source)
            PhotoFinder.shared.recommendWallpaper(text) { finder in
                // They asked moi to choose, so moi chooses: the top pick goes up, the rest stay one tap away.
                guard let best = finder.wallpaperPicks.first else { self.say(finder.error ?? finder.message, source: "moi"); return }
                Task {
                    await finder.applyWallpaper(best)
                    guard finder.applied == best.id else { self.say(finder.error ?? "I couldn't change the wallpaper.", source: "moi"); return }
                    self.undoStep = { finder.restoreWallpaper() }; self.canUndo = true
                    self.say("Done! I went with this one: \(best.reason.prefix(1).lowercased() + best.reason.dropFirst()). Not your favourite? Four more are in Clean up → Photos, or say “undo”.", source: source)
                }
            }
        case .showApps:
            TidyStore.shared.tab = .apps
            MoiWorkspace.shared.showMain(.clean)
            let apps = MacControl.openApps()
            say("\(apps.count) apps are open, with \(apps.reduce(0) { $0 + $1.windows }) windows. Pick the ones to quit or hide in Clean up → Open apps.", source: source)
        case let .quitApps(names, allExcept):
            let targets = MacControl.targets(names, allExcept: allExcept)
            guard !targets.isEmpty else { say(allExcept == nil ? "None of those are open." : "Nothing else is open.", source: "moi"); return }
            let quit = MacControl.quit(targets)
            undoStep = { MacControl.reopen(quit) }; canUndo = true
            record("quit", "Completed", quit.map(\.name).joined(separator: ", "))
            say("Asked \(quit.count == 1 ? quit[0].name : "\(quit.count) apps") to quit" + (quit.count > 1 ? ": " + quit.map(\.name).joined(separator: ", ") : "") + ". Anything with unsaved work will ask first. Say “undo” to reopen.", source: source)
        case let .hideApps(keep):
            let targets = MacControl.targets([], allExcept: keep)
            MacControl.hide(targets)
            say("Hid \(targets.count) apps." + (keep.isEmpty ? "" : " \(keep.joined(separator: ", ")) stays."), source: source)
        case let .dockRemove(names):
            let before = MacControl.dockItems()
            let (after, removed) = DockLayout.removing(names, from: before)
            guard !removed.isEmpty else { say("I couldn't find \(names.joined(separator: ", ")) in your Dock.", source: "moi"); return }
            MacControl.setDockItems(after)
            undoStep = { MacControl.setDockItems(before) }; canUndo = true
            record("dock", "Completed", "removed " + removed.joined(separator: ", "))
            say("Took \(removed.joined(separator: ", ")) out of your Dock. The apps are still installed. Say “undo” to put \(removed.count == 1 ? "it" : "them") back.", source: source)
        case let .dockAdd(names):
            let before = MacControl.dockItems()
            var after = before, added: [String] = []
            for name in names { if let url = MacControl.appURL(named: name) { after = DockLayout.adding(appAt: url, bundleID: Bundle(url: url)?.bundleIdentifier, to: after); added.append(url.deletingPathExtension().lastPathComponent) } }
            guard !added.isEmpty, after.count != before.count else { say(added.isEmpty ? "I couldn't find that app on your Mac." : "It's already in your Dock.", source: "moi"); return }
            MacControl.setDockItems(after)
            undoStep = { MacControl.setDockItems(before) }; canUndo = true
            record("dock", "Completed", "added " + added.joined(separator: ", "))
            say("Added \(added.joined(separator: ", ")) to your Dock.", source: source)
        case .showDock:
            TidyStore.shared.tab = .dock
            MoiWorkspace.shared.showMain(.clean)
            say("Here's your Dock. Pick apps to take out, or add one. You can always restore it.", source: source)
        case let .webSearch(query):
            guard let url = Web.search(query) else { return }
            NSWorkspace.shared.open(url); record("search", "Completed", query)
            say("Searching the web for “\(query)”.", source: source)
        case let .focus(title, minutes):
            guard !store.isReadOnly else { return }
            let name = title.isEmpty ? (NextUpEngine.items(data: store.data, now: now, calendar: cal, limit: 1).first?.title ?? "Focus") : title.prefix(1).uppercased() + title.dropFirst()
            store.startFocus(title: name, durationMinutes: min(240, max(1, minutes ?? 25)))
            record("focus", "Completed", name)
            say(MoiVoice.focusStarted(name, minutes: min(240, max(1, minutes ?? 25))), source: source)
        case let .open(name, browser, isPrivate):
            let apps = MoiWorkspace.shared.applications
            let app = apps.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) ?? (name.count > 3 ? apps.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) : nil)
            if let app, browser == nil, !isPrivate {
                Task {
                    do { try await MoiWorkspace.shared.openApplication(app.bundleID); record("open", "Completed", app.name); say(MoiVoice.opened(app.name), source: source) }
                    catch { say(MoiVoice.failed("open \(app.name)", reason: error.localizedDescription), source: "moi") }
                }
                return
            }
            guard let url = Web.url(for: name) else { say("I couldn't find an app or website called “\(name)”.", source: "moi"); return }
            do {
                try MacControl.open(url, browser: browser, private: isPrivate)
                record("open", "Completed", url.host ?? name)
                say("Opened \(url.host ?? name)" + (isPrivate ? " in a private window" : "") + (browser.map { " in \($0)" } ?? "") + ".", source: source)
            } catch { say(error.localizedDescription, source: "moi") }
        case .undo:
            guard let step = undoStep else { say("There's nothing for me to undo.", source: "moi"); return }
            // ponytail: one step back, restoring a snapshot; edits made elsewhere since then are undone too
            step()
            undoStep = nil; canUndo = false; record("undo", "Completed", "")
            say("Undone. It's back the way it was.", source: source)
        }
    }

    /// Shows exactly what a model wants to change and waits for a yes (typed, tapped or said).
    private func confirm(_ intents: [MoiIntent], store: AppStore, source: String) {
        var lines: [String] = []
        for intent in intents { if let line = summary(of: intent, store: store) { lines.append(line) } }
        guard let first = intents.first, lines.count == intents.count else { say("I'm not sure which item you mean. Try its name as it appears in Plan.", source: source); return }
        pending = first; pendingMore = Array(intents.dropFirst())
        pendingSummary = lines.count == 1 ? lines[0] : lines.joined(separator: " ")
        pendingVerb = intents.count > 1 ? "Yes, do all \(intents.count)" : { switch first { case .add: "Yes, add it"; case .move, .when: "Yes, move it"; case .complete: "Yes, it's done"; case .delete: "Yes, delete it"; case .quitApps: "Yes, quit"; default: "Yes" } }()
        say(pendingSummary + " Say or tap yes.", source: source)
    }

    private func summary(of intent: MoiIntent, store: AppStore) -> String? {
        let now = Date(), cal = store.calendar
        func name(_ ref: ItemRef) -> String? { MoiCommand.resolve(ref, in: store.data, last: lastItem).flatMap { MoiCommand.title(of: $0, in: store.data) } }
        func when(_ phrase: String) -> String {
            let p = QuickAddParser.parse(phrase, now: now, calendar: cal)
            return MoiCommand.describe(ParsedQuickTask(title: "", date: p.date, time: p.time, category: .personal), now: now, calendar: cal).replacingOccurrences(of: "“” for ", with: "")
        }
        let summary: String?
        switch intent {
        case let .add(phrase): summary = "Add " + MoiCommand.describe(QuickAddParser.parse(phrase, now: now, calendar: cal, categories: ItemCategory.options(in: store.data)), now: now, calendar: cal) + "?"
        case let .move(ref, phrase): summary = name(ref).map { "Move “\($0)” to " + when(phrase) + "?" }
        case let .when(phrase): summary = name(.last).map { "Move “\($0)” to " + when(phrase) + "?" }
        case let .complete(ref): summary = name(ref).map { "Mark “\($0)” done?" }
        case let .delete(ref): summary = name(ref).map { "Delete “\($0)”?" }
        case let .quitApps(names, keep):
            let targets = MacControl.targets(names, allExcept: keep)
            summary = targets.isEmpty ? nil : "Quit " + targets.map(\.name).joined(separator: ", ") + "?"
        case let .dockRemove(names): summary = "Take \(names.joined(separator: ", ")) out of your Dock?"
        case let .dockAdd(names): summary = "Add \(names.joined(separator: ", ")) to your Dock?"
        default: summary = nil
        }
        return summary
    }

    func approvePending(store: AppStore) {
        guard let intent = pending else { return }
        let more = pendingMore
        pending = nil; pendingSummary = ""; pendingMore = []
        for each in [intent] + more { perform(each, store: store, source: "Done on your Mac") }
    }

    func undo(store: AppStore) { perform(.undo, store: store, source: "moi") }

    /// One clear OK per cloud provider, remembered. (The old build asked before every message.)
    private func consented(to provider: AIProvider) -> Bool {
        let key = "moi.consent.\(provider.id)"
        if UserDefaults.standard.bool(forKey: key) { return true }
        let alert = NSAlert()
        alert.messageText = "Send your Ask moi messages to \(provider.name)?"
        alert.informativeText = "From now on, what you type in Ask moi (and the recent conversation) goes to \(provider.name) using your key. Your schedule, files, photos and audio are never included. Their pricing, limits and data policy apply. You can switch back to an on-Mac brain any time."
        alert.addButton(withTitle: "Send to \(provider.name)"); alert.addButton(withTitle: "Not now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    /// Apple's model answers in a fixed shape (reply + one optional action), so it can't ramble
    /// into broken JSON. It only decides *what*; dates are still read by `QuickAddParser`.
    private func askApple(system: String, text: String, history: [MoiMessage] = []) async throws -> (reply: String, intent: MoiIntent?) {
        try Self.simulatedFailure("apple")
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else { throw MoiError.message(appleAvailability) }
            let string = DynamicGenerationSchema(type: String.self)
            let root = DynamicGenerationSchema(name: "Answer", properties: [
                .init(name: "reply", description: "What moi says back: short, warm, one to three sentences. Answer questions directly.", schema: string),
                .init(name: "action", description: MoiActions.guide, schema: DynamicGenerationSchema(name: "Action", anyOf: MoiActions.kinds)),
                .init(name: "target", description: MoiActions.targetGuide, schema: string),
                .init(name: "value", description: MoiActions.valueGuide, schema: string),
            ])
            let schema = try GenerationSchema(root: root, dependencies: [])
            // As a stand-in for another brain, it gets the recent conversation so the chat carries on.
            let earlier = history.dropLast().suffix(8).map { ($0.fromMOI ? "moi: " : "Them: ") + $0.text }.joined(separator: "\n")
            let session = earlier.isEmpty ? ((appleSession as? LanguageModelSession) ?? LanguageModelSession(instructions: system)) : LanguageModelSession(instructions: system + "\nThe conversation so far:\n" + earlier)
            if earlier.isEmpty { appleSession = session }
            let content = try await session.respond(to: text, schema: schema).content
            func field(_ name: String) -> String { ((try? content.value(String.self, forProperty: name)) ?? "").trimmingCharacters(in: .whitespaces) }
            let reply = field("reply")
            return (reply.isEmpty ? "Hm, I lost my words there. Try again?" : reply, MoiCommand.intent(kind: field("action"), target: field("target"), value: field("value")))
        }
        #endif
        throw MoiError.message(appleAvailability)
    }

    private func ask(_ provider: AIProvider, system: String, history: [MoiMessage]) async throws -> String {
        try Self.simulatedFailure(provider.id)
        let turns = history.map { ["role": $0.fromMOI ? "assistant" : "user", "content": $0.text] }
        // Whatever the provider says is left (Groq, OpenRouter, NVIDIA… send x-ratelimit-remaining-*).
        var responseModel = provider.model
        let remember: (HTTPURLResponse) -> Void = { [weak self] response in
            let left = response.allHeaderFields.reduce(into: [String: String]()) { found, pair in
                if let name = (pair.key as? String)?.lowercased(), name.contains("ratelimit-remaining") { found[name] = "\(pair.value)" }
            }
            if !left.isEmpty { self?.update(provider.id) { $0.remaining = left } }
            let quota = response.allHeaderFields.reduce(into: [String: String]()) { found, pair in
                if let name = (pair.key as? String)?.lowercased(), name.hasPrefix("x-ratelimit-") { found[name] = "\(pair.value)" }
            }
            if !quota.isEmpty { self?.update(provider.id) { $0.quotaHeaders = quota; $0.quotaObservedAt = Date(); $0.quotaModel = responseModel } }
        }
        switch provider.kind {
        case .none: return ""
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                guard case .available = SystemLanguageModel.default.availability else { throw MoiError.message(appleAvailability) }
                let session = (appleSession as? LanguageModelSession) ?? LanguageModelSession(instructions: system)
                appleSession = session
                return try await session.respond(to: history.last?.text ?? "").content
            }
            #endif
            throw MoiError.message(appleAvailability)
        case .ollama:
            let base = try ollamaBase()
            let model = provider.model
            guard !model.isEmpty else { throw MoiError.message("Pick one of your installed Ollama models in Settings → AI. I never download models myself.") }
            let metadata = try await requestJSON(base.appendingPathComponent("api/show"), body: ["model": model])
            guard metadata["remote_host"] == nil, metadata["remote_model"] == nil, !model.lowercased().contains("cloud"), let info = metadata["model_info"] as? [String: Any], !info.isEmpty else { throw MoiError.message("That model can't be verified as installed on this Mac. Cloud-routed Ollama models are refused.") }
            let result = try await requestJSON(base.appendingPathComponent("api/chat"), body: ["model": model, "stream": false, "messages": [["role": "system", "content": system]] + turns])
            guard let message = result["message"] as? [String: Any], let content = message["content"] as? String else { throw MoiError.message("Ollama returned no message.") }
            return content
        case .openAI:
            let base = try endpointURL(provider)
            // A free key added without a model (or whose model vanished) gets one that answers, on the spot.
            if provider.model.isEmpty, provider.free, let model = try await firstWorkingModel(provider, excluding: []) { provider.model = model }
            guard !provider.model.isEmpty else { throw MoiError.message("Choose a \(provider.name) model in Settings → AI.") }
            let key = provider.local ? nil : CredentialStore.get(provider.keyAccount)
            responseModel = provider.model
            var request: [String: Any] = ["model": provider.model, "messages": [["role": "system", "content": system]] + turns, "max_tokens": 2_048, "tools": [MoiActions.tool], "tool_choice": "auto"]
            // Gemini's Flash models otherwise think out loud into the reply and run out of room before acting.
            if provider.id == "gemini" { request["reasoning_effort"] = "low" }
            let result: [String: Any]
            do { result = try await requestJSON(base.appendingPathComponent("chat/completions"), body: request, token: key, response: remember) }
            catch let error as HTTPStatusError where [429, 500, 502, 503, 504].contains(error.status) && provider.needsKey {
                // Quota used up (429): move to the next free model for good. Busy (5xx): use it just this once.
                guard let next = try await firstWorkingModel(provider, excluding: [provider.model]) else { throw error }
                if error.status == 429 { provider.model = next }
                request["model"] = next
                responseModel = next
                result = try await requestJSON(base.appendingPathComponent("chat/completions"), body: request, token: key, response: remember)
            }
            guard let choices = result["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] else { throw MoiError.message("\(provider.name) sent back nothing.") }
            let content = message["content"] as? String ?? ""
            // A tool call becomes the same {"reply", "action"} shape every brain uses.
            let actions: [[String: Any]] = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call in
                guard let function = call["function"] as? [String: Any], let arguments = (function["arguments"] as? String)?.data(using: .utf8),
                      let action = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any] else { return nil }
                return ["kind": action["action"] ?? "none", "target": action["target"] ?? "", "value": action["value"] ?? ""]
            }
            if !actions.isEmpty { return String(decoding: try JSONSerialization.data(withJSONObject: ["reply": content, "actions": actions]), as: UTF8.self) }
            guard !content.isEmpty else { throw MoiError.message("\(provider.name) sent back no text.") }
            return content
        case .anthropic:
            let base = try endpointURL(provider)
            guard !provider.model.isEmpty else { throw MoiError.message("Choose a Claude model in Settings → AI.") }
            let function = MoiActions.tool["function"] as? [String: Any] ?? [:]
            let tool: [String: Any] = ["name": function["name"] ?? "moi_action", "description": function["description"] ?? "", "input_schema": function["parameters"] ?? [:]]
            let result = try await requestJSON(base.appendingPathComponent("messages"), body: ["model": provider.model, "max_tokens": 1_024, "system": system, "messages": turns, "tools": [tool]], headers: ["x-api-key": CredentialStore.get(provider.keyAccount), "anthropic-version": "2023-06-01"], response: remember)
            guard let content = result["content"] as? [[String: Any]] else { throw MoiError.message("Claude sent back no text.") }
            let text = content.compactMap { $0["text"] as? String }.joined()
            let actions: [[String: Any]] = content.filter { $0["type"] as? String == "tool_use" }.compactMap { block in
                guard let input = block["input"] as? [String: Any] else { return nil }
                return ["kind": input["action"] ?? "none", "target": input["target"] ?? "", "value": input["value"] ?? ""]
            }
            if !actions.isEmpty { return String(decoding: try JSONSerialization.data(withJSONObject: ["reply": text, "actions": actions]), as: UTF8.self) }
            return text
        }
    }

    private func endpointURL(_ provider: AIProvider) throws -> URL {
        guard let url = URL(string: provider.endpoint), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw MoiError.message("That address doesn't look right. Check it in Settings → AI.") }
        if provider.local { guard ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "") else { throw MoiError.message("\(provider.name) must run on this Mac (localhost).") } }
        else { guard url.scheme == "https", url.host != nil else { throw MoiError.message("Cloud addresses must use HTTPS.") } }
        return url
    }

    func ollamaBase() throws -> URL {
        let raw = UserDefaults.standard.string(forKey: "moi.ollamaURL") ?? "http://127.0.0.1:11434"
        guard let url = URL(string: raw), ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""), ["http","https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw MoiError.message("Use a loopback Ollama URL without credentials or query.") }
        return url
    }

    /// Any key in one step: works out whose it is, saves it in the Keychain, picks a model that
    /// answers, and adds it to the chain (as the main brain if there's no real one yet). The person
    /// pressed "Add" after reading what gets sent, which is the one-time OK. Returns what happened.
    func addKey(_ raw: String, provider chosen: String? = nil) async -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = chosen ?? BrainChain.detect(key: key) else { return "I can't tell whose key that is. Pick the provider and try again." }
        let provider = AIProvider.find(id)
        guard provider.needsKey else { return "That provider doesn't need a key." }
        do { try CredentialStore.set(key, account: provider.keyAccount) } catch { return error.localizedDescription }
        UserDefaults.standard.set(true, forKey: "moi.consent.\(provider.id)")
        UserDefaults.standard.set(false, forKey: "moi.offline")
        wake(provider.id)
        do {
            if provider.free || provider.model.isEmpty {
                guard let model = try await firstWorkingModel(provider, excluding: []) else { return "\(provider.name) accepted the key, but none of its free models answered. New keys sometimes need a few minutes; try again shortly." }
                provider.model = model
            }
            let main = [AIProvider.Kind.none, .apple].contains(self.provider.kind) || !ready(self.provider)
            if main { providerID = provider.id } else { objectWillChange.send() }
            return main ? "Done. \(provider.name) is now my brain." : "Added \(provider.name) as a backup. If \(self.provider.name) runs out, \(provider.name) answers instead."
        } catch {
            try? CredentialStore.set("", account: provider.keyAccount)
            return "\(provider.name) didn't accept that key: \(error.localizedDescription)"
        }
    }

    /// Development only: `MOI_FAIL_BRAINS="gemini:429,apple:503"` makes those brains fail, to test failover.
    private static func simulatedFailure(_ id: String) throws {
        guard MoiPaths.isDevelopment, let spec = ProcessInfo.processInfo.environment["MOI_FAIL_BRAINS"] else { return }
        for part in spec.split(separator: ",") {
            let bits = part.split(separator: ":").map(String.init)
            guard bits.first == id, let status = Int(bits.last ?? "") else { continue }
            throw HTTPStatusError(status: status, message: "Simulated failure (HTTP \(status)).", retryAfter: nil, daily: status == 429)
        }
    }

    /// Tries the safe free models in order with a tiny request and returns the first that answers.
    private func firstWorkingModel(_ provider: AIProvider, excluding: Set<String>) async throws -> String? {
        let key = CredentialStore.get(provider.keyAccount)
        let list = try await requestJSON(try endpointURL(provider).appendingPathComponent("models"), token: key)
        let ids = (list["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.map { $0.replacingOccurrences(of: "models/", with: "") }
        for model in MoiCommand.freeModelCandidates(provider: provider.id, available: ids) where !excluding.contains(model) {
            let probe: [String: Any] = ["model": model, "max_tokens": 5, "messages": [["role": "user", "content": "hi"]]]
            if (try? await requestJSON(try endpointURL(provider).appendingPathComponent("chat/completions"), body: probe, token: key)) != nil { return model }
        }
        return nil
    }

    /// Installed or available models for the chosen provider (never downloads anything).
    func refreshModels() {
        let provider = self.provider
        job = Task {
            do {
                switch provider.kind {
                case .ollama:
                    let result = try await requestJSON(try ollamaBase().appendingPathComponent("api/tags"))
                    models = (result["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.filter { !$0.lowercased().contains("cloud") }
                case .openAI:
                    let result = try await requestJSON(try endpointURL(provider).appendingPathComponent("models"), token: provider.local ? nil : CredentialStore.get(provider.keyAccount))
                    models = (result["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
                case .anthropic:
                    let result = try await requestJSON(try endpointURL(provider).appendingPathComponent("models"), headers: ["x-api-key": CredentialStore.get(provider.keyAccount), "anthropic-version": "2023-06-01"])
                    models = (result["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                case .apple, .none: models = []
                }
                if models.isEmpty { error = "No models found for \(provider.name)." }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func requestJSON(_ url: URL, body: [String: Any]? = nil, token: String? = nil, headers: [String: String] = [:], response onResponse: ((HTTPURLResponse) -> Void)? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 60)
        if let body { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        if let token, !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard data.count <= 5_000_000 else { throw MoiError.message("That reply was too large.") }
        if let http = response as? HTTPURLResponse { onResponse?(http) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Say what the provider actually said (e.g. which quota ran out), not just the code.
            let body = (try? JSONSerialization.jsonObject(with: data)).flatMap { ($0 as? [String: Any]) ?? ($0 as? [[String: Any]])?.first }
            let said = ((body?["error"] as? [String: Any])?["message"] as? String).map { " They said: " + String($0.prefix(220)) } ?? ""
            let limit = BrainChain.readLimit(body: String(decoding: data.prefix(20_000), as: UTF8.self), retryAfterHeader: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"))
            throw HTTPStatusError(status: status, message: (status == 401 || status == 403 ? "The key was refused (HTTP \(status))." : status == 429 ? "The provider says slow down, or this model's free quota is used up (HTTP 429)." : "The request failed (HTTP \(status)).") + said, retryAfter: limit.retryAfter, daily: status == 429 && limit.daily)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MoiError.message("That reply wasn't readable.") }
        return object
    }
}
