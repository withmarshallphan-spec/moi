import Foundation

/// Everything moi says in its own voice. Rules (MOI_DESIGN.md → Voice):
/// - Clear first. At most one playful beat per message, and none when files, permissions,
///   money or lost work are involved.
/// - Mannerisms, used sparingly: "Moi!" as hello (it's Finnish for hi, and its name);
///   counting small wins; narrating its own tiny effort; taking an idiom a little literally;
///   saying plainly when it isn't sure.
/// - Never guilt the person, never claim feelings or needs, never pretend something happened.
/// - Uses the person's name for greetings and celebrations, not in every sentence.
/// Lines vary by day (not per render) so moi doesn't change its mind every time a view redraws.
enum MoiVoice {
    static var name: String { UserDefaults.standard.string(forKey: "moi.userName")?.trimmingCharacters(in: .whitespaces) ?? "" }

    // MARK: Greetings

    static func greeting(name: String = name, at date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let who = name.isEmpty ? "" : ", \(name)"
        let options: [String]
        switch hour {
        case 5..<12: options = ["Moi\(who)! Good morning.", "Morning\(who). I was here the whole time.", "Good morning\(who). Coffee first, or list first?"]
        case 12..<17: options = ["Hey\(who).", "Afternoon\(who). It snuck up on both of us.", "Moi\(who)! Still going strong?"]
        case 17..<23: options = ["Evening\(who).", "Hey\(who). Winding down, or just getting interesting?", "Moi\(who). The day's nearly folded up."]
        default: options = ["It's late\(who). I'll keep it short.", "Still up\(who)? Me too. I don't sleep, technically.", "Hey\(who). Night shift."]
        }
        return pick(options, date: date, calendar: calendar)
    }

    /// One line under the greeting: what the day looks like, from real counts only.
    static func daySummary(dueToday: Int, overdue: Int, nextTitle: String?, done: Int) -> String {
        if overdue > 0 { return overdue == 1 ? "One thing slipped past its date. Want to pick it back up?" : "\(overdue) things slipped past their dates. Pick one and we'll start there." }
        switch dueToday {
        case 0 where done > 0: return "Everything for today is done. \(done) ticked off. I counted."
        case 0: return nextTitle.map { "Nothing due today. Next up is “\($0)” — no rush." } ?? "Nothing on the list. Suspiciously peaceful."
        case 1: return nextTitle.map { "Just one thing today: “\($0)”." } ?? "Just one thing today."
        default: return nextTitle.map { "\(dueToday) things today. Maybe start with “\($0)”?" } ?? "\(dueToday) things today."
        }
    }

    // MARK: Doing things

    static func taskAdded(_ title: String) -> String { "Added “\(title)”. It's on the list, where I can keep an eye on it." }
    static func focusStarted(_ title: String, minutes: Int) -> String { "Focus on “\(title)” for \(minutes) minutes. I'll stay quiet. Mostly." }
    static func opened(_ app: String) -> String { "Opened \(app)." }
    static func completed(count: Int, date: Date = Date()) -> String {
        switch count {
        case 1: return "Done. First one today!"
        case 5, 10, 15, 20: return "Done. That's \(count) today. I'm keeping count, quietly."
        default: return pick(["Done.", "Ticked off.", "Gone. Next!", "Done. That's \(count)."], date: date, calendar: .current, salt: count)
        }
    }

    // MARK: Not quite

    /// Plain and honest. No jokes when something didn't work.
    static func failed(_ what: String, reason: String) -> String { "I couldn't \(what). \(reason)" }
    static let notUnderstood = "Hm, I'm not sure what you mean. Try “gym tomorrow 16:30”, “move it to 5pm”, “what's tomorrow?” or “clean up my desktop”."
    static func permission(feature: String, capability: String) -> String {
        "To \(feature), macOS needs to let me \(capability). I'll only use it when you ask. macOS will show its own prompt next."
    }

    // MARK: Empty states (where a little personality is welcome)

    static let noTasks = "No tasks. Enjoy it, or give me one."
    static let noDeadlines = "No deadlines. Rare, and a little suspicious."
    static let nothingPlaying = "Nothing's playing. It's very quiet up here."
    static let noFolders = "I haven't been shown any folders yet. Pick one and I'll look carefully. I won't move a thing."
    static let wokeUp = "Oh! I was just resting my eyes."

    // MARK: Helpers

    /// Stable for a day (and per salt), so a line doesn't flicker between redraws.
    static func pick(_ options: [String], date: Date, calendar: Calendar, salt: Int = 0) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return options[abs(day &+ salt) % options.count]
    }
}
