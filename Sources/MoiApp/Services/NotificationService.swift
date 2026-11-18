import AppKit
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()
    private let center: UNUserNotificationCenter?
    private weak var store: AppStore?

    private override init() {
        // UserNotifications raises an Objective-C exception when a SwiftPM executable
        // is run directly from `.build` because that process has no application bundle
        // proxy. The dashboard should still run in that development mode;
        // notifications become available as soon as Moi runs from `Moi.app`.
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app", Bundle.main.bundleIdentifier != nil {
            center = UNUserNotificationCenter.current()
        } else {
            center = nil
        }
        super.init()
    }

    @MainActor
    func configure(store: AppStore) {
        self.store = store
        guard let center else { return }
        center.delegate = self
        let start = UNNotificationAction(identifier: "START", title: "Start", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "SNOOZE_5", title: "Snooze 5 min")
        let open = UNNotificationAction(identifier: "OPEN_DASHBOARD", title: "Open Dashboard", options: [.foreground])
        let complete = UNNotificationAction(identifier: "COMPLETE", title: "Complete")
        let extend = UNNotificationAction(identifier: "EXTEND_15", title: "Extend 15 min")
        let move = UNNotificationAction(identifier: "MOVE", title: "Move task", options: [.foreground])
        let plan = UNNotificationAction(identifier: "PLAN_TOMORROW", title: "Plan Tomorrow", options: [.foreground])
        // Checking something off must never require opening Moi.
        let done = UNNotificationAction(identifier: "DONE", title: "Done ✓")
        let later = UNNotificationAction(identifier: "LATER", title: "Remind me in 1 hour")
        let tomorrow = UNNotificationAction(identifier: "TOMORROW", title: "Remind me tomorrow")
        let openPlan = UNNotificationAction(identifier: "OPEN_PLAN", title: "Open plan", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "BLOCK_START", actions: [start, snooze, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "BLOCK_END", actions: [complete, extend, move], intentIdentifiers: []),
            UNNotificationCategory(identifier: "DEADLINE", actions: [done, later, tomorrow, openPlan], intentIdentifiers: []),
            UNNotificationCategory(identifier: "BRIEF", actions: [done, later, openPlan], intentIdentifiers: []),
            UNNotificationCategory(identifier: "EVENING", actions: [plan], intentIdentifiers: [])
        ])
    }

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        guard let center else { completion?(false); return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    func reschedule(using data: AppData, now: Date = Date()) {
        guard let center else {
            return
        }
        let prefix = "moi."
        guard data.settings.notificationsEnabled else {
            center.getPendingNotificationRequests { pending in
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !$0.hasPrefix("moi.snooze.") })
            }
            return
        }
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            // Snoozes are one-offs the user asked for; a reschedule must not swallow them.
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !$0.hasPrefix("moi.snooze.") })
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: data.settings.timeZoneID) ?? .current
            var blockRequests: [UNNotificationRequest] = []
            if data.settings.blockReminders != .off {
                let horizon = calendar.date(byAdding: .day, value: 7, to: now)!
                var day = calendar.startOfDay(for: now)
                while day <= horizon {
                    for item in ScheduleEngine.occurrences(on: day, data: data, calendar: calendar) where !item.isSkipped {
                        blockRequests += self.requests(for: item, data: data, now: now, calendar: calendar)
                    }
                    day = calendar.date(byAdding: .day, value: 1, to: day)!
                }
            }
            let important = self.deadlineRequests(data: data, now: now, calendar: calendar) + self.summaryRequests(data: data, now: now, calendar: calendar)
            for request in NotificationBudget.select(important: important, routine: blockRequests, date: triggerDate) { center.add(request) }
        }
    }

    private func requests(for item: ScheduleOccurrence, data: AppData, now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        let rule = item.source.notificationRule
        var entries: [(String, String, Date, String)] = []
        switch data.settings.blockReminders {
        case .off:
            return []
        case .workStart:
            // Meals, sleep and stretching don't need announcing; work blocks get one ping with their objective.
            guard rule.atStart, item.source.category != .personal else { return [] }
            let body = item.source.notes.isEmpty ? "Until \(item.end.formattedTime(in: calendar.timeZone))." : item.source.notes
            entries.append(("\(item.title) — starting now", body, item.start, "BLOCK_START"))
        case .detailed:
            let next = ScheduleEngine.nextOccurrence(after: item.end, data: data, calendar: calendar)
            for minute in rule.minutesBefore {
                let time = item.start.formattedTime(in: calendar.timeZone)
                entries.append(("\(minute) minutes until \(item.title)", "Starts at \(time). Wrap up what you're doing.", item.start.addingTimeInterval(TimeInterval(-minute * 60)), "BLOCK_START"))
            }
            if rule.atStart { entries.append(("\(item.title) starts now", "You're scheduled until \(item.end.formattedTime(in: calendar.timeZone)).", item.start, "BLOCK_START")) }
            for minute in rule.minutesBeforeEnd {
                let body = next.map { "\($0.title) is next at \($0.start.formattedTime(in: calendar.timeZone))." } ?? "Finish the thought you're on."
                entries.append(("\(minute) minutes left", body, item.end.addingTimeInterval(TimeInterval(-minute * 60)), "BLOCK_END"))
            }
            if rule.atEnd { entries.append(("\(item.title) is finished", next.map { "\($0.title) is next at \($0.start.formattedTime(in: calendar.timeZone))." } ?? "Your scheduled day is clear.", item.end, "BLOCK_END")) }
            if let followUp = rule.followUpMinutes, item.completion == nil { entries.append(("Still working on \(item.title)?", "Complete, move, or skip it when you're ready.", item.end.addingTimeInterval(TimeInterval(followUp * 60)), "BLOCK_END")) }
        }
        return entries.compactMap { title, body, fireDate, category in
            guard fireDate > now else { return nil }
            let info: [AnyHashable: Any] = ["blockID": item.source.id.uuidString, "occurrence": item.start.timeIntervalSince1970]
            return request(id: NotificationIdentity.block(blockID: item.source.id, occurrence: item.start, fireDate: fireDate), title: title, body: body, date: fireDate, category: category, sound: .notification, settings: data.settings, userInfo: info)
        }
    }

    /// Countdown reminders ("1 week away", "tomorrow", "3 hours left") that each name the
    /// next concrete step. Rescheduling after every change keeps the named step current.
    private func deadlineRequests(data: AppData, now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []
        let defaults = data.reminderDefaults ?? ReminderDefaults()
        for deadline in data.deadlines where deadline.completedAt == nil {
            let target = deadline.isDateOnly ? calendar.date(bySettingHour: 8, minute: 0, second: 0, of: deadline.date)! : deadline.date
            var offsets = deadline.reminderOffsetsMinutes ?? (defaults.deadlineDays.map { $0 * 1_440 } + (!deadline.isDateOnly ? defaults.exactTimeExtraMinutes : []))
            // Date-only deadlines also get a morning-of reminder unless custom offsets say otherwise.
            if deadline.isDateOnly && deadline.reminderOffsetsMinutes == nil { offsets.append(0) }
            let nextStep = NextUpEngine.nextStep(for: deadline, in: data)
            for offset in Set(offsets).sorted() {
                if deadline.isDateOnly && offset > 0 && offset < 1_440 { continue }
                let fire = target.addingTimeInterval(TimeInterval(-offset * 60))
                guard fire > now else { continue }
                let days = offset / 1_440
                let hours = !deadline.isDateOnly && offset < 1_440 ? offset / 60 : nil
                // On the day itself the useful question is "is it done?", not "what's the next step?".
                let asksIfDone = hours != nil || days == 0
                let step: (title: String, minutes: Int?, target: NextUpItem.Target)? = switch nextStep {
                case let .task(task): (task.title, task.durationMinutes, .task(task.id))
                case let .suggested(suggestion): (suggestion.title, suggestion.minutes, .suggestedStep(deadlineID: deadline.id))
                case .finishDeadline: nil
                }
                let doneTarget = asksIfDone ? .deadline(deadline.id) : step?.target ?? .deadline(deadline.id)
                var info: [AnyHashable: Any] = doneTarget.userInfo
                info["deadlineID"] = deadline.id.uuidString
                result.append(request(
                    id: "moi.deadline.\(deadline.id).\(offset)",
                    title: ReminderVoice.deadlineTitle(deadline.title, days: days, hours: hours),
                    body: ReminderVoice.deadlineBody(days: days, hours: hours, step: asksIfDone ? nil : step?.title, minutes: step?.minutes),
                    date: fire,
                    category: "DEADLINE",
                    sound: deadline.priority == .critical && offset <= 1_440 ? .attention : .notification,
                    settings: data.settings,
                    userInfo: info
                ))
            }
        }
        return result
    }

    private func summaryRequests(data: AppData, now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { continue }
            if data.settings.morningSummaryEnabled, let fire = calendar.date(bySettingHour: data.settings.morningSummaryTime.hour, minute: data.settings.morningSummaryTime.minute, second: 0, of: day), fire > now {
                let items = NextUpEngine.items(data: data, now: fire, calendar: calendar, limit: 3)
                let copy = ReminderVoice.morning(items)
                var info: [AnyHashable: Any] = items.first?.target.userInfo ?? [:]
                if let deadlineID = items.first?.deadlineID { info["deadlineID"] = deadlineID.uuidString }
                requests.append(request(id: "moi.summary.morning.\(Int(day.timeIntervalSince1970))", title: copy.title, body: copy.body, date: fire, category: items.isEmpty ? "SUMMARY" : "BRIEF", sound: .notification, settings: data.settings, userInfo: info))
            }
            if data.settings.eveningReviewEnabled, let fire = calendar.date(bySettingHour: data.settings.eveningReviewTime.hour, minute: data.settings.eveningReviewTime.minute, second: 0, of: day), fire > now,
               let tomorrowMorning = calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day) {
                let copy = ReminderVoice.evening(tomorrow: NextUpEngine.items(data: data, now: tomorrowMorning, calendar: calendar, limit: 1).first)
                requests.append(request(id: "moi.summary.evening.\(Int(day.timeIntervalSince1970))", title: copy.title, body: copy.body, date: fire, category: "EVENING", sound: .notification, settings: data.settings))
            }
        }
        return requests
    }

    private func request(id: String, title: String, body: String, date: Date, category: String, sound: MoiSound?, settings: UserSettings, userInfo: [AnyHashable: Any] = [:]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = userInfo
        if let sound { content.sound = MoiSoundController.notificationSound(for: sound, settings: settings) }
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let content = response.notification.request.content
        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { completionHandler(); return }
            let deadlineID = (info["deadlineID"] as? String).flatMap(UUID.init(uuidString:))
            switch response.actionIdentifier {
            case "DONE":
                if let target = NextUpItem.Target(userInfo: info) { store.complete(target) }
            case "LATER":
                self.scheduleSnooze(from: content, after: 60)
            case "TOMORROW":
                self.scheduleSnoozeTomorrow(from: content, calendar: store.calendar)
            case "OPEN_PLAN":
                store.openPlan(for: deadlineID)
            case UNNotificationDefaultActionIdentifier where deadlineID != nil:
                store.openPlan(for: deadlineID)
            case "OPEN_DASHBOARD", UNNotificationDefaultActionIdentifier:
                store.selectedSection = .overview
                NSApp.activate(ignoringOtherApps: true)
            case "MOVE", "PLAN_TOMORROW":
                store.selectedSection = .calendar
                NSApp.activate(ignoringOtherApps: true)
            default:
                break
            }
            if let raw = info["blockID"] as? String, let id = UUID(uuidString: raw), let stamp = info["occurrence"] as? TimeInterval, let block = store.data.scheduleBlocks.first(where: { $0.id == id }) {
                let occurrence = ScheduleEngine.occurrences(on: Date(timeIntervalSince1970: stamp), data: store.data, calendar: store.calendar).first { $0.source.id == block.id }
                if response.actionIdentifier == "COMPLETE", let occurrence { store.complete(occurrence) }
                if response.actionIdentifier == "START", let occurrence { store.startFocus(title: occurrence.title, durationMinutes: max(1, Int(occurrence.end.timeIntervalSince(Date()) / 60)), blockID: block.id) }
                if response.actionIdentifier == "SNOOZE_5" { self.scheduleSnooze(from: content, after: 5) }
                if response.actionIdentifier == "EXTEND_15" { store.startFocus(title: block.title, durationMinutes: 15, blockID: block.id) }
            }
            completionHandler()
        }
    }

    private func scheduleSnooze(from original: UNNotificationContent, after minutes: Int) {
        guard let center else { return }
        let copy = original.mutableCopy() as! UNMutableNotificationContent
        if !copy.title.hasPrefix("Reminder: ") { copy.title = "Reminder: \(original.title)" }
        center.add(UNNotificationRequest(identifier: "moi.snooze.\(UUID().uuidString)", content: copy, trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)))
    }

    private func scheduleSnoozeTomorrow(from original: UNNotificationContent, calendar: Calendar) {
        guard let center,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
              let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else { return }
        let copy = original.mutableCopy() as! UNMutableNotificationContent
        if !copy.title.hasPrefix("Reminder: ") { copy.title = "Reminder: \(original.title)" }
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        center.add(UNNotificationRequest(identifier: "moi.snooze.\(UUID().uuidString)", content: copy, trigger: trigger))
    }

    func sendIdentitySoundTest(settings: UserSettings) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Moi sounds like this"
        content.body = "The custom notification sound is active."
        content.sound = MoiSoundController.notificationSound(for: .notification, settings: settings)
        let request = UNNotificationRequest(
            identifier: "moi.sound-test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

}

private func triggerDate(_ request: UNNotificationRequest) -> Date {
    (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
}
