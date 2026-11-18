import Foundation

struct ItemCategory: RawRepresentable, Codable, CaseIterable, Identifiable, Hashable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    static let work = Self(rawValue: "Work")
    static let study = Self(rawValue: "Study")
    static let creative = Self(rawValue: "Creative")
    static let gym = Self(rawValue: "Gym")
    static let personal = Self(rawValue: "Personal")
    static let deadline = Self(rawValue: "Deadline")
    static let deepWork = Self(rawValue: "Deep Work")
    static let admin = Self(rawValue: "Admin")
    /// Generic built-ins only. A person's own categories (whatever their data already uses, plus
    /// any they add in Settings) come from `options(in:)`, so nothing personal ships in the code.
    static let allCases: [Self] = [.personal, .work, .study, .creative, .gym, .deepWork, .admin, .deadline]
    static func options(in data: AppData) -> [Self] {
        var seen = Set(allCases), result = allCases
        let used = data.settings.customCategories.map(Self.init(rawValue:)) + data.scheduleBlocks.map(\.category) + data.tasks.map(\.category) + data.projects.map(\.category) + data.deadlines.map(\.category)
        for category in used where !category.rawValue.isEmpty && seen.insert(category).inserted { result.append(category) }
        return result
    }
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .study: "book.closed"
        case .creative: "paintbrush"
        case .gym: "figure.strengthtraining.traditional"
        case .personal: "person"
        case .deadline: "flag"
        case .deepWork: "brain.head.profile"
        case .admin: "tray.full"
        default: "tag"
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low, normal, high, critical
    var id: String { rawValue }
    var rank: Int { switch self { case .low: 0; case .normal: 1; case .high: 2; case .critical: 3 } }
    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
}

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case primary = "ACTIVE / PRIMARY"
    case active = "ACTIVE"
    case maintenance = "MAINTENANCE"
    case backup = "BACKUP / TRACKED"
    case upcoming = "UPCOMING"
    case tentative = "TENTATIVE"
    case completed = "COMPLETED"
    var id: String { rawValue }
}

enum CompletionState: String, Codable, CaseIterable {
    case completed, skipped, moved, unfinished
}

struct LocalTime: Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(_ hour: Int, _ minute: Int = 0) { self.hour = hour; self.minute = minute }
    static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
    var display: String { String(format: "%02d:%02d", hour, minute) }
}

struct NotificationRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var minutesBefore: [Int]
    var atStart: Bool
    var minutesBeforeEnd: [Int]
    var atEnd: Bool
    var followUpMinutes: Int?

    static let scheduleDefault = NotificationRule(minutesBefore: [10], atStart: true, minutesBeforeEnd: [10], atEnd: true, followUpMinutes: 15)
}

struct RecurringRule: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Calendar weekday: Sunday = 1 ... Saturday = 7
    var weekdays: Set<Int>
    var startDate: Date
    var endDate: Date?
}

struct ScheduleBlock: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var startTime: LocalTime
    var endTime: LocalTime
    var category: ItemCategory
    var recurrence: RecurringRule
    var isEnabled = true
    var notificationRule: NotificationRule = .scheduleDefault
    var projectID: UUID?
    var workspaceItemIDs: [UUID] = []
    var notes = ""
}

struct DailyOverride: Identifiable, Codable, Hashable {
    var id = UUID()
    var blockID: UUID
    var date: Date
    var replacementTitle: String?
    var replacementStart: LocalTime?
    var replacementEnd: LocalTime?
    var isSkipped = false
}

struct CompletionRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var sourceID: UUID
    var occurrenceDate: Date
    var state: CompletionState
    var recordedAt = Date()
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes = ""
    var date: Date?
    var startTime: LocalTime?
    var durationMinutes: Int?
    var deadline: Date?
    var priority: Priority = .normal
    var projectID: UUID?
    var scheduleBlockID: UUID?
    var category: ItemCategory = .personal
    var recurrence: RecurringRule?
    var notificationMinutesBefore: [Int] = []
    var completedAt: Date?
    /// Set when this task is a step in a deadline's plan. Optional so files written
    /// before plans existed still decode with the synthesized `Decodable`.
    var deadlineID: UUID?

    var isCompleted: Bool { completedAt != nil }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var status: ProjectStatus
    var importance: Priority
    var category: ItemCategory
    var notes = ""
    var startDate: Date?
    var endDate: Date?
    var progress: Double = 0
}

struct Deadline: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var isDateOnly: Bool
    var originalTimeZoneID: String?
    var originalDescription: String?
    var category: ItemCategory
    var priority: Priority
    var projectID: UUID?
    var isTentative = false
    var needsVerification = false
    var reminderOffsetsMinutes: [Int]?
    var completedAt: Date?
}

enum LauncherKind: String, Codable, CaseIterable { case application, url, file, folder }

struct LauncherItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var kind: LauncherKind
    /// Bundle identifier for applications; URL or path for other entries.
    var target: String
    var symbol: String
    var isFavorite = true
    var keyboardShortcut: String?
    var order: Int
}

struct FocusSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var scheduleBlockID: UUID?
    var taskID: UUID?
    var startedAt: Date
    var plannedEnd: Date
    var endedAt: Date?
    var pausedAt: Date?
    var accumulatedPauseSeconds: TimeInterval = 0
    var distractionAttempts = 0

    var isActive: Bool { endedAt == nil }
    func elapsed(at date: Date = Date()) -> TimeInterval {
        var effective = min(endedAt ?? date, plannedEnd)
        if let pausedAt { effective = min(effective, pausedAt) }
        return max(0, effective.timeIntervalSince(startedAt) - accumulatedPauseSeconds)
    }
}

/// How much the recurring schedule is allowed to notify. Deadlines and the daily
/// brief are unaffected — they're what reminders are for.
enum BlockReminderStyle: String, Codable, CaseIterable, Identifiable {
    case off
    /// One ping as each non-personal block starts; meals, sleep and similar stay quiet.
    case workStart
    /// Every reminder each block's own notification rule asks for.
    case detailed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .workStart: "When work blocks start"
        case .detailed: "Everything (each block's own rules)"
        }
    }
}

enum MoiHaloIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle = "Subtle"
    case standard = "Standard"
    case vivid = "Vivid"

    var id: String { rawValue }
}

struct UserSettings: Codable, Hashable {
    var hudEnabled = true
    var hudCompact = false
    var hudOpacity = 0.94
    var hudAlwaysOnTop = true
    var hudAllSpaces = true
    var hudHiddenUntil: Date?
    var notificationsEnabled = true
    /// Retained for decoding older backups. New code uses the per-category Moi settings.
    var notificationSound = true
    var moiSoundsEnabled = true
    var moiSummonSoundEnabled = true
    var moiNotificationSoundEnabled = true
    var moiSuccessSoundEnabled = true
    var moiAttentionSoundEnabled = true
    var moiHaloEnabled = true
    var moiHaloIntensity: MoiHaloIntensity = .standard
    var morningSummaryEnabled = true
    var morningSummaryTime = LocalTime(7, 50)
    var eveningReviewEnabled = true
    var eveningReviewTime = LocalTime(21, 30)
    var blockReminders: BlockReminderStyle = .workStart
    /// A line about the user that makes research prompts specific ("high-school senior applying to design programs").
    var researchContext = ""
    /// The person's own category names (e.g. a subject or a competition). Stored with their data, never in code.
    var customCategories: [String] = []
    var timeZoneID = TimeZone.current.identifier
    var weekStartsMonday = true
    var softBlockEnabled = true
    var quitBlockedApps = false
    var blockedBundleIDs = ["com.reddit.Reddit", "com.facebook.archon"]
    var blockedWebsites = ["reddit.com", "instagram.com", "tiktok.com"]
    var allowedBundleIDs = ["com.apple.Safari"]

    init() {}

    /// Tolerant of missing keys for the same reason as `AppData.init(from:)` — a settings
    /// field added in a later version must not make an older file undecodable.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hudEnabled = try c.decodeIfPresent(Bool.self, forKey: .hudEnabled) ?? true
        hudCompact = try c.decodeIfPresent(Bool.self, forKey: .hudCompact) ?? false
        hudOpacity = try c.decodeIfPresent(Double.self, forKey: .hudOpacity) ?? 0.94
        hudAlwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .hudAlwaysOnTop) ?? true
        hudAllSpaces = try c.decodeIfPresent(Bool.self, forKey: .hudAllSpaces) ?? true
        hudHiddenUntil = try c.decodeIfPresent(Date.self, forKey: .hudHiddenUntil)
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notificationSound = try c.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? true
        moiSoundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .moiSoundsEnabled) ?? true
        moiSummonSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .moiSummonSoundEnabled) ?? true
        moiNotificationSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .moiNotificationSoundEnabled) ?? notificationSound
        moiSuccessSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .moiSuccessSoundEnabled) ?? true
        moiAttentionSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .moiAttentionSoundEnabled) ?? true
        moiHaloEnabled = try c.decodeIfPresent(Bool.self, forKey: .moiHaloEnabled) ?? true
        moiHaloIntensity = try c.decodeIfPresent(MoiHaloIntensity.self, forKey: .moiHaloIntensity) ?? .standard
        morningSummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .morningSummaryEnabled) ?? true
        morningSummaryTime = try c.decodeIfPresent(LocalTime.self, forKey: .morningSummaryTime) ?? LocalTime(7, 50)
        eveningReviewEnabled = try c.decodeIfPresent(Bool.self, forKey: .eveningReviewEnabled) ?? true
        eveningReviewTime = try c.decodeIfPresent(LocalTime.self, forKey: .eveningReviewTime) ?? LocalTime(21, 30)
        blockReminders = try c.decodeIfPresent(BlockReminderStyle.self, forKey: .blockReminders) ?? .workStart
        researchContext = try c.decodeIfPresent(String.self, forKey: .researchContext) ?? ""
        customCategories = try c.decodeIfPresent([String].self, forKey: .customCategories) ?? []
        timeZoneID = try c.decodeIfPresent(String.self, forKey: .timeZoneID) ?? TimeZone.current.identifier
        weekStartsMonday = try c.decodeIfPresent(Bool.self, forKey: .weekStartsMonday) ?? true
        softBlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .softBlockEnabled) ?? true
        quitBlockedApps = try c.decodeIfPresent(Bool.self, forKey: .quitBlockedApps) ?? false
        blockedBundleIDs = try c.decodeIfPresent([String].self, forKey: .blockedBundleIDs) ?? ["com.reddit.Reddit", "com.facebook.archon"]
        blockedWebsites = try c.decodeIfPresent([String].self, forKey: .blockedWebsites) ?? ["reddit.com", "instagram.com", "tiktok.com"]
        allowedBundleIDs = try c.decodeIfPresent([String].self, forKey: .allowedBundleIDs) ?? ["com.apple.Safari"]
    }
}

/// A user-defined named workspace retained for archive compatibility.
///
/// Before this existed a "workspace" was only an array of launcher IDs hanging off a
/// schedule block, so it could only be addressed if a block with that exact name
/// happened to be running. A mode is addressable by name at any time.
struct MoiMode: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Extra phrasings that should resolve to this mode ("sat prep", "study").
    var aliases: [String] = []
    /// Launcher items to open, in this order.
    var launcherItemIDs: [UUID] = []
    /// When set, entering the mode also starts a focus session of this length.
    var focusMinutes: Int?
    var linkedProjectID: UUID?
    var linkedBlockID: UUID?

    /// True when `term` names this mode, by title or alias, case/whitespace-insensitively.
    func matches(_ term: String) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        if name.lowercased() == needle { return true }
        if aliases.contains(where: { $0.lowercased() == needle }) { return true }
        // Allow "set me up for SAT" style phrasing to still land on the mode.
        return name.lowercased().contains(needle) || needle.contains(name.lowercased())
    }
}

struct AppData: Codable {
    var schemaVersion = 1
    var modes: [MoiMode] = []
    var scheduleBlocks: [ScheduleBlock] = []
    var overrides: [DailyOverride] = []
    var completions: [CompletionRecord] = []
    var tasks: [TaskItem] = []
    var projects: [Project] = []
    var deadlines: [Deadline] = []
    var focusSessions: [FocusSession] = []
    var launcherItems: [LauncherItem] = []
    var settings = UserSettings()
    var reminderDefaults: ReminderDefaults?
    var seededAt = Date()

    init() {}

    /// Decodes tolerantly: any key missing from the file falls back to its default.
    ///
    /// This is load-bearing. Swift's *synthesized* `Decodable` ignores property defaults
    /// and throws `keyNotFound` instead, and `AppStore` treats a decode failure as
    /// "no data yet" and overwrites the file with seed data. Without this initializer,
    /// adding a single new field to `AppData` silently destroys the user's real
    /// schedule, tasks, projects and deadlines the next time Moi launches.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        modes = try container.decodeIfPresent([MoiMode].self, forKey: .modes) ?? []
        scheduleBlocks = try container.decodeIfPresent([ScheduleBlock].self, forKey: .scheduleBlocks) ?? []
        overrides = try container.decodeIfPresent([DailyOverride].self, forKey: .overrides) ?? []
        completions = try container.decodeIfPresent([CompletionRecord].self, forKey: .completions) ?? []
        tasks = try container.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        deadlines = try container.decodeIfPresent([Deadline].self, forKey: .deadlines) ?? []
        focusSessions = try container.decodeIfPresent([FocusSession].self, forKey: .focusSessions) ?? []
        launcherItems = try container.decodeIfPresent([LauncherItem].self, forKey: .launcherItems) ?? []
        settings = try container.decodeIfPresent(UserSettings.self, forKey: .settings) ?? UserSettings()
        reminderDefaults = try container.decodeIfPresent(ReminderDefaults.self, forKey: .reminderDefaults)
        seededAt = try container.decodeIfPresent(Date.self, forKey: .seededAt) ?? Date()
    }
}

struct ReminderDefaults: Codable, Hashable {
    var deadlineDays = [30, 14, 7, 3, 1]
    var exactTimeExtraMinutes = [180, 60]
}

struct ScheduleOccurrence: Identifiable, Hashable {
    var id: String { "\(source.id.uuidString)-\(Int(start.timeIntervalSince1970))" }
    let source: ScheduleBlock
    let title: String
    let start: Date
    let end: Date
    let isSkipped: Bool
    let completion: CompletionState?
}

enum ScheduleMoment: Equatable {
    case beforeDay(next: ScheduleOccurrence?)
    case active(ScheduleOccurrence, next: ScheduleOccurrence?)
    case gap(previous: ScheduleOccurrence?, next: ScheduleOccurrence?)
    case afterDay(previous: ScheduleOccurrence?)
}

struct PersistedEnvelope: Codable {
    var exportedAt = Date()
    var data: AppData
}
