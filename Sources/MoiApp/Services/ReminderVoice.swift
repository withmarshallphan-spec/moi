import Foundation

/// How Moi talks in reminders: short, warm, specific, and always ending in something
/// doable. A countdown on its own ("3 days") is information; a countdown with the next
/// 20-minute step is help.
enum ReminderVoice {
    static func countdownPhrase(days: Int) -> String {
        switch days {
        case ..<0: "overdue"
        case 0: "today"
        case 1: "tomorrow"
        case 7: "1 week"
        case 14: "2 weeks"
        default: "\(days) days"
        }
    }

    static func deadlineTitle(_ title: String, days: Int, hours: Int? = nil) -> String {
        if let hours { return hours == 0 ? "\(title) is due now" : "\(title) — \(hours) hour\(hours == 1 ? "" : "s") left" }
        switch days {
        case ..<1: return "\(title) is today"
        case 1: return "\(title) is tomorrow"
        default: return "\(title) — \(countdownPhrase(days: days)) away"
        }
    }

    /// `step` is nil when the question is "is it done?" rather than "what's next?".
    static func deadlineBody(days: Int, hours: Int? = nil, step: String?, minutes: Int?) -> String {
        let lead: String
        if hours != nil { lead = "Home stretch." }
        else {
            switch days {
            case ..<1: lead = "It's the day."
            case 1: lead = "Nearly there."
            case 2...3: lead = "A few days left — a good day to do the heavy part."
            case 4...7: lead = "About a week. One small step today keeps it calm."
            case 8...14: lead = "A couple of weeks out, which makes starting easy."
            default: lead = "Still far away — the easiest time to begin."
            }
        }
        guard let step else { return "\(lead) If it's already done, tap Done so I stop reminding you." }
        return "\(lead) Next: \(step)\(minutes.map { " (\($0) min)" } ?? "")."
    }

    static func morning(_ items: [NextUpItem]) -> (title: String, body: String) {
        guard let first = items.first else {
            return ("Good morning", "Nothing's pressing today. Pick one thing you'd enjoy moving forward.")
        }
        var body = first.detail + (first.minutes.map { " · \($0) min" } ?? "")
        let rest = items.dropFirst().map(\.title)
        if !rest.isEmpty { body += "\nThen: " + rest.joined(separator: " · ") }
        return ("Today's one thing: \(first.title)", body)
    }

    static func evening(tomorrow first: NextUpItem?) -> (title: String, body: String) {
        guard let first else { return ("Nothing pressing tomorrow", "Rest well — I'll keep an eye on the dates.") }
        return ("Tomorrow starts with: \(first.title)", "\(first.detail). Rest now; I'll remind you in the morning.")
    }
}
