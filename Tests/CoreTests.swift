import Foundation

@main
struct CoreTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
        else { print("PASS: \(message)") }
    }

    static func main() throws {
        var data = CoreFixtures.initialData()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!

        let houseTime = CoreFixtures.date(2026, 9, 3, 14, 32)
        if case let .active(item, next) = ScheduleEngine.state(at: houseTime, data: data, calendar: calendar) {
            expect(item.title == "Creative work", "current-block calculation")
            expect(Int(item.end.timeIntervalSince(houseTime) / 60) == 43, "remaining time calculation")
            expect(next?.title == "Application admin", "next-block calculation")
        } else { expect(false, "current-block calculation") }

        let gapTime = CoreFixtures.date(2026, 9, 3, 10, 35)
        if case let .gap(previous, next) = ScheduleEngine.state(at: gapTime, data: data, calendar: calendar) {
            expect(previous?.title == "SAT" && next?.title == "Research", "unscheduled gap calculation")
        } else { expect(false, "unscheduled gap calculation") }

        let mockDay = CoreFixtures.date(2026, 9, 12)
        let mockMorning = ScheduleEngine.occurrences(on: mockDay, data: data, calendar: calendar).filter { calendar.component(.hour, from: $0.start) == 9 }
        expect(mockMorning.count == 1 && mockMorning.first?.title == "Full Timed Mock", "recurring override prevents duplicate SAT block")

        let sundayTitles = ScheduleEngine.occurrences(on: CoreFixtures.date(2026, 9, 6), data: data, calendar: calendar).map(\.title)
        expect(sundayTitles.contains("SAT Mock Review") && sundayTitles.contains("Weekly Planning") && !sundayTitles.contains("SAT"), "weekly special rules")

        if case let .active(windDown, next) = ScheduleEngine.state(at: CoreFixtures.date(2026, 9, 3, 23, 45), data: data, calendar: calendar) {
            expect(windDown.title == "Wind Down" && next?.title == "Sleep", "cross-midnight next-block calculation")
        } else { expect(false, "cross-midnight next-block calculation") }

        let breakthrough = data.deadlines.first { $0.title == "Example submission" }!
        let converted = calendar.dateComponents([.day, .hour, .minute], from: breakthrough.date)
        expect(breakthrough.originalTimeZoneID == "America/Los_Angeles" && converted.day == 16 && converted.hour == 13 && converted.minute == 59, "PDT to WIB conversion")

        let sat = data.deadlines.first { $0.title == "Official SAT" }!
        let satDate = calendar.dateComponents([.month, .day], from: sat.date)
        expect(sat.isDateOnly && satDate.month == 11 && satDate.day == 7, "date-only deadline does not timezone-shift")
        expect(DeadlineEngine.countdown(to: sat, now: CoreFixtures.date(2026, 11, 5, 12), calendar: calendar) == "2 DAYS", "deadline countdown")
        expect(DeadlineEngine.countdown(to: sat, now: CoreFixtures.date(2026, 11, 7, 18), calendar: calendar) == "TODAY", "date-only deadline remains current all day")

        let gym = data.scheduleBlocks.first { $0.title == "Gym" }!
        data.overrides.append(DailyOverride(blockID: gym.id, date: CoreFixtures.date(2026, 9, 3), isSkipped: true))
        expect(ScheduleEngine.occurrences(on: CoreFixtures.date(2026, 9, 3), data: data, calendar: calendar).first { $0.source.id == gym.id }!.isSkipped, "one-day skip override")

        let nid = UUID(), occurrence = CoreFixtures.date(2026, 9, 3, 9), fire = CoreFixtures.date(2026, 9, 3, 8, 50)
        expect(NotificationIdentity.block(blockID: nid, occurrence: occurrence, fireDate: fire) == NotificationIdentity.block(blockID: nid, occurrence: occurrence, fireDate: fire), "notification deduplication identity")

        data.completions.append(CompletionRecord(sourceID: gym.id, occurrenceDate: CoreFixtures.date(2026, 9, 3), state: .completed))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AppData.self, from: encoder.encode(data))
        expect(restored.completions.first?.state == .completed, "completion persistence round-trip")

        // MARK: Forward compatibility of the on-disk file
        //
        // AppStore treats a decode failure as "no data yet" and overwrites data.json with
        // seed data, so a file that fails to decode means the user's real schedule, tasks
        // and deadlines are destroyed. Swift's synthesized Decodable throws on missing
        // keys rather than using property defaults, so every added field is a potential
        // data-loss bug unless AppData decodes tolerantly. This guards that.
        let legacyJSON = """
        {"schemaVersion":3,"scheduleBlocks":[],"overrides":[],"completions":[],"tasks":[],
         "projects":[],"deadlines":[],"focusSessions":[],"launcherItems":[],
         "settings":{"hudEnabled":true,"timeZoneID":"Asia/Jakarta"},
         "seededAt":"2026-09-03T00:00:00Z"}
        """
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        let legacy = try? legacyDecoder.decode(AppData.self, from: Data(legacyJSON.utf8))
        expect(legacy != nil, "persistence: a file written before newer fields existed still decodes")
        expect(legacy?.modes.isEmpty == true, "persistence: a missing field falls back to its default")
        expect(legacy?.settings.timeZoneID == "Asia/Jakarta", "persistence: present settings survive the fallback")
        expect(legacy?.settings.hudOpacity == 0.94, "persistence: absent settings take their default rather than throwing")
        expect(legacy?.settings.moiSoundsEnabled == true && legacy?.settings.moiNotificationSoundEnabled == true,
               "persistence: older files adopt Moi sound defaults")
        expect(legacy?.settings.moiHaloEnabled == true && legacy?.settings.moiHaloIntensity == .standard,
               "persistence: older files adopt standard halo presence")
        var identitySettings = UserSettings()
        identitySettings.moiSummonSoundEnabled = false
        identitySettings.moiHaloIntensity = .vivid
        let restoredIdentitySettings = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(identitySettings))
        expect(!restoredIdentitySettings.moiSummonSoundEnabled,
               "persistence: independent Moi sound settings round-trip")
        expect(restoredIdentitySettings.moiHaloIntensity == .vivid,
               "persistence: halo intensity round-trips")

        // MARK: Next up

        let seed = CoreFixtures.initialData()
        let morning = CoreFixtures.date(2026, 9, 24, 10)
        let upNext = NextUpEngine.items(data: seed, now: morning, calendar: calendar, limit: 5)
        expect(upNext.first?.detail == "Bluebook Mock · 2 days", "next up: the nearest important deadline leads")
        expect(upNext.contains { $0.detail.hasPrefix("Portfolio V1 freeze") }, "next up: a deadline without a plan still offers a first step")
        expect(upNext.allSatisfy { item in
            guard let id = item.deadlineID, let deadline = seed.deadlines.first(where: { $0.id == id }) else { return true }
            return deadline.date >= calendar.startOfDay(for: morning)
        }, "next up: passed deadlines are left to the tidy-up card")
        expect(upNext.filter { $0.detail.hasPrefix("Bluebook Mock") }.count == 2, "next up: independent same-title deadlines remain visible")
        expect(NextUpEngine.passedDeadlines(data: seed, now: morning, calendar: calendar).contains { $0.title == "Example submission" },
               "next up: an unmarked past deadline is offered for tidy-up")

        let portfolio = seed.deadlines.first { $0.title == "Portfolio V1 freeze" }!
        let plan = DeadlinePlan.tasks(for: portfolio, steps: DeadlinePlaybook.match(portfolio.title).steps, now: morning, calendar: calendar)
        expect(plan.count == DeadlinePlaybook.match(portfolio.title).steps.count, "plan: every playbook step becomes a task")
        expect(plan.first.map { calendar.isDate($0.date!, inSameDayAs: morning) } == true, "plan: the first step is today")
        expect(plan.last.map { calendar.isDate($0.date!, inSameDayAs: CoreFixtures.date(2026, 9, 29)) } == true, "plan: the last step lands the day before the deadline")
        expect(plan.allSatisfy { $0.deadlineID == portfolio.id && $0.projectID == portfolio.projectID }, "plan: steps link back to the deadline and project")
        let lastMinute = DeadlinePlan.tasks(for: portfolio, steps: DeadlinePlaybook.general.steps, now: CoreFixtures.date(2026, 9, 30, 9), calendar: calendar)
        expect(lastMinute.allSatisfy { calendar.isDate($0.date!, inSameDayAs: CoreFixtures.date(2026, 9, 30)) }, "plan: with no room left, every step lands today")

        var planned = seed
        var adopted = plan
        adopted[0].completedAt = morning
        planned.tasks += adopted
        expect(NextUpEngine.nextStep(for: portfolio, in: planned) == .task(adopted[1]), "plan: the next step is the first unfinished one")
        let plannedNext = NextUpEngine.items(data: planned, now: morning, calendar: calendar, limit: 10)
        expect(plannedNext.contains { $0.target == .task(adopted[1].id) } && !plannedNext.contains { $0.target == .suggestedStep(deadlineID: portfolio.id) },
               "plan: an adopted plan replaces the suggestion")
        for index in adopted.indices { adopted[index].completedAt = morning }
        var finished = seed
        finished.tasks += adopted
        expect(NextUpEngine.nextStep(for: portfolio, in: finished) == .finishDeadline, "plan: with every step done, the deadline itself is next")

        let doneTarget = NextUpItem.Target.suggestedStep(deadlineID: portfolio.id)
        expect(NextUpItem.Target(userInfo: doneTarget.userInfo) == doneTarget, "notifications: a Done target survives userInfo")

        // MARK: Playbooks

        expect(DeadlinePlaybook.match("Portfolio V1 freeze").id == "portfolio", "playbook: portfolio")
        expect(DeadlinePlaybook.match("Official SAT").id == "test-day", "playbook: the real SAT is test day")
        expect(DeadlinePlaybook.match("Bluebook Mock").id == "practice-test", "playbook: a mock is a practice test")
        expect(DeadlinePlaybook.match("SAT score / retake decision").id == "decision", "playbook: a decision beats its subject")
        expect(DeadlinePlaybook.match("Common App personal essay final content").id == "essay", "playbook: essay wins over 'final'")
        expect(DeadlinePlaybook.match("Breakthrough peer review begins").id == "peer-review", "playbook: peer review wins over 'begins'")
        expect(DeadlinePlaybook.match("Conrad Phase 1 ends").id == "general", "playbook: unknown titles get the general plan")
        let prompt = ResearchPrompt.make(deadline: portfolio, project: seed.projects.first { $0.id == portfolio.projectID }, steps: [], aboutMe: "Senior applying to design programs", now: morning, calendar: calendar)
        expect(prompt.contains("Portfolio V1 freeze") && prompt.contains("6 days from now") && prompt.contains("About me: Senior"), "research: the brief carries the deadline, time left, and context")
        expect(ResearchPrompt.claudeURL(for: "a & b")?.absoluteString == "https://claude.ai/new", "research: the browser URL never contains the private prompt")

        // MARK: Reminder voice

        expect(ReminderVoice.deadlineTitle("Portfolio", days: 7) == "Portfolio — 1 week away", "voice: a week out")
        expect(ReminderVoice.deadlineTitle("Portfolio", days: 1) == "Portfolio is tomorrow", "voice: tomorrow")
        expect(ReminderVoice.deadlineTitle("Pitch", days: 0, hours: 3) == "Pitch — 3 hours left", "voice: hours left")
        expect(ReminderVoice.deadlineBody(days: 7, step: "List projects", minutes: 20).hasSuffix("Next: List projects (20 min)."), "voice: reminders name the next step")
        expect(ReminderVoice.deadlineBody(days: 0, step: nil, minutes: nil).contains("tap Done"), "voice: day-of asks whether it's done")

        // MARK: Notification budget

        let dates = (0..<200).map { Date(timeIntervalSince1970: TimeInterval($0 * 60)) }
        let importantLate = (0..<10).map { Date(timeIntervalSince1970: TimeInterval(1_000_000 + $0)) }
        let budget = NotificationBudget.select(important: importantLate, routine: dates) { $0 }
        expect(budget.count == NotificationBudget.total, "budget: never exceeds the system cap")
        expect(importantLate.allSatisfy(budget.contains), "budget: distant deadline reminders aren't crowded out by a day of block pings")

        // MARK: Quick add

        let thursday = CoreFixtures.date(2026, 9, 24, 10) // a Thursday
        let due = QuickAddParser.parse("Portfolio V2 due oct 15", now: thursday, calendar: calendar)
        expect(due.isDeadline && due.title == "Portfolio V2" && calendar.dateComponents([.month, .day], from: due.date!) == DateComponents(month: 10, day: 15),
               "quick add: 'due' plus a month-day makes a deadline")
        let friday = QuickAddParser.parse("Call Sam friday at 14:30", now: thursday, calendar: calendar)
        expect(friday.title == "Call Sam" && calendar.isDate(friday.date!, inSameDayAs: CoreFixtures.date(2026, 9, 25)) && friday.time == LocalTime(14, 30) && !friday.isDeadline,
               "quick add: weekday and time")
        let later = QuickAddParser.parse("finish essay in 3 days", now: thursday, calendar: calendar)
        expect(later.title == "finish essay" && calendar.isDate(later.date!, inSameDayAs: CoreFixtures.date(2026, 9, 27)), "quick add: in N days")
        // Personal categories come from the person's own data, never from code.
        let satCategory = ItemCategory(rawValue: "SAT"), mine = ItemCategory.options(in: data)
        expect(!ItemCategory.allCases.contains(satCategory) && mine.contains(satCategory) && mine.contains(ItemCategory(rawValue: "Competition")), "categories: own categories come from data, not built-ins")
        expect(QuickAddParser.parse("Gym saturday", now: thursday, calendar: calendar, categories: mine).category != satCategory, "quick add: Saturday isn't the SAT")
        expect(QuickAddParser.parse("sat down with notes tomorrow", now: thursday, calendar: calendar, categories: mine).category != satCategory, "quick add: lowercase 'sat' isn't the SAT")
        expect(QuickAddParser.parse("SAT drills tomorrow", now: thursday, calendar: calendar, categories: mine).category == satCategory, "quick add: own SAT category recognised")
        expect(QuickAddParser.parse("SAT drills tomorrow", now: thursday, calendar: calendar).category == .personal, "quick add: without that category it stays Personal")
        let wrapped = QuickAddParser.parse("Essay due 3 jan", now: thursday, calendar: calendar)
        expect(calendar.component(.year, from: wrapped.date!) == 2027, "quick add: a date that has passed this year means next year")

        // MARK: Day answers (deterministic, records only)

        let routes: [(String, DayAnswers.Question?)] = [("What should I do today?", .today), ("What do I have tomorrow?", .tomorrow), ("What's next?", .next),
            ("What am I behind on?", .behind), ("What should I prioritize?", .prioritize), ("How much time do I have?", .freeTime), ("What did I complete today?", .completed), ("hello", nil)]
        expect(routes.allSatisfy { DayAnswers.question(for: $0.0) == $0.1 }, "answers: every directive question routes to its deterministic answer")
        let thursdayAfternoon = CoreFixtures.date(2026, 9, 3, 14, 32)
        let answersData = CoreFixtures.initialData()
        let nextAnswer = DayAnswers.answer(.next, data: answersData, now: thursdayAfternoon, calendar: calendar)
        expect(nextAnswer.contains("Now: Creative work") && nextAnswer.contains("Next on the schedule: Application admin"), "answers: what's next uses the live schedule")
        expect(DayAnswers.answer(.tomorrow, data: answersData, now: thursdayAfternoon, calendar: calendar).contains("SAT"), "answers: tomorrow lists Friday's blocks")
        // 14:32 → 21:30 evening review = 418 min; Creative 43 + Admin 90 + Gym 60 scheduled = 193; free 225.
        expect(DayAnswers.answer(.freeTime, data: answersData, now: thursdayAfternoon, calendar: calendar).contains("about 3h 45m free"), "answers: free time subtracts remaining blocks")
        expect(DayAnswers.mergedMinutes([(thursdayAfternoon, thursdayAfternoon.addingTimeInterval(3600)), (thursdayAfternoon.addingTimeInterval(1800), thursdayAfternoon.addingTimeInterval(5400))]) == 90, "answers: overlapping blocks are not double-counted")
        expect(DayAnswers.answer(.today, data: AppData(), now: thursdayAfternoon, calendar: calendar) == "Nothing is scheduled or due today in moi.", "answers: empty records say so instead of inventing")
        var behindData = answersData
        behindData.tasks = [TaskItem(title: "Synthetic overdue essay", date: CoreFixtures.date(2026, 9, 1)), TaskItem(title: "Synthetic undated idea")]
        expect(DayAnswers.answer(.behind, data: behindData, now: thursdayAfternoon, calendar: calendar).contains("Synthetic overdue essay"), "answers: overdue tasks are reported")
        expect(DayAnswers.answer(.completed, data: behindData, now: thursdayAfternoon, calendar: calendar) == "Nothing is marked done today in moi yet.", "answers: nothing is inferred as completed")
        behindData.tasks[1].completedAt = thursdayAfternoon
        expect(DayAnswers.answer(.completed, data: behindData, now: thursdayAfternoon, calendar: calendar).contains("Synthetic undated idea"), "answers: marked-done tasks are reported")

        // MARK: moi's voice

        let voiceMorning = CoreFixtures.date(2026, 9, 3, 9)
        expect(MoiVoice.greeting(name: "Sam", at: voiceMorning, calendar: calendar).contains("Sam"), "voice: greeting uses the name")
        expect((0..<3).map { MoiVoice.greeting(name: "", at: voiceMorning.addingTimeInterval(Double($0) * 86_400), calendar: calendar) }.allSatisfy { !$0.contains(",!") && !$0.contains(",.") && !$0.contains(" ,") }, "voice: no dangling comma without a name")
        expect(MoiVoice.greeting(name: "Sam", at: voiceMorning, calendar: calendar) == MoiVoice.greeting(name: "Sam", at: voiceMorning.addingTimeInterval(600), calendar: calendar), "voice: the line doesn't change between redraws")
        expect(MoiVoice.daySummary(dueToday: 0, overdue: 2, nextTitle: "Essay", done: 0).contains("2 things slipped"), "voice: overdue comes first, with the real count")
        expect(MoiVoice.daySummary(dueToday: 3, overdue: 0, nextTitle: "Essay", done: 0).contains("3 things today") , "voice: today's count is real")
        expect(MoiVoice.daySummary(dueToday: 0, overdue: 0, nextTitle: nil, done: 0) == "Nothing on the list. Suspiciously peaceful.", "voice: empty day says so")
        expect(DayAnswers.summaryLine(data: AppData(), now: thursdayAfternoon, calendar: calendar) == "Nothing on the list. Suspiciously peaceful.", "voice: summary line reads real records")

        // MARK: Persona

        expect(MoiPersona.answer(to: "Who are you?")?.contains("I'm moi") == true, "persona: who are you is answered in character")
        expect(MoiPersona.answer(to: "who made you")?.contains("Marshall") == true, "persona: origin")
        expect(MoiPersona.answer(to: "hi") != nil && MoiPersona.answer(to: "Moi!") != nil, "persona: greetings")
        expect(MoiPersona.answer(to: "help me write an email to my teacher") == nil, "persona: real requests go on to the model")
        expect(MoiPersona.answer(to: "good morning, what's on today?") == nil, "persona: small talk doesn't swallow a question")
        let personaPrompt = MoiPersona.instructions(name: "Sam", context: "")
        expect(personaPrompt.contains("Sam") && !personaPrompt.contains("their day"), "persona: prompt names the user, no schedule unless given")
        expect(MoiPersona.instructions(name: "", context: "Schedule").contains("Schedule"), "persona: on-device context included when given")

        // MARK: Typed commands ("add …" however it's phrased)

        let cmdNow = Date()
        var cmdCal = Calendar(identifier: .gregorian); cmdCal.timeZone = .current
        func addParsed(_ text: String) -> ParsedQuickTask? { MoiCommand.addPhrase(from: text).map { QuickAddParser.parse($0, now: cmdNow, calendar: cmdCal) } }
        let gymCmd = addParsed("add a schedule for tomorrow for me to go to the gym at 16:30")
        expect(gymCmd?.title == "go to the gym" && gymCmd?.time == LocalTime(16, 30) && gymCmd?.date == cmdCal.date(byAdding: .day, value: 1, to: cmdCal.startOfDay(for: cmdNow)), "command: the gym-tomorrow-16:30 sentence becomes a timed item tomorrow")
        let mum = addParsed("remind me to call mum on 3 dec")
        expect(mum?.title == "call mum" && mum.flatMap { $0.date.map { cmdCal.component(.month, from: $0) } } == 12, "command: remind me to … on a date")
        let dentist = addParsed("Can you put dentist on my calendar friday at 4:30pm?")
        expect(dentist?.title == "dentist" && dentist?.time == LocalTime(16, 30) && dentist.flatMap { $0.date.map { cmdCal.component(.weekday, from: $0) } } == 6, "command: put … on my calendar, 12-hour time")
        expect(addParsed("add task call the dentist")?.title == "call the dentist", "command: old 'add task' still works")
        expect(addParsed("schedule essay due friday")?.isDeadline == true, "command: due makes a deadline")
        expect(MoiCommand.addPhrase(from: "put on some music") == nil && MoiCommand.addPhrase(from: "what do I have tomorrow?") == nil && MoiCommand.addPhrase(from: "add tomorrow") == nil, "command: questions and non-requests are left alone")
        expect(QuickAddParser.parse("lunch at noon", now: cmdNow, calendar: cmdCal).time == LocalTime(12, 0) && QuickAddParser.parse("call 9am", now: cmdNow, calendar: cmdCal).time == LocalTime(9, 0), "quick add: noon and am/pm")
        expect(MoiCommand.describe(ParsedQuickTask(title: "Gym", date: cmdCal.date(byAdding: .day, value: 1, to: cmdCal.startOfDay(for: cmdNow)), time: LocalTime(16, 30), category: .gym), now: cmdNow, calendar: cmdCal) == "“Gym” for tomorrow at 16:30", "command: confirmation says what and when")

        // MARK: Understanding requests (edit, finish, delete, follow-ups)

        func said(_ text: String) -> MoiIntent? { MoiCommand.intent(from: text, now: cmdNow, calendar: cmdCal) }
        expect(said("edit it for 1630 tomorrow") == .move(.last, when: "for 1630 tomorrow"), "intent: 'edit it for 1630 tomorrow' moves the last item")
        expect(DayAnswers.question(for: "edit it for 1630 tomorrow") == nil, "intent: a request that mentions tomorrow is not a question about tomorrow")
        expect(said("move gym to friday 5pm") == .move(.named("gym"), when: "to friday 5pm"), "intent: move by name")
        expect(said("tomorrow at 4pm") == .when("tomorrow at 4pm"), "intent: a bare time is a follow-up for the last item")
        expect(said("mark gym as done") == .complete(.named("gym")) && said("I finished the essay") == .complete(.named("essay")), "intent: finishing things")
        expect(said("delete the dentist") == .delete(.named("dentist")), "intent: delete by name")
        expect(said("clean up my desktop") == .cleanUp("desktop") && said("take a screenshot") == .screenshot && said("undo") == .undo, "intent: Mac actions and undo")
        expect(said("focus on essay for 50 minutes") == .focus("essay", minutes: 50) && said("open safari") == .open("safari", browser: nil, private: false), "intent: focus and open")
        expect(said("what do I have tomorrow?") == nil && said("who are you") == nil, "intent: questions are left for answers")
        if case .add = said("add a schedule for tomorrow for me to go to the gym at 16:30") {} else { expect(false, "intent: add still wins for add requests") }

        var planData = AppData()
        let gymTask = TaskItem(title: "Go to the gym"), essayDeadline = Deadline(title: "History essay", date: cmdCal.date(bySettingHour: 12, minute: 0, second: 0, of: cmdNow)!, isDateOnly: true, category: .study, priority: .high)
        planData.tasks = [gymTask, TaskItem(title: "Call mum")]; planData.deadlines = [essayDeadline]
        expect(MoiCommand.resolve(.named("gym"), in: planData, last: nil) == .task(gymTask.id) && MoiCommand.resolve(.named("the essay"), in: planData, last: nil) == .deadline(essayDeadline.id), "resolve: finds items by a word of their name")
        expect(MoiCommand.resolve(.named("dentist"), in: planData, last: nil) == nil && MoiCommand.resolve(.last, in: planData, last: .task(gymTask.id)) == .task(gymTask.id), "resolve: unknown names find nothing; 'it' is the last item")
        let movedGym = MoiCommand.move(.task(gymTask.id), to: "for 1630 tomorrow", in: &planData, now: cmdNow, calendar: cmdCal)
        let tomorrowStart = cmdCal.date(byAdding: .day, value: 1, to: cmdCal.startOfDay(for: cmdNow))
        expect(movedGym?.time == LocalTime(16, 30) && planData.tasks[0].date == tomorrowStart && planData.tasks[0].startTime == LocalTime(16, 30), "move: the task gets tomorrow at 16:30")
        MoiCommand.move(.task(gymTask.id), to: "at 6pm", in: &planData, now: cmdNow, calendar: cmdCal)
        expect(planData.tasks[0].date == tomorrowStart && planData.tasks[0].startTime == LocalTime(18, 0), "move: a time alone keeps the day")
        MoiCommand.move(.deadline(essayDeadline.id), to: "at 17:00", in: &planData, now: cmdNow, calendar: cmdCal)
        expect(cmdCal.component(.hour, from: planData.deadlines[0].date) == 17 && cmdCal.isDate(planData.deadlines[0].date, inSameDayAs: cmdNow) && !planData.deadlines[0].isDateOnly, "move: a deadline gets an exact time on the same day")
        MoiCommand.complete(.task(gymTask.id), in: &planData, now: cmdNow)
        MoiCommand.delete(.deadline(essayDeadline.id), in: &planData)
        expect(planData.tasks[0].isCompleted && planData.deadlines.isEmpty && planData.tasks.count == 2, "complete and delete touch only their item")
        expect(QuickAddParser.parse("call 2026 plan", now: cmdNow, calendar: cmdCal).time == nil, "quick add: a bare 4-digit number isn't a time")
        expect(MoiCommand.parseJSONAnswer(#"{"reply":"Done","action":{"kind":"move","target":"gym","value":"tomorrow 16:30"}}"#).intents == [.move(.named("gym"), when: "tomorrow 16:30")], "brain: a model's JSON maps to the same intents")

        // The sentences Apple's model got wrong are now understood without it.
        expect(said("forget about calling mum") == .delete(.named("mum")), "intent: forget about calling mum deletes Call mum, nothing else")
        expect(said("the history essay is finished") == .complete(.named("history essay")), "intent: 'is finished' completes")
        if case let .move(target, when)? = said("can you shift my dentist thing to the afternoon on tuesday, like 3") {
            let p = QuickAddParser.parse(when, now: cmdNow, calendar: cmdCal)
            expect(target == .named("dentist") && p.time == LocalTime(15, 0) && p.date.map { cmdCal.component(.weekday, from: $0) } == 3, "intent: dentist → Tuesday 15:00")
        } else { expect(false, "intent: dentist → Tuesday 15:00") }
        expect(QuickAddParser.parse("buy milk at 6", now: cmdNow, calendar: cmdCal).time == LocalTime(18, 0) && QuickAddParser.parse("gym friday evening", now: cmdNow, calendar: cmdCal).time == LocalTime(18, 0), "quick add: 'at 6' is evening; parts of the day get a time")

        expect(!MoiCommand.grounded(.add("12"), in: "how many answers do you have") && !MoiCommand.grounded(.add("Call the dentist cgi film"), in: "what are those 12?"), "grounding: invented adds from questions are dropped")
        expect(MoiCommand.grounded(.add("dentist friday 16:30"), in: "pop the dentist on my calendar friday at half four") && !MoiCommand.grounded(.delete(.named("gym")), in: "is the gym still on?"), "grounding: real requests pass, questions never change the plan")

        // MARK: Mac actions (parsing only; nothing on the real Mac is touched)

        expect(said("open pornhub on safari private browser") == .open("pornhub", browser: "Safari", private: true), "mac: open a site in a Safari private window")
        expect(said("open youtube in incognito") == .open("youtube", browser: nil, private: true) && said("go to github.com") == .open("github.com", browser: nil, private: false), "mac: private without a browser; a domain")
        expect(Web.url(for: "pornhub")?.absoluteString == "https://www.pornhub.com" && Web.url(for: "github.com/apple")?.absoluteString == "https://github.com/apple" && Web.url(for: "bad name!") == nil, "mac: website addresses")
        expect(Web.privateFlag(forBrowser: "Brave Browser") == "--incognito" && Web.privateFlag(forBrowser: "Firefox") == "--private-window" && Web.privateFlag(forBrowser: "Safari") == nil, "mac: private-window flags per browser")
        expect(said("search for best pasta recipe") == .webSearch("best pasta recipe") && said("google weather in rome") == .webSearch("weather in rome"), "mac: web search")
        expect(said("quit everything except safari and spotify") == .quitApps([], allExcept: ["safari", "spotify"]) && said("close all apps") == .quitApps([], allExcept: []) && said("quit discord") == .quitApps(["discord"], allExcept: nil), "mac: quit apps")
        expect(said("hide everything but figma") == .hideApps(allExcept: ["figma"]) && said("what's open") == .showApps && said("show me everything that's running") == .showApps, "mac: hide and see open apps")
        expect(said("remove discord from my dock") == .dockRemove(["discord"]) && said("add spotify to the dock") == .dockAdd(["spotify"]) && said("clean up my dock") == .showDock, "mac: the Dock")
        expect(said("clean up my downloads") == .cleanUp("downloads") && said("tidy my documents") == .cleanUp("documents"), "mac: clean up any folder")
        if case .findPhotos = said("sort all my flower photos") {} else { expect(false, "photos: sort my flower photos") }
        if case .findPhotos = said("find the photos from my trip in italy") {} else { expect(false, "photos: trip in italy") }
        expect(PhotoQuery.parse("sort all my flower photos") == PhotoQuery(subjects: ["flower"], place: nil, year: nil), "photos: subjects")
        expect(PhotoQuery.parse("find the photos from my trip in italy") == PhotoQuery(subjects: [], place: "italy", year: nil), "photos: a place")
        expect(PhotoQuery.parse("dog photos at the beach 2023") == PhotoQuery(subjects: ["dog", "beach"], place: nil, year: 2023), "photos: scenes are subjects, years are years")
        expect(PhotoQuery.matches(subject: "flower", labels: ["outdoor", "rose"]) && PhotoQuery.matches(subject: "dog", labels: ["retriever"]) && !PhotoQuery.matches(subject: "dog", labels: ["cat", "hotdog"]), "photos: label matching")
        let many = PhotoQuery.parseAll("sort my flower photos and my trips")
        expect(many.count == 2 && many[0].subjects == ["flower"] && many[1].trips && many[1].subjects.isEmpty && many[1].title == "Trips", "photos: several things at once, and “my trips”")
        expect(PhotoQuery.parseAll("dogs, cats & trip to italy").map(\.title) == ["Dog", "Cat", "Italy"] && PhotoQuery.parse("trip to italy").trips == false, "photos: lists split; a named trip is a place")
        expect(PhotoQuery.parse("food on my holidays") == PhotoQuery(subjects: ["food"], place: nil, year: nil, trips: true), "photos: things seen on trips")
        let day: TimeInterval = 86_400, t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var pts = (0..<20).map { Trips.Point(date: t0.addingTimeInterval(Double($0) * day), lat: -6.2, lon: 106.8) } // home (Jakarta)
        pts += (0..<4).map { Trips.Point(date: t0.addingTimeInterval(30 * day + Double($0) * 3600), lat: 45.46, lon: 9.19) } // Milan, one day
        pts += (0..<3).map { Trips.Point(date: t0.addingTimeInterval(33 * day + Double($0) * day), lat: 41.9, lon: 12.5) } // Rome, 3 days later: a new trip
        pts += [Trips.Point(date: t0.addingTimeInterval(60 * day), lat: -8.65, lon: 115.2)] // one Bali photo: too few for a trip
        let home = Trips.home(pts)!
        expect(abs(home.lat + 6.2) < 0.01 && Trips.group(pts, home: home) == [Array(20..<24), Array(24..<27)], "trips: home is where most photos are; gaps split trips; tiny ones dropped")
        expect(abs(Trips.km((-6.2, 106.8), (-8.65, 115.2)) - 965) < 25, "trips: distances in km")
        expect(FreeName.pick("front.png", taken: ["front.png"], exists: { $0 == "front 2.png" }) == "front 3.png" && FreeName.pick("a", taken: [], exists: { _ in false }) == "a", "folders: same-named files get a free name instead of failing")
        expect(said("set my wallpaper to a flower photo") == .wallpaper("flower photo") && said("make a sunset photo my wallpaper") == .wallpaper("sunset photo"), "mac: wallpaper from a photo")
        expect(MoiCommand.intent(kind: "open", target: "", value: "pornhub in private in safari") == .open("pornhub", browser: "Safari", private: true) && MoiCommand.intent(kind: "add", target: "", value: "dentist on Friday at 4:30 PM") == .add("dentist on Friday at 4:30 PM"), "brain: Gemini's real answers map cleanly")
        if case .findPhotos = said("sort my trips") {} else { expect(false, "photos: sort my trips") }
        expect(MoiCommand.parseJSONAnswer(#"{"reply":"On it","actions":[{"kind":"photos","value":"flowers"},{"kind":"quit","value":"Spotify, Discord"}]}"#).intents == [.findPhotos("flowers"), .quitApps(["Spotify", "Discord"], allExcept: nil)], "brain: several actions in one answer")
        let dock: [DockLayout.Item] = ["Safari", "Discord", "Spotify"].map { ["tile-data": ["file-label": $0, "file-data": ["_CFURLString": "file:///Applications/\($0).app/", "_CFURLStringType": 15]], "tile-type": "file-tile"] }
        let trimmed = DockLayout.removing(["discord"], from: dock)
        expect(trimmed.removed == ["Discord"] && trimmed.items.map(DockLayout.label) == ["Safari", "Spotify"], "dock: remove by name, keep the rest in order")
        let grown = DockLayout.adding(appAt: URL(fileURLWithPath: "/Applications/Notes.app"), bundleID: "com.apple.Notes", to: dock)
        expect(grown.count == 4 && DockLayout.label(grown[3]) == "Notes" && DockLayout.adding(appAt: URL(fileURLWithPath: "/Applications/Safari.app/"), bundleID: nil, to: dock).count == 3, "dock: add once, never twice")
        expect(MoiCommand.intent(kind: "quit_all", target: "", value: "Safari") == .quitApps([], allExcept: ["Safari"]) && MoiCommand.intent(kind: "photos", target: "", value: "flowers") == .findPhotos("flowers"), "brain: tool actions map to the same intents")

        let geminiIDs = ["gemini-omni-flash-preview", "gemini-3-flash-preview", "gemini-flash-latest", "gemini-2.5-flash", "gemini-3.8-flash", "gemini-3.5-flash", "gemini-3.8-flash-tts", "gemini-2.5-flash-lite"]
        expect(MoiCommand.freeModelCandidates(provider: "gemini", available: geminiIDs) == ["gemini-flash-latest", "gemini-3.8-flash", "gemini-3.5-flash", "gemini-2.5-flash"], "free brain: stable Gemini models first, never previews (the 429)")
        expect(MoiCommand.freeModelCandidates(provider: "groq", available: ["whisper-large-v3", "llama-3.3-70b-versatile", "openai/gpt-oss-120b"]).first == "llama-3.3-70b-versatile", "free brain: Groq's strong default")

        expect(said("wrap up my day") == .wrapUp && said("i'm done for today") == .wrapUp && said("let's call it a day") == .wrapUp && MoiCommand.intent(kind: "wrap_up", target: "", value: "") == .wrapUp, "wrap up: the end-of-day ritual")
        expect(said("gym tomorrow 16:30") != .wrapUp, "wrap up: doesn't swallow plans")

        // MARK: Brain chain
        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        expect(BrainChain.order(primary: "gemini", ready: ["gemini", "groq", "nvidia", "apple", "openai"], allowPaid: false, resting: [:], now: noon) == ["gemini", "groq", "nvidia", "apple"], "chain: main brain, free backups, Apple last; paid never without an OK")
        expect(BrainChain.order(primary: "gemini", ready: ["gemini", "groq", "apple"], allowPaid: false, resting: ["gemini": noon.addingTimeInterval(60)], now: noon) == ["groq", "apple"], "chain: a resting brain is skipped, the chat carries on")
        expect(BrainChain.order(primary: "gemini", ready: ["gemini", "groq"], allowPaid: false, resting: ["gemini": noon.addingTimeInterval(-1)], now: noon).first == "gemini", "chain: a brain wakes when its rest is over")
        expect(BrainChain.order(primary: "openai", ready: ["openai", "anthropic", "groq"], allowPaid: false, resting: [:], now: noon) == ["openai", "groq"] && BrainChain.order(primary: "groq", ready: ["groq", "openai"], allowPaid: true, resting: [:], now: noon) == ["groq", "openai"], "chain: a chosen paid brain is fine; paid backups only when allowed")
        expect(BrainChain.order(primary: "moi", ready: ["gemini", "apple"], allowPaid: true, resting: [:], now: noon).isEmpty, "chain: “no AI” means no AI")
        expect(BrainChain.rest(status: 429, retryAfter: 41, daily: false, now: noon) == noon.addingTimeInterval(41) && BrainChain.rest(status: 429, retryAfter: nil, daily: false, now: noon) == noon.addingTimeInterval(60) && BrainChain.rest(status: 503, retryAfter: nil, daily: false, now: noon) == noon.addingTimeInterval(30) && BrainChain.rest(status: 401, retryAfter: nil, daily: false, now: noon) == noon.addingTimeInterval(86_400), "chain: rests match the failure")
        let pt = TimeZone(identifier: "America/Los_Angeles")!
        let wake = BrainChain.rest(status: 429, retryAfter: 41, daily: true, now: noon)
        var ptCal = Calendar(identifier: .gregorian); ptCal.timeZone = pt
        expect(wake > noon && wake.timeIntervalSince(noon) <= 86_400 && ptCal.component(.hour, from: wake) == 0 && ptCal.component(.minute, from: wake) == 0, "chain: a used-up daily quota rests until midnight Pacific")
        let geminiBody = #"[{"error":{"code":429,"message":"You exceeded your current quota","details":[{"violations":[{"quotaId":"GenerateRequestsPerDayPerProjectPerModel-FreeTier"}]},{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"41s"}]}}]"#
        let limit = BrainChain.readLimit(body: geminiBody, retryAfterHeader: nil)
        expect(limit.retryAfter == 41 && limit.daily && BrainChain.readLimit(body: "{}", retryAfterHeader: "7").retryAfter == 7, "chain: reads Gemini's retry delay and daily quota, and Retry-After headers")
        expect(BrainChain.detect(key: " AIzaSyA ") == "gemini" && BrainChain.detect(key: "gsk_abc") == "groq" && BrainChain.detect(key: "sk-or-v1-x") == "openrouter" && BrainChain.detect(key: "nvapi-x") == "nvidia" && BrainChain.detect(key: "sk-ant-x") == "anthropic" && BrainChain.detect(key: "abc123") == nil, "keys: whose key it is, from its shape")
        expect(MoiCommand.freeModelCandidates(provider: "openrouter", available: ["openai/gpt-4o", "meta-llama/llama-3.3-70b-instruct:free", "foo/bar:free"]) == ["meta-llama/llama-3.3-70b-instruct:free", "foo/bar:free"], "free brain: OpenRouter only ever gets :free models")

        // MARK: Desktop tidy (synthetic folder in the temp directory, never the real Desktop)

        let fm = FileManager.default
        let desk = fm.temporaryDirectory.appendingPathComponent("moi-tidy-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: desk, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: desk) }
        let old = Date().addingTimeInterval(-3600)
        for name in ["Screenshot 2026-11-18 at 10.00.png", "photo.jpg", "essay.pdf", "song.mp3", "setup.dmg", "notes.xyz", "partial.crdownload", ".hidden"] {
            let url = desk.appendingPathComponent(name)
            try Data("synthetic".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
        try Data("synthetic".utf8).write(to: desk.appendingPathComponent("fresh.txt"))
        try fm.createDirectory(at: desk.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: desk.appendingPathComponent("link"), withDestinationURL: desk.appendingPathComponent("photo.jpg"))
        let tidyPlan = try DesktopTidy.plan(desktop: desk, now: Date(), isScreenshot: { DesktopTidy.looksLikeScreenshot($0.lastPathComponent) })
        let tidyKinds = Dictionary(uniqueKeysWithValues: tidyPlan.moves.map { (URL(fileURLWithPath: $0.from).lastPathComponent, URL(fileURLWithPath: $0.to).deletingLastPathComponent().lastPathComponent) })
        expect(tidyKinds == ["Screenshot 2026-11-18 at 10.00.png": "Screenshots", "photo.jpg": "Images", "essay.pdf": "Documents", "song.mp3": "Audio & video", "setup.dmg": "Installers & archives", "notes.xyz": "Other"], "tidy: sorts loose files by kind")
        expect(tidyPlan.left.count == 3 && fm.fileExists(atPath: desk.appendingPathComponent("fresh.txt").path), "tidy: leaves links, partial downloads and just-saved files alone")
        expect(tidyKinds["Projects"] == nil && tidyKinds[".hidden"] == nil, "tidy: never moves folders or hidden files")
        expect(fm.fileExists(atPath: desk.appendingPathComponent("photo.jpg").path) && !fm.fileExists(atPath: tidyPlan.folder.path), "tidy: the preview changes nothing")
        let tidied = DesktopTidy.apply(tidyPlan)
        expect(tidied.failures.isEmpty && tidied.record.moves.count == 6 && fm.fileExists(atPath: tidyPlan.folder.appendingPathComponent("Images/photo.jpg").path), "tidy: moves into one dated folder")
        try Data("new".utf8).write(to: desk.appendingPathComponent("essay.pdf")) // a new file took the old spot
        let putBack = DesktopTidy.undo(tidied.record)
        expect(putBack.restored == 5 && putBack.failures.count == 1, "tidy undo: restores everything whose spot is free")
        expect((try? String(contentsOf: desk.appendingPathComponent("essay.pdf"), encoding: .utf8)) == "new" && fm.fileExists(atPath: tidyPlan.folder.appendingPathComponent("Documents/essay.pdf").path), "tidy undo: never overwrites, keeps the blocked file safe in the folder")
        expect(!fm.fileExists(atPath: tidyPlan.folder.appendingPathComponent("Images").path), "tidy undo: removes only emptied folders")
        let junk = desk.appendingPathComponent("junk-\(UUID().uuidString.prefix(6)).txt")
        try Data("synthetic".utf8).write(to: junk)
        let binned = DesktopTidy.trash([junk.path])
        expect(binned.failures.isEmpty && !fm.fileExists(atPath: junk.path) && binned.record.trashed == true, "trash: only the chosen file goes to the Trash")
        let unbinned = DesktopTidy.undo(binned.record)
        expect(unbinned.restored == 1 && fm.fileExists(atPath: junk.path), "trash: put back from the Trash")
        let dupA = desk.appendingPathComponent("dup-a.txt"), dupB = desk.appendingPathComponent("dup-b.txt"), solo = desk.appendingPathComponent("solo.txt")
        try Data("same bytes".utf8).write(to: dupA); try Data("same bytes".utf8).write(to: dupB); try Data("diff bytes".utf8).write(to: solo)
        let dupGroups = DesktopTidy.duplicateGroups([dupA.path, dupB.path, solo.path])
        expect(dupGroups.count == 1 && Set(dupGroups[0]) == [dupA.path, dupB.path], "duplicates: exact copies found, same-size different files are not")
        for f in [dupA, dupB, solo] { try? fm.removeItem(at: f) }
        let second = try DesktopTidy.plan(desktop: desk, now: Date(), isScreenshot: { _ in false })
        expect(second.folder.lastPathComponent.hasSuffix(" 2"), "tidy: a second tidy the same day gets its own folder")
        expect(RecentFiles.latest(in: [desk], limit: 2).count == 2 && RecentFiles.latest(in: [desk, desk], limit: 50).count == Set(RecentFiles.latest(in: [desk], limit: 50)).count, "recent: newest files, no duplicates")

        // MARK: Compatibility

        let legacyTask = #"{"id":"6B1D2C8E-2B7A-4E0B-9E43-3E0B6A1C9D11","title":"Old","notes":"","priority":"normal","category":"Personal","notificationMinutesBefore":[]}"#
        expect((try? decoder.decode(TaskItem.self, from: Data(legacyTask.utf8)))?.deadlineID == nil, "compat: tasks saved before plans still decode")
        let legacySettings = try decoder.decode(UserSettings.self, from: Data(#"{"hudEnabled":false}"#.utf8))
        expect(legacySettings.blockReminders == .workStart && legacySettings.researchContext.isEmpty && !legacySettings.hudEnabled, "compat: older settings get quiet block reminders by default")

        if failures > 0 { print("\n\(failures) test(s) failed"); exit(1) }
        print("\nAll core tests passed")
    }
}
