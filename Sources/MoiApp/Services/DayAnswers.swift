import Foundation

/// Deterministic answers to everyday questions, computed only from saved moi records.
/// No model is involved. When records are empty the answer says so instead of guessing,
/// and nothing is ever reported as done unless it was marked done.
enum DayAnswers {
    enum Question: Equatable { case today, tomorrow, next, behind, prioritize, freeTime, completed }

    /// Order matters: "what did I complete today" is about completion, not today's plan.
    static func question(for text: String) -> Question? {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Only questions. "edit it for 1630 tomorrow" mentions tomorrow but isn't asking about it.
        let asking = t.hasSuffix("?") || t.range(of: #"^(what|whats|what's|when|how|do|does|did|am|is|are|any|anything|show|list|tell|give|which|where|should|can you tell)\b"#, options: .regularExpression) != nil || t.split(separator: " ").count <= 2
        guard asking else { return nil }
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("tomorrow") { return .tomorrow }
        if has("behind", "overdue", "missed") { return .behind }
        if has("complete", "finished", "did i do", "got done", "accomplish") { return .completed }
        if has("how much time", "free time", "time left", "time do i have") { return .freeTime }
        if has("priorit", "most important") { return .prioritize }
        if has("next") { return .next }
        if has("today", "should i do", "agenda", "my day") { return .today }
        return nil
    }

    static func answer(_ question: Question, data: AppData, now: Date, calendar inputCalendar: Calendar) -> String {
        var calendar = inputCalendar
        calendar.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? inputCalendar.timeZone
        let zone = calendar.timeZone
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayFormat = DateFormatter(); dayFormat.timeZone = zone; dayFormat.dateFormat = "EEE d MMM"
        func time(_ date: Date) -> String { date.formattedTime(in: zone) }
        func section(_ title: String, _ lines: [String]) -> String? { lines.isEmpty ? nil : ([title] + lines.map { "• " + $0 }).joined(separator: "\n") }
        func schedule(_ day: Date) -> [String] {
            ScheduleEngine.occurrences(on: day, data: data, calendar: calendar).filter { !$0.isSkipped }
                .map { "\(time($0.start))–\(time($0.end)) \($0.title)" + ($0.completion.map { " (\($0.rawValue))" } ?? "") }
        }
        func due(_ day: Date) -> [String] {
            data.tasks.filter { !$0.isCompleted && $0.date.map { calendar.isDate($0, inSameDayAs: day) } == true }
                .map { $0.title + ($0.startTime.map { " at \($0.display)" } ?? "") + ($0.durationMinutes.map { " · ~\($0) min" } ?? "") }
            + data.deadlines.filter { $0.completedAt == nil && calendar.isDate($0.date, inSameDayAs: day) }.map { "Deadline: \($0.title)" }
        }
        let ranked = NextUpEngine.items(data: data, now: now, calendar: calendar, limit: 3)
        /// NextUp's `detail` already carries the reason: overdue, due today, which deadline and how far.
        func reason(_ item: NextUpItem) -> String { [item.title, item.detail, item.minutes.map { "~\($0) min" }].compactMap { $0 }.joined(separator: " · ") }

        switch question {
        case .today:
            let parts = [section("Schedule", schedule(today)), section("Due today", due(today)),
                         section("Suggested order (nearest deadline first, then priority)", ranked.map(reason))].compactMap { $0 }
            return parts.isEmpty ? "Nothing is scheduled or due today in moi." : parts.joined(separator: "\n\n")

        case .tomorrow:
            let parts = [section("Schedule", schedule(tomorrow)), section("Due tomorrow", due(tomorrow))].compactMap { $0 }
            return parts.isEmpty ? "Nothing is scheduled or due tomorrow in moi." : "Tomorrow, \(dayFormat.string(from: tomorrow))\n\n" + parts.joined(separator: "\n\n")

        case .next:
            var lines: [String] = []
            if let focus = data.focusSessions.last(where: { $0.isActive && $0.plannedEnd > now }) { lines.append("Now: focus on \(focus.title) until \(time(focus.plannedEnd))") }
            else if case let .active(item, _) = ScheduleEngine.state(at: now, data: data, calendar: calendar) { lines.append("Now: \(item.title) until \(time(item.end))") }
            if let next = ScheduleEngine.nextOccurrence(after: now, data: data, calendar: calendar) {
                let day = calendar.isDate(next.start, inSameDayAs: today) ? "" : " on \(dayFormat.string(from: next.start))"
                lines.append("Next on the schedule: \(next.title) at \(time(next.start))\(day)")
            }
            if let first = ranked.first { lines.append("Next to tick off: \(reason(first))") }
            return lines.isEmpty ? "Nothing is scheduled and nothing is pending in moi." : lines.joined(separator: "\n")

        case .behind:
            let overdue = data.tasks.filter { !$0.isCompleted && ($0.date.map { $0 < today } ?? false) }
                .sorted { $0.date! < $1.date! }.map { "\($0.title) (was due \(dayFormat.string(from: $0.date!)))" }
            let passed = NextUpEngine.passedDeadlines(data: data, now: now, calendar: calendar).map { "Deadline passed: \($0.title) (\(dayFormat.string(from: $0.date)))" }
            return section("Overdue in moi", overdue + passed) ?? "Nothing is overdue in moi."

        case .prioritize:
            guard !ranked.isEmpty else { return "Nothing is pending in moi, so there's nothing to rank." }
            return (["Ranked by nearest deadline, then priority:"] + ranked.enumerated().map { "\($0.offset + 1). \(reason($0.element))" }).joined(separator: "\n")

        case .freeTime:
            // The day ends at the evening review when that's still ahead, otherwise at midnight.
            let review = calendar.date(bySettingHour: data.settings.eveningReviewTime.hour, minute: data.settings.eveningReviewTime.minute, second: 0, of: today)!
            let useReview = data.settings.eveningReviewEnabled && review > now
            let end = useReview ? review : tomorrow
            let blocks = (ScheduleEngine.occurrences(on: calendar.date(byAdding: .day, value: -1, to: today)!, data: data, calendar: calendar)
                          + ScheduleEngine.occurrences(on: today, data: data, calendar: calendar))
                .filter { !$0.isSkipped }.map { (max($0.start, now), min($0.end, end)) }.filter { $0.0 < $0.1 }
            let scheduled = mergedMinutes(blocks)
            let window = max(0, Int(end.timeIntervalSince(now) / 60))
            let free = max(0, window - scheduled)
            var lines = ["Until \(time(end))\(useReview ? " (evening review)" : ""): \(duration(window)) left, \(duration(scheduled)) scheduled, about \(duration(free)) free."]
            let pending = data.tasks.filter { !$0.isCompleted && ($0.date.map { calendar.startOfDay(for: $0) <= today } ?? false) }
            if !pending.isEmpty {
                let estimated = pending.compactMap(\.durationMinutes).reduce(0, +)
                let missing = pending.filter { $0.durationMinutes == nil }.count
                lines.append("Due today or overdue: \(pending.count) task\(pending.count == 1 ? "" : "s"), \(duration(estimated)) estimated" + (missing > 0 ? " (\(missing) without an estimate)" : "") + ".")
                lines.append(estimated > free ? "That's \(duration(estimated - free)) more than your free time." : "That fits in your free time.")
            }
            return lines.joined(separator: "\n")

        case .completed:
            let blocks = Dictionary(data.scheduleBlocks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            var done = data.tasks.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: today) } ?? false }.map(\.title)
            done += data.completions.filter { $0.state == .completed && calendar.isDate($0.occurrenceDate, inSameDayAs: today) }.compactMap { blocks[$0.sourceID] }
            done += data.deadlines.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: today) } ?? false }.map { "Deadline: \($0.title)" }
            let focused = data.focusSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: today) && (!$0.isActive || $0.plannedEnd <= now) }.reduce(0) { $0 + Int($1.elapsed(at: now) / 60) }
            if focused > 0 { done.append("Focus: \(duration(focused))") }
            return section("Marked done today", done) ?? "Nothing is marked done today in moi yet."
        }
    }

    /// moi's one-line read of the day (greeting subtitle), from real counts only.
    static func summaryLine(data: AppData, now: Date, calendar inputCalendar: Calendar) -> String {
        var calendar = inputCalendar
        calendar.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? inputCalendar.timeZone
        let today = calendar.startOfDay(for: now)
        let open = data.tasks.filter { !$0.isCompleted }
        let dueToday = open.filter { $0.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false }.count
            + data.deadlines.filter { $0.completedAt == nil && calendar.isDate($0.date, inSameDayAs: today) }.count
        let overdue = open.filter { $0.date.map { $0 < today } ?? false }.count
        let done = data.tasks.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: today) } ?? false }.count
        let next = NextUpEngine.items(data: data, now: now, calendar: calendar, limit: 1).first?.title
        return MoiVoice.daySummary(dueToday: dueToday, overdue: overdue, nextTitle: next, done: done)
    }

    /// Total minutes covered by possibly overlapping intervals.
    static func mergedMinutes(_ intervals: [(Date, Date)]) -> Int {
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let c = current, interval.0 <= c.1 { current = (c.0, max(c.1, interval.1)) }
            else { if let c = current { total += c.1.timeIntervalSince(c.0) }; current = interval }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return Int(total / 60)
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m") : "\(minutes)m"
    }
}
