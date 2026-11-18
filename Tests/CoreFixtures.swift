import Foundation

// Fictional test fixtures only. Never included in the application target.
enum CoreFixtures {
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute))!
    }
    static func initialData() -> AppData {
        var data = AppData(); data.schemaVersion = 6; data.settings.timeZoneID = "Asia/Jakarta"
        let every = Set(1...7), weekday = Set(2...6)
        func block(_ title: String, _ start: LocalTime, _ end: LocalTime, days: Set<Int>) -> ScheduleBlock {
            ScheduleBlock(title: title, startTime: start, endTime: end, category: .personal, recurrence: RecurringRule(weekdays: days, startDate: date(2026, 1, 1)))
        }
        data.scheduleBlocks = [
            block("SAT", LocalTime(9), LocalTime(10,30), days: weekday),
            block("Research", LocalTime(10,45), LocalTime(12), days: weekday),
            block("Creative work", LocalTime(14), LocalTime(15,15), days: weekday),
            block("Application admin", LocalTime(15,30), LocalTime(17), days: weekday),
            block("Gym", LocalTime(18), LocalTime(19), days: every),
            block("Wind Down", LocalTime(23), LocalTime(0), days: every),
            block("Sleep", LocalTime(0), LocalTime(8), days: every),
            block("Full Timed Mock", LocalTime(9), LocalTime(12), days: [7]),
            block("SAT Mock Review", LocalTime(9), LocalTime(10), days: [1]),
            block("Weekly Planning", LocalTime(14), LocalTime(15), days: [1])
        ]
        let project = Project(title: "Demo portfolio", status: .active, importance: .high, category: .creative)
        data.projects = [project]
        var la = Calendar(identifier: .gregorian); la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        data.deadlines = [
            Deadline(title: "Example submission", date: la.date(from: DateComponents(year:2026,month:9,day:15,hour:23,minute:59))!, isDateOnly: false, originalTimeZoneID: "America/Los_Angeles", category: ItemCategory(rawValue: "Competition"), priority: .critical),
            Deadline(title: "Official SAT", date: date(2026,11,7,12), isDateOnly: true, category: ItemCategory(rawValue: "SAT"), priority: .critical),
            Deadline(title: "Bluebook Mock", date: date(2026,9,26,12), isDateOnly: true, category: ItemCategory(rawValue: "SAT"), priority: .critical),
            Deadline(title: "Bluebook Mock", date: date(2026,10,10,12), isDateOnly: true, category: ItemCategory(rawValue: "SAT"), priority: .critical),
            Deadline(title: "Portfolio V1 freeze", date: date(2026,9,30,12), isDateOnly: true, category: .creative, priority: .high, projectID: project.id)
        ]
        data.launcherItems = [
            LauncherItem(title: "Safari", kind: .application, target: "com.apple.Safari", symbol: "safari", order: 0),
            LauncherItem(title: "Study reference", kind: .url, target: "https://example.com", symbol: "book", order: 1)
        ]
        return data
    }
}
