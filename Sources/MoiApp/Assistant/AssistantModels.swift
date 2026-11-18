import Carbon
import Foundation

enum AIProviderID: String, Codable, CaseIterable, Identifiable {
    case appleIntelligence = "Apple Intelligence"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case both = "Both"
    var id: String { rawValue }

    /// True when the provider runs entirely on this Mac — no key, no network, no data leaving the device.
    var isOnDevice: Bool { self == .appleIntelligence }
}

enum NotchShortcut: String, CaseIterable, Identifiable {
    case optionSpace, controlSpace, optionA
    var id: String { rawValue }
    var label: String { switch self { case .optionSpace: "Option + Space"; case .controlSpace: "Control + Space"; case .optionA: "Option + A" } }
    var keyCode: UInt32 { switch self { case .optionSpace, .controlSpace: 49; case .optionA: 0 } }
    var modifiers: UInt32 { switch self { case .optionSpace, .optionA: UInt32(optionKey); case .controlSpace: UInt32(controlKey) } }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case user, assistant, system }
    var id = UUID()
    var role: Role
    var content: String
    var provider: AIProviderID?
    var createdAt = Date()
    var usedPersonalContext = false
}

struct ConversationMetadata: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var updatedAt = Date()
    var provider: AIProviderID
    var messageCount = 0
}

struct ConversationFile: Codable {
    var id: UUID
    var messages: [ChatMessage]
}

struct AIUsageRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var provider: AIProviderID
    var timestamp = Date()
    var model: String
    var inputTokens: Int?
    var outputTokens: Int?
}

struct KnowledgeNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var body: String
    var projectID: UUID?
    var createdAt = Date()
    var updatedAt = Date()
}

struct AssistantIndex: Codable {
    var conversations: [ConversationMetadata] = []
    var notes: [KnowledgeNote] = []
    var usage: [AIUsageRecord] = []
}

struct AssistantArchive: Codable {
    var index: AssistantIndex
    var conversations: [String: ConversationFile]
}

struct ComprehensiveBackup: Codable {
    var exportedAt = Date()
    var appData: AppData
    var assistant: AssistantArchive
}

struct NotchPreferences {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let panelEnabled = "assistant.panelEnabled"
        static let shortcut = "assistant.shortcut"
        static let opensOnHover = "assistant.opensOnHover"
    }
    /// When false, the glance opens only on a click at the notch (or the shortcut).
    var opensOnHover: Bool {
        get { defaults.object(forKey: Key.opensOnHover) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.opensOnHover) }
    }
    var panelEnabled: Bool {
        get { defaults.object(forKey: Key.panelEnabled) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.panelEnabled) }
    }
    var shortcut: NotchShortcut {
        get { NotchShortcut(rawValue: defaults.string(forKey: Key.shortcut) ?? "optionSpace") ?? .optionSpace }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.shortcut) }
    }
    /// The parts of the glance, in order. Missing ones are switched off.
    var parts: [NotchPart] {
        get { (defaults.stringArray(forKey: "moi.notchParts") ?? ["music", "tasks", "files"]).compactMap(NotchPart.init) }
        nonmutating set { defaults.set(newValue.map(\.rawValue), forKey: "moi.notchParts") }
    }
    /// Like an iPhone: while music plays or Focus runs, the notch stays a little wider with art and a timer.
    var liveActivity: Bool {
        get { defaults.object(forKey: "moi.notchLive") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "moi.notchLive") }
    }
}

/// One optional part of the notch glance.
enum NotchPart: String, CaseIterable, Identifiable {
    case music, tasks, calendar, weather, files
    var id: String { rawValue }
    var title: String {
        switch self {
        case .music: "Music"
        case .tasks: "Now & next"
        case .calendar: "Calendar"
        case .weather: "UV & weather"
        case .files: "Recent files"
        }
    }
    var symbol: String {
        switch self {
        case .music: "music.note"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .weather: "sun.max"
        case .files: "tray.and.arrow.down"
        }
    }
    var detail: String {
        switch self {
        case .music: "What's playing, with controls. Spotify or Apple Music."
        case .tasks: "What you're doing now and the next thing to tick off."
        case .calendar: "Today's date and your next event from Calendar."
        case .weather: "The UV index and temperature where you are."
        case .files: "Newest downloads and screenshots, ready to drag."
        }
    }
}

enum LauncherAliasStore {
    static func aliases(for id: UUID) -> [String] {
        UserDefaults.standard.stringArray(forKey: "launcher.aliases.\(id.uuidString)") ?? []
    }
    static func set(_ aliases: [String], for id: UUID) {
        UserDefaults.standard.set(aliases.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, forKey: "launcher.aliases.\(id.uuidString)")
    }
}
