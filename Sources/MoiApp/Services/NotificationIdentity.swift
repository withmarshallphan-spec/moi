import Foundation

enum NotificationIdentity {
    static func block(blockID: UUID, occurrence: Date, fireDate: Date) -> String {
        "moi.block.\(blockID).\(Int(occurrence.timeIntervalSince1970)).\(Int(fireDate.timeIntervalSince1970))"
    }
}

/// Decides which reminders get one of macOS's limited pending-notification slots.
///
/// Routine schedule pings used to compete with deadlines purely by date. A single day
/// of block reminders filled every slot, so "one week left" reminders were never
/// scheduled at all. Important reminders now get first claim; routine ones fill what's left.
enum NotificationBudget {
    /// Below the system's cap of 64 pending requests, leaving room for snoozes.
    static let total = 60
    static let important = 44

    static func select<T>(important: [T], routine: [T], date: (T) -> Date) -> [T] {
        let chosen = Array(important.sorted { date($0) < date($1) }.prefix(Self.important))
        let filler = routine.sorted { date($0) < date($1) }.prefix(total - chosen.count)
        return chosen + filler
    }
}
