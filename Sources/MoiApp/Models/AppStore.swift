import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var selectedSection: SidebarSection = .overview
    @Published var commandPalettePresented = false
    @Published var quickAddPresented = false
    @Published var now = Date()
    @Published var persistenceError: String?
    /// The deadline whose plan sheet is showing. One presentation path, so a notification,
    /// the menu bar, and the dashboard can all open the same sheet.
    @Published var planningDeadlineID: UUID?

    private(set) var isReadOnly = false
    private let persistenceURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var minuteTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(persistenceURL: URL? = nil, startTimer: Bool = true) {
        let folder = MoiPaths.root
        self.persistenceURL = persistenceURL ?? folder.appendingPathComponent("data.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            try LocalStorage.recoverRestore(in: self.persistenceURL.deletingLastPathComponent())
            data = try LocalStorage.load(AppData.self, from: self.persistenceURL, default: SeedData.initialData())
            try data.validate()
            if data.schemaVersion < 6 {
                try LocalStorage.snapshot(self.persistenceURL)
                Self.applyMigrations(to: &data)
            }
        } catch {
            data = AppData()
            isReadOnly = true
            persistenceError = "Original data preserved. Changes are disabled until you import a valid backup or repair the original. " + error.localizedDescription
        }
        if startTimer {
            beginMinuteTicks()
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshAfterWake() } })
            observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshAfterWake() } })
        }
        save()
    }

    deinit {
        minuteTimer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func beginMinuteTicks() {
        minuteTimer?.invalidate()
        let delay = 60 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        minuteTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
            }
        }
    }

    private func refreshAfterWake() {
        now = Date()
        beginMinuteTicks()
        NotificationService.shared.reschedule(using: data)
    }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? .current
        cal.firstWeekday = data.settings.weekStartsMonday ? 2 : 1
        return cal
    }

    func update(_ mutation: (inout AppData) -> Void) {
        guard !isReadOnly else { return }
        var copy = data
        mutation(&copy)
        data = copy
        save()
        NotificationService.shared.reschedule(using: copy)
    }

    func save() {
        guard !isReadOnly else { return }
        do {
            try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try encoder.encode(data)
            try bytes.write(to: persistenceURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func toggleTask(_ task: TaskItem) {
        update { data in
            guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            data.tasks[index].completedAt = data.tasks[index].completedAt == nil ? Date() : nil
        }
    }

    func complete(_ occurrence: ScheduleOccurrence, state: CompletionState = .completed) {
        update { data in
            data.completions.removeAll { $0.sourceID == occurrence.source.id && calendar.isDate($0.occurrenceDate, inSameDayAs: occurrence.start) }
            data.completions.append(CompletionRecord(sourceID: occurrence.source.id, occurrenceDate: occurrence.start, state: state))
        }
    }

    func addTask(title: String, date: Date? = nil, time: LocalTime? = nil) {
        let parsed = QuickAddParser.parse(title, now: now, calendar: calendar, categories: ItemCategory.options(in: data))
        update { $0.tasks.append(TaskItem(title: parsed.title, date: date ?? parsed.date, startTime: time ?? parsed.time, category: parsed.category)) }
    }

    /// One line of text from anywhere: "essay due fri" becomes a deadline with countdown
    /// reminders; anything else becomes a to-do.
    @discardableResult func quickAdd(_ text: String) -> ParsedQuickTask? {
        var parsed = QuickAddParser.parse(text, now: Date(), calendar: calendar, categories: ItemCategory.options(in: data))
        guard !parsed.title.isEmpty else { return nil }
        parsed = ParsedQuickTask(title: parsed.title.prefix(1).uppercased() + parsed.title.dropFirst(), date: parsed.date, time: parsed.time, category: parsed.category, isDeadline: parsed.isDeadline)
        if parsed.isDeadline, let day = parsed.date {
            let exact = parsed.time.flatMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day) }
            let deadline = Deadline(title: parsed.title, date: exact ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day, isDateOnly: exact == nil, category: parsed.category, priority: .high)
            update { $0.deadlines.append(deadline) }
        } else {
            update { $0.tasks.append(TaskItem(title: parsed.title, date: parsed.date, startTime: parsed.time, durationMinutes: parsed.time == nil ? nil : 60, category: parsed.category)) }
        }
        return parsed
    }

    // MARK: Checking things off from anywhere

    func complete(_ target: NextUpItem.Target) {
        switch target {
        case let .task(id):
            setTask(id, completed: true)
        case let .suggestedStep(deadlineID):
            // If a plan was adopted since this suggestion was shown, finish its first open step instead.
            if let deadline = data.deadlines.first(where: { $0.id == deadlineID }),
               let open = NextUpEngine.steps(for: deadline, in: data).first(where: { !$0.isCompleted }) {
                setTask(open.id, completed: true)
            } else {
                adoptPlan(forDeadline: deadlineID, completingFirst: true)
            }
        case let .deadline(id):
            setDeadline(id, completed: true)
        }
        MoiSoundController.shared.play(.success, settings: data.settings)
    }

    func setTask(_ id: UUID, completed: Bool) {
        update { data in
            guard let index = data.tasks.firstIndex(where: { $0.id == id }), data.tasks[index].isCompleted != completed else { return }
            data.tasks[index].completedAt = completed ? Date() : nil
        }
    }

    /// Finishing a deadline also closes its open steps; they no longer mean anything.
    func setDeadline(_ id: UUID, completed: Bool) {
        update { data in
            guard let index = data.deadlines.firstIndex(where: { $0.id == id }) else { return }
            data.deadlines[index].completedAt = completed ? Date() : nil
            guard completed else { return }
            for step in data.tasks.indices where data.tasks[step].deadlineID == id && data.tasks[step].completedAt == nil {
                data.tasks[step].completedAt = Date()
            }
        }
    }

    /// Turns the deadline's playbook into dated steps spread over the days left.
    func adoptPlan(forDeadline id: UUID, completingFirst: Bool = false) {
        guard let deadline = data.deadlines.first(where: { $0.id == id }), NextUpEngine.steps(for: deadline, in: data).isEmpty else { return }
        var steps = DeadlinePlan.tasks(for: deadline, steps: DeadlinePlaybook.match(deadline.title).steps, now: Date(), calendar: calendar)
        if completingFirst, !steps.isEmpty { steps[0].completedAt = Date() }
        update { $0.tasks.append(contentsOf: steps) }
    }

    func addStep(_ title: String, toDeadline id: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let deadline = data.deadlines.first(where: { $0.id == id }) else { return }
        let lastDate = NextUpEngine.steps(for: deadline, in: data).compactMap(\.date).max()
        update { $0.tasks.append(TaskItem(title: trimmed, date: lastDate ?? calendar.startOfDay(for: Date()), durationMinutes: 30, priority: deadline.priority >= .high ? .high : .normal, projectID: deadline.projectID, category: deadline.category, deadlineID: id)) }
    }

    /// Opens the plan sheet over whatever screen is showing, bringing Moi forward when
    /// called from a notification or the menu bar.
    func openPlan(for deadlineID: UUID?) {
        if let deadlineID { planningDeadlineID = deadlineID } else { selectedSection = .deadlines }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    func startFocus(title: String, durationMinutes: Int, blockID: UUID? = nil, taskID: UUID? = nil) {
        update { data in
            for index in data.focusSessions.indices where data.focusSessions[index].isActive { data.focusSessions[index].endedAt = Date() }
            data.focusSessions.append(FocusSession(title: title, scheduleBlockID: blockID, taskID: taskID, startedAt: Date(), plannedEnd: Date().addingTimeInterval(TimeInterval(durationMinutes * 60))))
        }
        SoftBlocker.shared.begin(store: self)
    }

    func endFocus() {
        update { data in
            guard let i = data.focusSessions.lastIndex(where: { $0.isActive }) else { return }
            data.focusSessions[i].endedAt = Date()
        }
        SoftBlocker.shared.end()
    }

    func incrementDistractionAttempts() {
        update { data in
            guard let i = data.focusSessions.lastIndex(where: { $0.isActive }) else { return }
            data.focusSessions[i].distractionAttempts += 1
        }
    }

    var activeFocus: FocusSession? { data.focusSessions.last(where: { $0.isActive && ($0.pausedAt != nil || $0.plannedEnd > now) }) }

    func replaceData(_ imported: AppData, assistant: AssistantArchive? = nil) throws {
        try imported.validate()
        var imported = imported
        Self.applyMigrations(to: &imported)
        var files = ["data.json": try LocalStorage.encoder().encode(imported)]
        if let assistant {
            var ids = Set<UUID>()
            for item in assistant.index.conversations {
                guard ids.insert(item.id).inserted, let file = assistant.conversations[item.id.uuidString], file.id == item.id else { throw MoiError.message("Backup is missing a unique conversation file.") }
            }
            files["Assistant/index.json"] = try LocalStorage.encoder().encode(assistant.index)
            for (key, file) in assistant.conversations {
                guard key == file.id.uuidString else { throw MoiError.message("Conversation identifier mismatch.") }
                files["Assistant/\(file.id.uuidString).json"] = try LocalStorage.encoder().encode(file)
            }
        }
        try LocalStorage.restore(files, in: persistenceURL.deletingLastPathComponent())
        data = imported; isReadOnly = false; persistenceError = nil
        if assistant != nil { AssistantStore.shared.reload() }
        NotificationService.shared.reschedule(using: imported)
    }

    private static func applyMigrations(to data: inout AppData) {
        if data.schemaVersion < 3 {
            data.settings.hudCompact = true
        }
        if data.schemaVersion < 5 {
            data.settings.moiNotificationSoundEnabled = data.settings.notificationSound
        }
        data.schemaVersion = max(data.schemaVersion, 6)
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview", tasks = "Tasks", focus = "Focus", clean = "Clean", intelligence = "Intelligence", guide = "Guide", settings = "Settings"
    /// Old destinations (notifications, menus) that now live inside Plan.
    case deadlines = "Deadlines", calendar = "Calendar"
    var id: String { rawValue }
    /// What people see. `rawValue` stays stable for URLs and saved selections.
    var title: String {
        switch self {
        case .overview: "Home"
        case .tasks, .deadlines, .calendar: "Plan"
        case .focus: "Focus mode"
        case .clean: "Clean up"
        case .intelligence: "Ask moi"
        case .guide: "Guide"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "house"
        case .tasks, .deadlines, .calendar: "calendar"
        case .focus: "timer"
        case .clean: "sparkles.rectangle.stack"
        case .intelligence: "sparkles"
        case .guide: "questionmark.circle"
        case .settings: "gearshape"
        }
    }
}
