import Foundation

enum SeedData {
    static func initialData() -> AppData {
        var data = AppData()
        data.schemaVersion = 6
        data.settings.timeZoneID = TimeZone.current.identifier
        data.settings.notificationsEnabled = false
        data.settings.softBlockEnabled = true // only acts during a focus session you start
        return data
    }
}
