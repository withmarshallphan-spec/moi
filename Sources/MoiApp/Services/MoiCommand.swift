import Foundation

/// Understands "please add something" however it's phrased, without a model:
/// "add a schedule for tomorrow for me to go to the gym at 16:30" → "tomorrow go to the gym at 16:30",
/// which `QuickAddParser` then turns into a title, a day and a time.
enum MoiCommand {
    private static let lead = #"^(?:(?:hey |hi |ok |okay )?moi[,!]?\s+)?(?:(?:can|could|would|will) you\s+|please\s+|pls\s+)*"#
    private static let verbs = #"(?:add|schedule|put|create|remind me(?: to)?|set (?:up )?(?:a )?reminder(?: to| for)?|new task:?|to-?do:?|task:)"#

    /// The add phrase for `AppStore.quickAdd`, or nil when the message isn't asking to add something.
    static func addPhrase(from text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        guard let match = t.range(of: lead + verbs + #"\s+"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        // "put" only counts when it says where ("put dentist on my calendar"), so "put on some music" isn't a task.
        if t[match].lowercased().contains("put"), t.range(of: #"\b(calendar|schedule|list|planner|tasks?|to-?dos?)\b"#, options: [.regularExpression, .caseInsensitive]) == nil { return nil }
        t = String(t[match.upperBound...])
        let fillers = [
            #"^(?:a |an |my |the )?(?:new )?(?:schedule|event|task|reminder|to-?do|appointment|block|session|meeting|plan)s?\b\s*(?:for |to |called |named |:)?"#,
            #"\b(?:on|to|in|into) (?:my |the )?(?:calendar|schedule|list|tasks?|to-?dos?|planner)\b"#,
            #"\bfor me to\b"#, #"\bfor me\b"#, #"\bthat i (?:need|have|want) to\b"#, #"\bplease\b"#,
            #"^(?:to|that)\s+"#,
        ]
        for pattern in fillers { t = t.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive]) }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",:")))
        // What's left must name something, not only a when ("add tomorrow").
        let probe = QuickAddParser.parse(t, now: Date(), calendar: .current)
        return probe.title.isEmpty ? nil : t
    }

    /// "“Go to the gym” for tomorrow at 16:30" — how moi confirms what it added.
    static func describe(_ parsed: ParsedQuickTask, now: Date, calendar: Calendar) -> String {
        var when = ""
        if let date = parsed.date {
            let today = calendar.startOfDay(for: now)
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 99
            let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
            f.dateFormat = (0..<7).contains(days) ? "EEEE" : "EEE d MMM"
            when = days == 0 ? "today" : days == 1 ? "tomorrow" : f.string(from: date)
        }
        if let time = parsed.time { when += (when.isEmpty ? "" : " ") + "at " + String(format: "%02d:%02d", time.hour, time.minute) }
        return "“\(parsed.title)”" + (parsed.isDeadline ? " as a deadline" : "") + (when.isEmpty ? "" : (parsed.isDeadline ? ", due " : " for ") + when)
    }
}

/// Something in the plan: a task or a deadline.
enum PlanItemRef: Equatable { case task(UUID), deadline(UUID) }
/// How a message points at an item: "it" (the last one moi touched) or by name ("gym").
enum ItemRef: Equatable { case last, named(String) }

/// Everything moi can do from one message, understood without a model.
enum MoiIntent: Equatable {
    case add(String)                     // phrase for `AppStore.quickAdd`
    case move(ItemRef, when: String)     // "move gym to 5pm", "edit it for 1630 tomorrow"
    case when(String)                    // only a time ("tomorrow at 4pm"): applies to the last item
    case complete(ItemRef)
    case delete(ItemRef)
    case cleanUp(String?)                // a folder: desktop, downloads, documents, pictures, home
    case screenshot, undo
    case focus(String, minutes: Int?)
    case open(String, browser: String?, private: Bool)   // an app, or a website
    case webSearch(String)
    case findPhotos(String)              // "flower photos", "trip in italy", "dog 2023"
    case wallpaper(String)               // a photo to find and put on the desktop: "a flower photo"
    case showApps                        // what's open
    case quitApps([String], allExcept: [String]?)        // nil = just these; [] = everything
    case hideApps(allExcept: [String])
    case dockAdd([String]), dockRemove([String]), showDock
}

extension MoiCommand {
    private static let politeLead = #"^(?:(?:hey |hi |ok |okay )?moi[,!]?\s+)?(?:(?:can|could|would|will) you\s+|please\s+|pls\s+)*"#

    static func intent(from text: String, now: Date = Date(), calendar: Calendar = .current) -> MoiIntent? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        let t = raw.replacingOccurrences(of: politeLead, with: "", options: [.regularExpression, .caseInsensitive])
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
            return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: t).map { String(t[$0]) } ?? "" }
        }
        func hasWhen(_ phrase: String) -> Bool { let p = QuickAddParser.parse(phrase, now: now, calendar: calendar); return p.date != nil || p.time != nil }

        func list(_ s: String) -> [String] { s.replacingOccurrences(of: #"\s+(?:and|&)\s+"#, with: ",", options: [.regularExpression, .caseInsensitive]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^(?:the|my)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]) }.filter { !$0.isEmpty } }

        if match(#"^(?:undo(?: that)?|take that back|never ?mind)$"#) != nil { return .undo }
        // The Dock
        if let g = match(#"^(?:remove|take|delete|get rid of|unpin)\s+(.+?)\s+(?:from|off|out of)\s+(?:my |the )?dock$"#) { return .dockRemove(list(g[1])) }
        if let g = match(#"^(?:add|put|pin)\s+(.+?)\s+(?:to|in|on|into)\s+(?:my |the )?dock$"#) { return .dockAdd(list(g[1])) }
        if match(#"\b(?:clean|tidy|sort|organi[sz]e|edit|fix|show|change)\b.*\bdock\b"#) != nil { return .showDock }
        // Folders
        if match(#"^(?:clean|tidy|declutter|sort)(?:\s+(?:it|this))?(?:\s+up)?(?:\s+everything)?$"#) != nil { return .cleanUp("screen") }
        if match(#"\b(?:clean|tidy|organi[sz]e|declutter|sort)\b.*\b(?:home screen|screen|workspace|desktop and apps)\b"#) != nil { return .cleanUp("screen") }
        if let g = match(#"\b(?:clean|tidy|organi[sz]e|declutter|sort out|sort)\b(?:\s+up)?\s+(?:my |the )?(desktop|downloads?|documents|pictures|home(?: folder)?)\b"#) { return .cleanUp(g[1].lowercased()) }
        // Open apps and windows
        if match(#"\b(?:what'?s|what is|what are|show(?: me)?|see|list)\b.*\b(?:open|running)\b"#) != nil, match(#"\bphotos?\b"#) == nil { return .showApps }
        if let g = match(#"^(?:quit|close|kill)\s+(?:all|everything|every app|all (?:my )?(?:apps|windows))(?:\s+(?:except|but|apart from|other than)\s+(.+))?$"#) { return .quitApps([], allExcept: g[1].isEmpty ? [] : list(g[1])) }
        if let g = match(#"^hide\s+(?:all|everything|every app|all (?:my )?(?:apps|windows))(?:\s+(?:except|but|apart from|other than)\s+(.+))?$"#) { return .hideApps(allExcept: g[1].isEmpty ? [] : list(g[1])) }
        if let g = match(#"^(?:quit|close|kill)\s+(.+?)(?:\s+app)?$"#) { return .quitApps(list(g[1]), allExcept: nil) }
        // Wallpaper, from a photo moi finds
        if let g = match(#"^(?:set|change|make|use)\s+(?:my\s+|the\s+)?(?:wallpaper|desktop(?: background| picture)?|background)\s+(?:to|as|into)\s+(?:an?\s+|my\s+|one of my\s+)?(.+?)$"#) { return .wallpaper(g[1]) }
        if let g = match(#"^(?:make|set|use|choose|pick|recommend)\s+(?:an?\s+|my\s+|one of my\s+)?(.+?)\s+(?:(?:as|for)\s+)?(?:my\s+|the\s+)?(?:wallpaper|desktop background|background)$"#) { return .wallpaper(g[1]) }
        // Photos by what's in them, where, or when
        if match(#"^(?:sort|find|show|gather|organi[sz]e|group)\s+(?:all\s+)?(?:of\s+)?(?:my\s+)?(?:trips|holidays|vacations|travels)\b"#) != nil { return .findPhotos(t) }
        if match(#"\b(?:photos?|pictures?|pics|images)\b"#) != nil, match(#"^(?:what|when|how|why|who|which|where|do|does|did|is|are)\b"#) == nil, match(#"\b(?:sort|find|show|gather|collect|organi[sz]e|group|put|make|album|search|look for|get)\b"#) != nil || match(#"\b(?:trip|holiday|vacation)\b"#) != nil { return .findPhotos(t) }
        if match(#"\b(?:clean|tidy|organi[sz]e|sort|declutter)\b.*\bdesktop\b"#) != nil { return .cleanUp("desktop") }
        if match(#"^(?:take |grab |capture )?(?:a )?screen ?shot$"#) != nil || match(#"\b(?:take|grab|capture)\b.*\bscreen ?shot\b"#) != nil { return .screenshot }
        if let g = match(#"^(?:start |begin )?(?:a )?focus(?:ing)?(?: session| mode)?(?:\s+(?:on|for))?\s*(.*)$"#) {
            var title = g[1], minutes: Int?
            if let m = title.range(of: #"\b(?:for\s+)?(\d{1,3})\s*(?:min(?:ute)?s?|m)\b"#, options: [.regularExpression, .caseInsensitive]) {
                minutes = Int(title[m].filter(\.isNumber)); title.removeSubrange(m)
            } else if let m = title.range(of: #"\b(?:for\s+)?(?:an?|1|one)\s+hours?\b"#, options: [.regularExpression, .caseInsensitive]) {
                minutes = 60; title.removeSubrange(m)
            }
            return .focus(title.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ","))), minutes: minutes)
        }
        if let g = match(#"^(?:search|look up|google)\s+(?:the web\s+|online\s+|google\s+|the internet\s+)?(?:for\s+)?(.+)$"#) { return .webSearch(g[1]) }
        if let g = match(#"^(?:open|go to|visit|launch|pull up)\s+(?:the\s+)?(?:app\s+)?(.+?)(?:\s+app)?$"#) {
            var name = g[1], browser: String?
            if let r = name.range(of: #"\s+(?:in|on|with|using)\s+(?:a\s+|an\s+)?(?:new\s+)?(?:(safari|google chrome|chrome|brave|firefox|edge|arc|opera|vivaldi))?\s*(?:private|incognito)?\s*(?:browser|window|tab|mode)?.*$"#, options: [.regularExpression, .caseInsensitive]) {
                let tail = name[r].lowercased()
                browser = ["safari", "google chrome", "chrome", "brave", "firefox", "edge", "arc", "opera", "vivaldi"].first { tail.contains($0) }
                name.removeSubrange(r)
            }
            let isPrivate = g[1].range(of: #"\b(?:private|incognito)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            name = name.replacingOccurrences(of: #"\s+(?:privately|in private|incognito)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            return .open(name.trimmingCharacters(in: .whitespaces), browser: browser.map { $0 == "chrome" ? "Google Chrome" : $0.prefix(1).uppercased() + $0.dropFirst() }, private: isPrivate)
        }
        if let g = match(#"^(?:mark|tick off|check off|cross off|complete|finish)\s+(.+?)(?:\s+as)?(?:\s+(?:done|complete|completed|finished))?$"#) { return .complete(ref(g[1])) }
        if let g = match(#"^(?:i\s+)?(?:finished|completed|did|am done with|done with)\s+(.+)$"#) { return .complete(ref(g[1])) }
        if let g = match(#"^(.+?)\s+(?:is\s+)?(?:done|finished|completed)$"#), !g[1].contains(" ") || g[1].split(separator: " ").count <= 5 { return .complete(ref(g[1])) }
        if let g = match(#"^(?:delete|remove|cancel|drop|scrap|get rid of|forget(?: about)?)\s+(.+)$"#) { return .delete(ref(g[1].replacingOccurrences(of: #"^(?:calling|doing|going to)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]))) }
        // Move: keep the preposition in the "when" so "for 1630" still reads as a time.
        if let g = match(#"^(?:move|reschedule|change|edit|push|shift|update|set|make|put)\s+(it|that|this|that one|the last one)\s+(.+)$"#), hasWhen(g[2]) { return .move(.last, when: g[2]) }
        if let g = match(#"^(?:move|reschedule|change|edit|push|shift|update)\s+(.+?)\s+((?:to|for|at|until|till|on|by)\s+.+)$"#), hasWhen(g[2]) { return .move(ref(g[1]), when: g[2]) }
        if let phrase = addPhrase(from: raw) { return .add(phrase) }
        // Only a when, nothing else: it's about the last thing moi touched.
        let parsed = QuickAddParser.parse(t, now: now, calendar: calendar)
        let leftover = parsed.title.replacingOccurrences(of: #"^(?:on|at|for|to|and|make it|do it|it)\b\s*"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
        if (parsed.date != nil || parsed.time != nil), leftover.isEmpty || ["it", "then", "instead", "please"].contains(leftover.lowercased()) { return .when(t) }
        return nil
    }

    private static func ref(_ text: String) -> ItemRef {
        let t = text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",."))).lowercased()
        if ["it", "that", "this", "that one", "this one", "the last one", "the task", "the event", "the reminder"].contains(t) { return .last }
        return .named(text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",."))).replacingOccurrences(of: #"^(?:the|my)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"\s+(?:thing|one|stuff)$"#, with: "", options: [.regularExpression, .caseInsensitive]))
    }

    /// Finds the open task or deadline a name points at, by shared words. Ties go to the soonest.
    static func resolve(_ ref: ItemRef, in data: AppData, last: PlanItemRef?) -> PlanItemRef? {
        guard case let .named(name) = ref else { return last }
        let stop: Set<String> = ["the", "my", "a", "an", "task", "event", "reminder", "deadline", "to", "for", "of", "session"]
        func words(_ s: String) -> Set<String> { Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)).subtracting(stop) }
        let want = words(name)
        guard !want.isEmpty else { return last }
        let candidates: [(PlanItemRef, String, Date)] = data.tasks.filter { !$0.isCompleted }.map { (.task($0.id), $0.title, $0.date ?? .distantFuture) }
            + data.deadlines.filter { $0.completedAt == nil }.map { (.deadline($0.id), $0.title, $0.date) }
        let scored = candidates.map { c -> (PlanItemRef, Double, Date) in
            let have = words(c.1)
            let exact = c.1.localizedCaseInsensitiveContains(name) ? 1.0 : 0
            return (c.0, exact + Double(want.intersection(have).count) / Double(want.count), c.2)
        }.filter { $0.1 >= 0.5 }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.first?.0
    }

    static func title(of item: PlanItemRef, in data: AppData) -> String? {
        switch item {
        case let .task(id): data.tasks.first { $0.id == id }?.title
        case let .deadline(id): data.deadlines.first { $0.id == id }?.title
        }
    }

    /// Gives an item the day and/or time in `phrase`. A time alone keeps its day (today if it had none).
    @discardableResult
    static func move(_ item: PlanItemRef, to phrase: String, in data: inout AppData, now: Date, calendar: Calendar) -> ParsedQuickTask? {
        let parsed = QuickAddParser.parse(phrase, now: now, calendar: calendar)
        guard parsed.date != nil || parsed.time != nil else { return nil }
        let today = calendar.startOfDay(for: now)
        switch item {
        case let .task(id):
            guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return nil }
            if let day = parsed.date { data.tasks[i].date = calendar.startOfDay(for: day) }
            if let time = parsed.time {
                data.tasks[i].startTime = time
                if data.tasks[i].date == nil { data.tasks[i].date = today }
                if data.tasks[i].durationMinutes == nil { data.tasks[i].durationMinutes = 60 }
            }
            let task = data.tasks[i]
            return ParsedQuickTask(title: task.title, date: task.date, time: task.startTime, category: task.category)
        case let .deadline(id):
            guard let i = data.deadlines.firstIndex(where: { $0.id == id }) else { return nil }
            let day = parsed.date.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: data.deadlines[i].date)
            let parts = parsed.time.map { (h: $0.hour, m: $0.minute) } ?? (data.deadlines[i].isDateOnly ? (h: 12, m: 0) : (h: calendar.component(.hour, from: data.deadlines[i].date), m: calendar.component(.minute, from: data.deadlines[i].date)))
            data.deadlines[i].date = calendar.date(bySettingHour: parts.h, minute: parts.m, second: 0, of: day) ?? day
            if parsed.time != nil { data.deadlines[i].isDateOnly = false }
            let d = data.deadlines[i]
            return ParsedQuickTask(title: d.title, date: d.date, time: d.isDateOnly ? nil : LocalTime(parts.h, parts.m), category: d.category, isDeadline: true)
        }
    }

    static func complete(_ item: PlanItemRef, in data: inout AppData, now: Date) {
        switch item {
        case let .task(id): if let i = data.tasks.firstIndex(where: { $0.id == id }) { data.tasks[i].completedAt = now }
        case let .deadline(id): if let i = data.deadlines.firstIndex(where: { $0.id == id }) { data.deadlines[i].completedAt = now }
        }
    }

    static func delete(_ item: PlanItemRef, in data: inout AppData) {
        switch item {
        case let .task(id): data.tasks.removeAll { $0.id == id }
        case let .deadline(id): data.deadlines.removeAll { $0.id == id }
        }
    }

    /// A cloud or local-server brain's JSON answer, read into the same intents.
    /// A brain's answer: a reply plus any number of actions ("action": {…} or "actions": [{…}, …]).
    static func parseJSONAnswer(_ answer: String) -> (reply: String, intents: [MoiIntent]) {
        var trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") { trimmed = trimmed.replacingOccurrences(of: #"^```(?:json)?\s*|\s*```$"#, with: "", options: .regularExpression) }
        guard let bytes = trimmed.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let reply = object["reply"] as? String else { return (trimmed, []) }
        let actions = (object["actions"] as? [[String: Any]]) ?? (object["action"] as? [String: Any]).map { [$0] } ?? []
        return (reply, actions.compactMap { intent(kind: $0["kind"] as? String ?? $0["action"] as? String ?? "none", target: $0["target"] as? String ?? "", value: $0["value"] as? String ?? "") })
    }

    static func intent(kind: String, target: String, value: String) -> MoiIntent? {
        let ref: ItemRef = ["", "it", "that", "this"].contains(target.lowercased().trimmingCharacters(in: .whitespaces)) ? .last : .named(target)
        switch kind {
        case "add": return value.isEmpty ? nil : .add(value)
        case "move": return value.isEmpty ? nil : .move(ref, when: value)
        case "complete": return .complete(ref)
        case "delete": return .delete(ref)
        case "cleanup": return .cleanUp(value.isEmpty ? nil : value.lowercased())
        case "screenshot": return .screenshot
        case "focus": return .focus(value, minutes: nil)
        case "open": return value.isEmpty ? nil : intent(from: "open " + value) ?? .open(value, browser: nil, private: false)
        case "search": return value.isEmpty ? nil : .webSearch(value)
        case "photos": return value.isEmpty ? nil : .findPhotos(value)
        case "wallpaper": return value.isEmpty ? nil : .wallpaper(value)
        case "show_apps": return .showApps
        case "quit": return value.isEmpty ? nil : .quitApps(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, allExcept: nil)
        case "quit_all": return .quitApps([], allExcept: value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        case "hide_all": return .hideApps(allExcept: value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        case "dock_add": return value.isEmpty ? nil : .dockAdd(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        case "dock_remove": return value.isEmpty ? nil : .dockRemove(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        default: return nil
        }
    }

    /// Whether a model's suggested change is backed by what the person actually said. Small models
    /// invent actions ("how many answers do you have" → add "12"); those are dropped, not shown.
    static func grounded(_ intent: MoiIntent, in text: String) -> Bool {
        let t = text.lowercased()
        let asking = t.hasSuffix("?") || t.range(of: #"^(what|whats|what's|when|how|why|who|which|where|do|does|did|am|is|are|can you tell|tell me)\b"#, options: .regularExpression) != nil
        func words(_ s: String) -> Set<String> { Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 }) }
        switch intent {
        case let .add(phrase):
            guard !asking else { return false }
            let want = words(QuickAddParser.parse(phrase, now: Date(), calendar: .current).title)
            return !want.isEmpty && Double(want.intersection(words(text)).count) / Double(want.count) >= 0.5
        case .move, .when, .complete, .delete: return !asking
        default: return true
        }
    }

    /// Models to try for a free key, safest first. Previews often have no free quota (the 429 you'd
    /// get straight away), so only stable names: Google's "latest" alias, then versioned Flash models.
    static func freeModelCandidates(provider: String, available ids: [String]) -> [String] {
        let avoid = ["lite", "image", "tts", "embed", "audio", "live", "vision", "guard", "whisper", "orpheus", "speech", "transcribe", "rerank", "preview", "exp", "omni", "learnlm", "gemma", "nano", "lyria", "research"]
        let usable = ids.filter { id in !avoid.contains { id.lowercased().contains($0) } }
        var order: [String]
        if provider == "gemini" {
            let versioned = usable.compactMap { id -> (String, Double)? in
                guard let r = id.range(of: #"^gemini-(\d+(?:\.\d+)?)-flash$"#, options: .regularExpression), r.lowerBound == id.startIndex else { return nil }
                return Double(id.dropFirst("gemini-".count).dropLast("-flash".count)).map { (id, $0) }
            }.sorted { $0.1 > $1.1 }.map(\.0)
            order = ["gemini-flash-latest"] + versioned + ["gemini-2.5-flash"]
        } else if provider == "groq" {
            order = ["llama-3.3-70b-versatile", "openai/gpt-oss-120b", "openai/gpt-oss-20b", "llama-3.1-8b-instant"] + usable
        } else if provider == "openrouter" {
            // Only ":free" models, so a key with credit on it is never charged by moi.
            order = ["meta-llama/llama-3.3-70b-instruct:free", "openai/gpt-oss-120b:free", "deepseek/deepseek-chat-v3-0324:free", "qwen/qwen3-235b-a22b:free", "mistralai/mistral-small-3.2-24b-instruct:free"] + usable.filter { $0.hasSuffix(":free") }
        } else if provider == "nvidia" {
            order = ["meta/llama-3.3-70b-instruct", "nvidia/llama-3.3-nemotron-super-49b-v1.5", "nvidia/llama-3.3-nemotron-super-49b-v1", "qwen/qwen3-235b-a22b", "meta/llama-3.1-70b-instruct"] + usable.filter { $0.contains("instruct") }
        } else if provider == "mistral" {
            order = ["mistral-small-latest", "mistral-medium-latest", "open-mistral-nemo"]
        } else { order = usable }
        var seen = Set<String>()
        return order.filter { ids.contains($0) && seen.insert($0).inserted }.prefix(5).map { $0 }
    }
}

