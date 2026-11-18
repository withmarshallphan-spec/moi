import Foundation

/// One concrete thing worth doing next, whatever it came from.
struct NextUpItem: Identifiable, Hashable {
    enum Target: Hashable {
        /// An existing task or plan step; checking it completes the task.
        case task(UUID)
        /// A deadline with no plan yet. Checking it adopts the suggested plan with the first step done.
        case suggestedStep(deadlineID: UUID)
        /// A deadline whose steps are all done; checking it completes the deadline.
        case deadline(UUID)
    }

    enum Urgency: Int, Comparable {
        case later, soon, today, overdue
        static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let target: Target
    let title: String
    /// Short context, e.g. "Portfolio V1 freeze · 6 days".
    let detail: String
    let deadlineID: UUID?
    let minutes: Int?
    let urgency: Urgency
    /// "2 days", "today", "overdue" — short enough to never be truncated away.
    var countdown: String?
    var id: Target { target }
}

extension NextUpItem.Target {
    /// Round-trips through a notification's `userInfo` so "Done" works from Notification Center.
    var userInfo: [String: String] {
        switch self {
        case let .task(id): ["target": "task", "id": id.uuidString]
        case let .suggestedStep(id): ["target": "suggested", "id": id.uuidString]
        case let .deadline(id): ["target": "deadline", "id": id.uuidString]
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let kind = userInfo["target"] as? String, let raw = userInfo["id"] as? String, let id = UUID(uuidString: raw) else { return nil }
        switch kind {
        case "task": self = .task(id)
        case "suggested": self = .suggestedStep(deadlineID: id)
        case "deadline": self = .deadline(id)
        default: return nil
        }
    }
}

enum DeadlineNextStep: Equatable {
    case task(TaskItem)
    case suggested(PlaybookStep)
    case finishDeadline
}

/// Ranks what to do now from deadlines, their plans, and dated tasks.
///
/// Deliberately independent of the recurring schedule: it works whether or not the
/// day's blocks were ever filled in, because keeping those current is exactly the
/// kind of upkeep nobody has time for.
enum NextUpEngine {
    /// Deadlines further out than this don't compete for "next"; they'd crowd out today.
    static let horizonDays = 30

    static func items(data: AppData, now: Date, calendar: Calendar, limit: Int = 5) -> [NextUpItem] {
        let today = calendar.startOfDay(for: now)
        func daysUntil(_ date: Date) -> Int { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0 }
        let deadlines = Dictionary(data.deadlines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var scored: [(score: Int, item: NextUpItem)] = []
        var represented = Set<UUID>()


        for deadline in data.deadlines.sorted(by: { $0.date < $1.date }) where deadline.completedAt == nil {
            let days = daysUntil(deadline.date)
            guard days >= 0, days <= horizonDays else { continue }
            let countdown = ReminderVoice.countdownPhrase(days: days)
            let context = "\(deadline.title) · \(countdown)"
            let base = deadlineScore(days: days, priority: deadline.priority)
            let urgency: NextUpItem.Urgency = days == 0 ? .today : days <= 7 ? .soon : .later
            switch nextStep(for: deadline, in: data) {
            case let .task(task):
                represented.insert(task.id)
                // A step already scheduled for today (or missed) is at least that urgent.
                let stepDays = task.date.map(daysUntil)
                let score = stepDays.map { max(base, dueScore(days: $0, priority: task.priority)) } ?? base
                let stepUrgency = stepDays.map { $0 < 0 ? .overdue : $0 == 0 ? max(urgency, .today) : urgency } ?? urgency
                scored.append((score, NextUpItem(target: .task(task.id), title: task.title, detail: context, deadlineID: deadline.id, minutes: task.durationMinutes, urgency: stepUrgency, countdown: countdown)))
            case let .suggested(step):
                scored.append((base, NextUpItem(target: .suggestedStep(deadlineID: deadline.id), title: step.title, detail: context, deadlineID: deadline.id, minutes: step.minutes, urgency: urgency, countdown: countdown)))
            case .finishDeadline:
                scored.append((base, NextUpItem(target: .deadline(deadline.id), title: "Mark “\(deadline.title)” done", detail: "Every step is checked off", deadlineID: deadline.id, minutes: nil, urgency: urgency, countdown: countdown)))
            }
        }

        for task in data.tasks where !task.isCompleted && !represented.contains(task.id) {
            let linked = task.deadlineID.flatMap { deadlines[$0] }
            // Steps of a deadline that has passed or been finished are moot.
            if let linked, linked.completedAt != nil || daysUntil(linked.date) < 0 { continue }
            if let date = task.date {
                let days = daysUntil(date)
                guard days <= 0 else { continue }
                let when = days < 0 ? "Overdue" : task.startTime.map { "Today · \($0.display)" } ?? "Today"
                let detail = linked.map { "\($0.title) · \(ReminderVoice.countdownPhrase(days: daysUntil($0.date)))" } ?? when
                scored.append((dueScore(days: days, priority: task.priority), NextUpItem(target: .task(task.id), title: task.title, detail: detail, deadlineID: linked?.id, minutes: task.durationMinutes, urgency: days < 0 ? .overdue : .today, countdown: days < 0 ? "overdue" : "today")))
            } else if task.priority >= .high, linked == nil {
                scored.append((150 + priorityBonus(task.priority), NextUpItem(target: .task(task.id), title: task.title, detail: "High priority · no date", deadlineID: nil, minutes: task.durationMinutes, urgency: .later)))
            }
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.title < $1.item.title }
            .prefix(limit)
            .map(\.item)
    }

    /// A deadline's plan steps, in plan order.
    static func steps(for deadline: Deadline, in data: AppData) -> [TaskItem] {
        data.tasks.filter { $0.deadlineID == deadline.id }
    }

    static func nextStep(for deadline: Deadline, in data: AppData) -> DeadlineNextStep {
        let steps = steps(for: deadline, in: data)
        if steps.isEmpty, let first = DeadlinePlaybook.match(deadline.title).steps.first { return .suggested(first) }
        if let open = steps.first(where: { !$0.isCompleted }) { return .task(open) }
        return .finishDeadline
    }

    /// Incomplete deadlines that have already passed — candidates for a quick "did this happen?" tidy-up.
    static func passedDeadlines(data: AppData, now: Date, calendar: Calendar, withinDays: Int = 45) -> [Deadline] {
        let today = calendar.startOfDay(for: now)
        return data.deadlines.filter { deadline in
            guard deadline.completedAt == nil else { return false }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: deadline.date)).day ?? 0
            return days < 0 && days >= -withinDays
        }.sorted { $0.date > $1.date }
    }

    private static func deadlineScore(days: Int, priority: Priority) -> Int {
        (days == 0 ? 900 : 800 - days * 20) + priorityBonus(priority)
    }

    private static func dueScore(days: Int, priority: Priority) -> Int {
        (days < 0 ? 1000 : 900) + priorityBonus(priority)
    }

    private static func priorityBonus(_ priority: Priority) -> Int {
        switch priority {
        case .critical: 60
        case .high: 30
        case .normal: 0
        case .low: -40
        }
    }
}
