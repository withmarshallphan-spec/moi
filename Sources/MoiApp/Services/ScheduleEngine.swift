import Foundation

enum ScheduleEngine {
    static func occurrences(on day: Date, data: AppData, calendar inputCalendar: Calendar? = nil) -> [ScheduleOccurrence] {
        var calendar = inputCalendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? .current
        let dayStart = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: dayStart)

        return data.scheduleBlocks.compactMap { block in
            guard block.isEnabled,
                  block.recurrence.weekdays.contains(weekday),
                  dayStart >= calendar.startOfDay(for: block.recurrence.startDate),
                  block.recurrence.endDate.map({ dayStart <= calendar.startOfDay(for: $0) }) ?? true else { return nil }

            let override = data.overrides.last { $0.blockID == block.id && calendar.isDate($0.date, inSameDayAs: dayStart) }
            let startTime = override?.replacementStart ?? block.startTime
            let endTime = override?.replacementEnd ?? block.endTime
            guard let start = calendar.date(bySettingHour: startTime.hour, minute: startTime.minute, second: 0, of: dayStart),
                  var end = calendar.date(bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: dayStart) else { return nil }
            if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end)! }
            let completion = data.completions.last { $0.sourceID == block.id && calendar.isDate($0.occurrenceDate, inSameDayAs: dayStart) }?.state
            return ScheduleOccurrence(source: block, title: override?.replacementTitle ?? block.title, start: start, end: end, isSkipped: override?.isSkipped ?? false, completion: completion)
        }
        .sorted { $0.start < $1.start }
    }

    static func state(at date: Date, data: AppData, calendar: Calendar? = nil) -> ScheduleMoment {
        var cal = calendar ?? Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? .current
        let yesterday = cal.date(byAdding: .day, value: -1, to: date)!
        let carry = occurrences(on: yesterday, data: data, calendar: cal).filter { $0.end > date }
        let items = (carry + occurrences(on: date, data: data, calendar: cal)).filter { !$0.isSkipped }
        let active = items.last { $0.start <= date && date < $0.end }
        if let active {
            return .active(active, next: items.first { $0.start >= active.end } ?? nextOccurrence(after: active.end, data: data, calendar: calendar))
        }
        let previous = items.last { $0.end <= date }
        let next = items.first { $0.start > date }
        if previous == nil { return .beforeDay(next: next) }
        if next == nil { return .afterDay(previous: previous) }
        return .gap(previous: previous, next: next)
    }

    static func nextOccurrence(after date: Date, data: AppData, calendar inputCalendar: Calendar? = nil) -> ScheduleOccurrence? {
        var calendar = inputCalendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? .current
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if let result = occurrences(on: day, data: data, calendar: calendar).first(where: { !$0.isSkipped && $0.start >= date }) { return result }
        }
        return nil
    }

    static func progress(of occurrence: ScheduleOccurrence, at date: Date) -> Double {
        let duration = occurrence.end.timeIntervalSince(occurrence.start)
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(occurrence.start) / duration))
    }

    static func remainingText(until date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return "\(max(1, Int(ceil(Double(seconds) / 60)))) min"
    }

    static func scheduledMinutesRemaining(on day: Date, after now: Date, data: AppData, calendar: Calendar? = nil) -> Int {
        occurrences(on: day, data: data, calendar: calendar)
            .filter { !$0.isSkipped && $0.end > now }
            .reduce(0) { result, occurrence in
                result + Int(occurrence.end.timeIntervalSince(max(now, occurrence.start)) / 60)
            }
    }

    static func hasConflict(_ candidate: ScheduleOccurrence, in occurrences: [ScheduleOccurrence]) -> Bool {
        occurrences.contains { $0.id != candidate.id && !$0.isSkipped && $0.start < candidate.end && candidate.start < $0.end }
    }
}

enum DeadlineEngine {
    static let defaultOffsets = [43_200, 20_160, 10_080, 4_320, 1_440, 180, 60]

    static func countdown(to deadline: Deadline, now: Date, calendar: Calendar) -> String {
        if deadline.completedAt != nil { return "COMPLETE" }
        if deadline.isDateOnly {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline.date)).day ?? 0
            if days < 0 { return "OVERDUE" }
            if days == 0 { return "TODAY" }
            return "\(days) DAYS"
        }
        let target = deadline.date
        let seconds = Int(target.timeIntervalSince(now))
        if seconds < 0 { return "OVERDUE" }
        if seconds >= 86_400 { return "\(Int(ceil(Double(seconds) / 86_400))) DAYS" }
        if seconds >= 3_600 { return "\(Int(ceil(Double(seconds) / 3_600))) HOURS" }
        return "\(max(1, Int(ceil(Double(seconds) / 60)))) MIN"
    }

    static func upcoming(from data: AppData, now: Date, includePast: Bool = false) -> [Deadline] {
        data.deadlines.filter { deadline in
            deadline.completedAt == nil && (includePast || deadline.date >= now || Calendar.current.isDate(deadline.date, inSameDayAs: now))
        }.sorted {
            if $0.priority != $1.priority && abs($0.date.timeIntervalSince(now) - $1.date.timeIntervalSince(now)) < 7 * 86_400 { return $0.priority > $1.priority }
            return $0.date < $1.date
        }
    }
}

struct WorkloadAssessment {
    let isOverCapacity: Bool
    let activeBuildProjects: [Project]
    let scheduledHours: Double
    let explanation: String
}

enum WorkloadEngine {
    static func assess(data: AppData, weekContaining date: Date, calendar: Calendar) -> WorkloadAssessment {
        let primary = data.projects.filter { $0.status == .primary }
        // Heavy concurrent builds: the primary project plus any other active high-importance one.
        let otherHeavy = data.projects.filter { $0.status == .active && $0.importance >= .high }
        let active = primary + otherHeavy
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
        var minutes = 0
        var categoryMinutes: [ItemCategory: Int] = [:]
        var day = interval.start
        while day < interval.end {
            for item in ScheduleEngine.occurrences(on: day, data: data, calendar: calendar) where !item.isSkipped && item.source.category != .personal {
                let duration = Int(item.end.timeIntervalSince(item.start) / 60)
                minutes += duration
                categoryMinutes[item.source.category, default: 0] += duration
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        let hours = Double(minutes) / 60
        let overloaded = active.count > 1 || hours > 70
        let names = active.map(\.title).joined(separator: ", ")
        let consumers = categoryMinutes.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key.rawValue) \(String(format: "%.1f", Double($0.value) / 60))h" }.joined(separator: ", ")
        let reason = overloaded ? "\(String(format: "%.1f", hours)) work/focus hours this week (\(consumers)); active-build projects: \(names.isEmpty ? "none" : names). Keep one competition primary and move others to upcoming or backup." : "Capacity is within the one-primary rule (\(String(format: "%.1f", hours)) work/focus hours)."
        return WorkloadAssessment(isOverCapacity: overloaded, activeBuildProjects: active, scheduledHours: hours, explanation: reason)
    }
}

extension Date {
    func formattedTime(in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = zone
        return formatter.string(from: self)
    }

    func formattedDate(in zone: TimeZone, includeTime: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = includeTime ? .short : .none
        formatter.timeZone = zone
        return formatter.string(from: self)
    }
}
