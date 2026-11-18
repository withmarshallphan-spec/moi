import Foundation

struct ParsedQuickTask {
    let title: String
    let date: Date?
    let time: LocalTime?
    let category: ItemCategory
    /// The text said "due" or "deadline", so it should become a countdown with reminders rather than a to-do.
    var isDeadline = false
}

/// Turns one line of typing into a task or deadline, so adding something never needs a form.
///
/// Understands today/tomorrow, weekday names, "in 3 days", "next week", "oct 3" / "3 oct",
/// and 24-hour times. Short weekdays work after a deadline marker; plain SAT remains a study subject.
enum QuickAddParser {
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let monthPattern = "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?"

    static func parse(_ input: String, now: Date, calendar: Calendar, categories: [ItemCategory] = ItemCategory.allCases) -> ParsedQuickTask {
        var title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = calendar.startOfDay(for: now)
        var date: Date?
        var time: LocalTime?

        /// Removes the first case-insensitive match from the title and returns its capture groups.
        func take(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let whole = Range(match.range, in: title) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: title).map { String(title[$0]) } ?? ""
            }
            title.replaceSubrange(whole, with: " ")
            return groups
        }
        func day(_ offset: Int) -> Date? { calendar.date(byAdding: .day, value: offset, to: today) }

        let isDeadline = take(#"\b(due|deadline)\b:?"#) != nil
        let weekdayPattern = isDeadline ? #"\b(?:on )?(sun(?:day)?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?)\b"# : #"\b(?:on )?(sunday|monday|tuesday|wednesday|thursday|friday|saturday|mon|tue|wed|thu|fri|sun)\b"#

        if take(#"\btomorrow\b"#) != nil {
            date = day(1)
        } else if take(#"\btoday\b"#) != nil {
            date = today
        } else if let groups = take(#"\bin (\d{1,3}) days?\b"#), let count = Int(groups[1]) {
            date = day(count)
        } else if take(#"\bnext week\b"#) != nil {
            date = day(7)
        } else if let groups = take(weekdayPattern),
                  let index = weekdays.firstIndex(where: { $0.hasPrefix(groups[1].lowercased()) }) {
            // Today counts: "gym friday" typed on a Friday means today.
            let current = calendar.component(.weekday, from: today)
            date = day((index + 1 - current + 7) % 7)
        } else if let groups = take("\\b(?:on )?\(monthPattern) (\\d{1,2})(?:st|nd|rd|th)?\\b") {
            date = monthDay(month: groups[1], day: groups[2], today: today, calendar: calendar)
        } else if let groups = take("\\b(?:on )?(\\d{1,2})(?:st|nd|rd|th)? \(monthPattern)\\b") {
            date = monthDay(month: groups[2], day: groups[1], today: today, calendar: calendar)
        }

        if let groups = take(#"\b(?:at )?([01]?\d|2[0-3]):([0-5]\d)\b"#), let hour = Int(groups[1]), let minute = Int(groups[2]) {
            time = LocalTime(hour, minute)
        } else if let groups = take(#"\b(?:at|for|@|by)\s+([01]\d|2[0-3])([0-5]\d)\b"#) ?? take(#"\b([01]\d|2[0-3])([0-5]\d)\s?(?:h|hrs|hours)\b"#), let hour = Int(groups[1]), let minute = Int(groups[2]) {
            time = LocalTime(hour, minute) // "for 1630", "1630h"; a bare 4-digit number could be a year, so it needs a cue
        } else if let groups = take(#"\b(?:at )?(1[0-2]|0?[1-9])(?:[:.]([0-5]\d))?\s?(am|pm)\b"#), let hour = Int(groups[1]) {
            let pm = groups[3].lowercased() == "pm"
            time = LocalTime(hour % 12 + (pm ? 12 : 0), Int(groups[2]) ?? 0)
        } else if take(#"\b(?:at )?noon\b"#) != nil {
            time = LocalTime(12, 0)
        } else if let groups = take(#"\b(?:at|around|like)\s+(1[0-2]|[1-9])\b(?![:.]?\d)"#), let hour = Int(groups[1]) {
            time = LocalTime(hour < 8 ? hour + 12 : hour, 0) // "at 6" means the evening; "at 9" the morning
        }
        // Parts of the day, when no clock time was given.
        if let groups = take(#"\b(?:this |in the |on the )?(morning|afternoon|evening|tonight)\b"#) {
            let part = groups[1].lowercased()
            if time == nil { time = part == "morning" ? LocalTime(9, 0) : part == "afternoon" ? LocalTime(15, 0) : part == "evening" ? LocalTime(18, 0) : LocalTime(20, 0) }
            if part == "tonight", date == nil { date = today }
        }

        // Leftover connectives from "finish essay by friday" or "call at 14:00".
        _ = take(#"\s(by|on|at)\s*$"#)
        let cleaned = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—,")))
        return ParsedQuickTask(title: cleaned, date: date, time: time, category: category(for: cleaned, among: categories), isDeadline: isDeadline)
    }

    /// The next occurrence of a month/day: this year, or next year if it has already passed.
    private static func monthDay(month: String, day: String, today: Date, calendar: Calendar) -> Date? {
        guard let monthIndex = months.firstIndex(of: String(month.lowercased().prefix(3))), let dayNumber = Int(day) else { return nil }
        let year = calendar.component(.year, from: today)
        for candidateYear in [year, year + 1] {
            guard let candidate = calendar.date(from: DateComponents(year: candidateYear, month: monthIndex + 1, day: dayNumber)),
                  calendar.component(.day, from: candidate) == dayNumber else { return nil }
            if candidate >= today { return candidate }
        }
        return nil
    }

    /// A category is picked when its name appears as a whole word ("SAT drills" → SAT, if the
    /// person has a SAT category). Case-sensitive for all-caps names so "sat down" isn't SAT.
    private static func category(for title: String, among categories: [ItemCategory]) -> ItemCategory {
        for category in categories where category != .personal {
            let name = NSRegularExpression.escapedPattern(for: category.rawValue)
            let caps = category.rawValue == category.rawValue.uppercased()
            if title.range(of: "\\b\(name)\\b", options: caps ? .regularExpression : [.regularExpression, .caseInsensitive]) != nil { return category }
        }
        return .personal
    }
}
