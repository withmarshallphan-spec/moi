import Foundation
import AppKit
@testable import MoiApp

final class WorkspaceChecks {
    func testFocusTimeExcludesPausesAndExpiration() {
        let start = Date(timeIntervalSince1970: 1000)
        var session = FocusSession(title: "Synthetic focus", startedAt: start, plannedEnd: start.addingTimeInterval(1500))
        checkEqual(session.elapsed(at: start.addingTimeInterval(3000)), 1500)
        session.pausedAt = start.addingTimeInterval(400)
        checkEqual(session.elapsed(at: start.addingTimeInterval(3000)), 400)
        session.pausedAt = nil
        session.plannedEnd = start.addingTimeInterval(1800)
        session.accumulatedPauseSeconds = 300
        checkEqual(session.elapsed(at: start.addingTimeInterval(3000)), 1500)
        session.endedAt = start.addingTimeInterval(900)
        checkEqual(session.elapsed(), 600)
    }
    func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moi-disposable-tests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testCorruptAndFutureStorePreservesOriginal() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("data.json")
        let invalid = Data("invalid JSON".utf8); try invalid.write(to: url)
        await MainActor.run {
            let store = AppStore(persistenceURL: url, startTimer: false)
            check(store.isReadOnly); store.addTask(title: "Must not persist"); store.save()
            check(store.data.tasks.isEmpty)
        }
        checkEqual(try Data(contentsOf: url), invalid)
        var future = AppData(); future.schemaVersion = 99
        try LocalStorage.save(future, to: url); let before = try Data(contentsOf: url)
        await MainActor.run { check(AppStore(persistenceURL: url, startTimer: false).isReadOnly) }
        checkEqual(try Data(contentsOf: url), before)
    }
    func testGenericFirstRunAndUnknownCategoryCompatibility() throws {
        let data = SeedData.initialData()
        check(data.tasks.isEmpty && data.projects.isEmpty && data.deadlines.isEmpty && data.scheduleBlocks.isEmpty)
        checkFalse(data.settings.notificationsEnabled)
        let category = ItemCategory(rawValue: "Private custom category")
        checkEqual(try JSONDecoder().decode(ItemCategory.self, from: JSONEncoder().encode(category)), category)
    }
    func testPersistenceDuplicateTitlesAndDeletedSeeds() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("data.json")
        var data = SeedData.initialData(); data.schemaVersion = 2
        data.launcherItems = (0..<2).map { LauncherItem(title:"Same",kind:.url,target:"https://example.com",symbol:"link",order:$0) }
        try LocalStorage.save(data, to: url)
        await MainActor.run {
            let store = AppStore(persistenceURL: url, startTimer: false)
            checkFalse(store.isReadOnly); checkEqual(store.data.launcherItems.count, 2)
            store.addTask(title: "Synthetic persisted task")
            checkNil(store.persistenceError)
            let next = AppStore(persistenceURL: url, startTimer: false)
            checkEqual(next.data.tasks.first?.title, "Synthetic persisted task")
            next.update { $0.launcherItems = [] }
            check(AppStore(persistenceURL: url, startTimer: false).data.launcherItems.isEmpty)
        }
    }
    func testRestoreCommitAndCrashRollback() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("data.json"))
        try LocalStorage.restore(["data.json": Data("new".utf8), "Assistant/index.json": Data("notes".utf8)], in: root)
        checkEqual(try String(contentsOf: root.appendingPathComponent("data.json"), encoding: .utf8), "new")
        checkEqual(try String(contentsOf: root.appendingPathComponent("Assistant/index.json"), encoding: .utf8), "notes")
        let pending = root.appendingPathComponent("Recovery/PendingRestore")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("before interruption".utf8).write(to: pending.appendingPathComponent("saved"))
        try Data(#"{"entries":[{"path":"data.json","snapshot":"saved"},{"path":"created.json"}],"committed":false}"#.utf8).write(to: pending.appendingPathComponent("manifest.json"))
        try Data("partial".utf8).write(to: root.appendingPathComponent("data.json"))
        try Data("partial".utf8).write(to: root.appendingPathComponent("created.json"))
        try LocalStorage.recoverRestore(in: root)
        checkEqual(try String(contentsOf: root.appendingPathComponent("data.json"), encoding: .utf8), "before interruption")
        checkFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("created.json").path))
        checkThrows(try LocalStorage.restore(["../escape": Data()], in: root))
    }
    func testBrainTrustBoundaries() {
        // A model can only name moi's own intents; anything else is plain text, never an action.
        checkNil(MoiCommand.parseJSONAnswer(#"{"reply":"ok","action":{"kind":"deleteFile","value":"/private"}}"#).intents.first)
        checkNil(MoiCommand.parseJSONAnswer(#"{"reply":"ok","action":{"kind":"shell","value":"rm -rf ~"}}"#).intents.first)
        checkEqual(MoiCommand.parseJSONAnswer("just words, not JSON").reply, "just words, not JSON")
        checkNil(MoiCommand.parseJSONAnswer("just words, not JSON").intents.first)
        // An unknown name resolves to nothing, so nothing is changed by mistake.
        var data = AppData(); data.tasks = [TaskItem(title: "Go to the gym")]
        checkNil(MoiCommand.resolve(.named("tax return"), in: data, last: nil))
        checkNil(MoiCommand.resolve(.last, in: data, last: nil))
    }
    func testOvernightShortWeekdayAndIndependentDeadlineIdentity() {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:"Asia/Jakarta")!
        let day=cal.date(from:DateComponents(year:2026,month:11,day:17))!
        var data=SeedData.initialData();data.settings.timeZoneID=cal.timeZone.identifier
        data.scheduleBlocks=[ScheduleBlock(title:"Overnight",startTime:LocalTime(22),endTime:LocalTime(2),category:.personal,recurrence:RecurringRule(weekdays:Set(1...7),startDate:day.addingTimeInterval(-86400)))]
        if case .active(let item,_) = ScheduleEngine.state(at:day.addingTimeInterval(3600),data:data,calendar:cal) {checkEqual(item.title,"Overnight")}else{checkFail("Overnight lost")}
        checkNotNil(QuickAddParser.parse("Finish draft due fri",now:day,calendar:cal).date)
        checkEqual(QuickAddParser.parse("SAT drills tomorrow",now:day,calendar:cal).title,"SAT drills")
        data.deadlines=(0..<2).map{Deadline(title:"Same title",date:day.addingTimeInterval(Double($0+1)*86400),isDateOnly:true,category:.personal,priority:.high)}
        checkEqual(Set(NextUpEngine.items(data:data,now:day,calendar:cal,limit:10).compactMap(\.deadlineID)).count,2)
    }
    func testMusicNotificationsAndQuietPresence() async throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        let spotify: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Synthetic Song", "Artist": "Test Artist", "Track ID": "spotify:track:abc", "Duration": NSNumber(value: 200_000), "Playback Position": NSNumber(value: 12.5)]
        let a = try unwrap(SpotifyPlaybackSnapshot.from(notification: spotify, previous: nil, now: t0))
        checkEqual(a.title, "Synthetic Song"); check(a.isPlaying); checkEqual(a.durationSeconds, 200); checkEqual(a.positionSeconds, 12.5)
        checkEqual(a.interpolatedPosition(at: t0.addingTimeInterval(10)), 22.5)
        // Apple Music: no position; same track carries the interpolated position, a new track starts at 0.
        let music: [AnyHashable: Any] = ["Player State": "Paused", "Name": "Synthetic Song", "Artist": "Test Artist", "PersistentID": NSNumber(value: 42), "Total Time": NSNumber(value: 180_000)]
        let b = try unwrap(SpotifyPlaybackSnapshot.from(notification: music, previous: nil, now: t0))
        checkFalse(b.isPlaying); checkEqual(b.trackID, "42"); checkEqual(b.durationSeconds, 180); checkEqual(b.positionSeconds, 0)
        var playing = b; playing.isPlaying = true
        checkEqual(try unwrap(SpotifyPlaybackSnapshot.from(notification: music, previous: playing, now: t0.addingTimeInterval(5))).positionSeconds, 5)
        checkNil(SpotifyPlaybackSnapshot.from(notification: ["Player State": "Stopped"], previous: a))
        checkNil(SpotifyPlaybackSnapshot.from(notification: ["Player State": "Playing"], previous: nil))
    }
}

private var assertions = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do { if try !value() { fatalError("FAILED: \(message) at \(file):\(line)") } } catch { fatalError("Unexpected error: \(error) at \(file):\(line)") }
}
func checkEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) { do { let x = try a(), y = try b(); check(x == y, "\(x) != \(y)") } catch { fatalError("Unexpected error: \(error)") } }
func checkFalse(_ value: @autoclosure () throws -> Bool) { do { let x = try value(); check(!x) } catch { fatalError("\(error)") } }
func checkNil<T>(_ value: T?) { check(value == nil) }
func checkNotNil<T>(_ value: T?) { check(value != nil) }
func checkThrows<T>(_ action: @autoclosure () throws -> T) { do { _ = try action(); fatalError("Expected refusal") } catch { assertions += 1 } }
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw MoiError.message("Missing test result.") }; return value }
func checkFail(_ message: String) { fatalError(message) }

@main struct WorkspaceTestRunner {
    static func main() async throws {
        let t = WorkspaceChecks()
        t.testFocusTimeExcludesPausesAndExpiration()
        try await t.testCorruptAndFutureStorePreservesOriginal()
        try t.testGenericFirstRunAndUnknownCategoryCompatibility()
        try await t.testPersistenceDuplicateTitlesAndDeletedSeeds()
        try t.testRestoreCommitAndCrashRollback()
        t.testBrainTrustBoundaries()
        t.testOvernightShortWeekdayAndIndependentDeadlineIdentity()
        try await t.testMusicNotificationsAndQuietPresence()
        print("PASS: 8 workspace scenarios, \(assertions) assertions; restore, persistence, focus, music parsing and brain trust boundaries.")
    }
}
