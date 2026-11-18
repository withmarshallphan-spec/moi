import Foundation

struct PlaybookStep: Hashable {
    let title: String
    let minutes: Int
}

/// What a kind of deadline asks for, and a plan of small steps to get there.
///
/// The point is to answer "I don't even know what this should have" without a network
/// call: every deadline gets sensible guidance and a first step the moment it exists.
/// Matching is by keywords in the title, most specific playbook first.
struct DeadlinePlaybook: Hashable {
    let id: String
    let keywords: [String]
    /// Section heading for the guidance, e.g. "What a strong portfolio has".
    let heading: String
    /// What the thing is, for the research prompt: "application portfolio".
    let noun: String
    let guidance: [String]
    let steps: [PlaybookStep]

    static func match(_ title: String) -> DeadlinePlaybook {
        let lower = title.lowercased()
        return library.first { playbook in playbook.keywords.contains { lower.contains($0) } } ?? general
    }

    /// Ordered from most to least specific: "SAT score / retake decision" is a decision,
    /// not a practice test, and "Official SAT" is test day, not a mock.
    static let library: [DeadlinePlaybook] = [
        DeadlinePlaybook(
            id: "decision",
            keywords: ["decision", "decide", "choose", "selection", "pick "],
            heading: "Making the call",
            noun: "decision",
            guidance: [
                "Write the question down in one line, with the date you'll decide by.",
                "Limit it to the 2–4 real options; more than that is research, not deciding.",
                "Pick the three criteria that matter most before you compare anything.",
                "A good-enough decision on time beats a perfect one late.",
                "Once decided, tell anyone who needs to know and add the next dates to Moi."
            ],
            steps: [
                .init(title: "Write down what you're deciding and by when", minutes: 10),
                .init(title: "List the real options", minutes: 15),
                .init(title: "Pick the 3 criteria that matter most", minutes: 15),
                .init(title: "Score each option against them", minutes: 20),
                .init(title: "Decide, and tell whoever needs to know", minutes: 10)
            ]
        ),
        DeadlinePlaybook(
            id: "test-day",
            keywords: ["official sat", "retake", "exam day", "test day"],
            heading: "Test-day checklist",
            noun: "test day",
            guidance: [
                "Complete Bluebook's exam setup on the device you'll use, a few days before — not the morning of.",
                "Have your admission ticket ready and bring an acceptable photo ID.",
                "Fully charge the device and pack the charger; update Bluebook and the operating system beforehand.",
                "Know where the test center is and when you need to arrive.",
                "The day before: light review only, then sleep. Cramming costs more than it gains."
            ],
            steps: [
                .init(title: "Complete Bluebook exam setup and get your admission ticket", minutes: 20),
                .init(title: "Check the test center location and arrival time", minutes: 10),
                .init(title: "Pack ID, charged device, charger, pencils, snacks", minutes: 15),
                .init(title: "Light review, then an early night", minutes: 30)
            ]
        ),
        DeadlinePlaybook(
            id: "practice-test",
            keywords: ["bluebook", "mock", "practice test", "rehearsal"],
            heading: "Getting the most from a practice test",
            noun: "full-length practice test and its review",
            guidance: [
                "Treat it like the real thing: same start time, timed sections, phone in another room.",
                "Use a full-length practice test in the Bluebook app so the format matches test day.",
                "The review is worth more than the score. Log every miss and why it happened.",
                "Sort misses into content gaps, careless errors, and timing — each needs a different fix.",
                "Turn your top three miss patterns into short drills for the next two weeks."
            ],
            steps: [
                .init(title: "Block the time and set up the test in Bluebook", minutes: 10),
                .init(title: "Take the full timed test", minutes: 150),
                .init(title: "Log every miss and why it happened", minutes: 45),
                .init(title: "Write your top 3 miss patterns and a drill for each", minutes: 20)
            ]
        ),
        DeadlinePlaybook(
            id: "portfolio",
            keywords: ["portfolio"],
            heading: "What a strong portfolio has",
            noun: "university application portfolio",
            guidance: [
                "Check each program's rules first: how many pieces, which file types and sizes, and where it's submitted (some use SlideRoom or their own portal).",
                "Quality over quantity — a tight set of your strongest work beats everything you've made. Stay within each program's limit.",
                "Open and close with your two best pieces.",
                "Give every piece a short caption: title, date, your role, tools, and one line of problem → what you did → result.",
                "Show process, not just polish: sketches, iterations, and what you changed and why.",
                "Show range, but with a clear through-line — what kind of thinker or maker you are.",
                "Include evidence of impact where you can: real clients, users, numbers, awards.",
                "Keep the layout clean and consistent, with your name on it."
            ],
            steps: [
                .init(title: "List every project you could include", minutes: 20),
                .init(title: "Pick your strongest pieces and put them in order", minutes: 30),
                .init(title: "Write a 1–2 line caption for each piece", minutes: 45),
                .init(title: "Gather good-quality images and files for each", minutes: 60),
                .init(title: "Assemble the first full version", minutes: 90),
                .init(title: "Get feedback from one person you trust", minutes: 30),
                .init(title: "Fix the top 3 issues and lock this version", minutes: 60)
            ]
        ),
        DeadlinePlaybook(
            id: "essay",
            keywords: ["essay", "short-answer", "short answer", "personal statement", "supplement"],
            heading: "What makes an essay work",
            noun: "application essay",
            guidance: [
                "Answer the actual prompt — reread it and underline what it's really asking.",
                "One specific story or idea beats a list of achievements.",
                "The reader should learn something about how you think that isn't anywhere else in your application.",
                "Concrete details (a moment, a place, something someone said) make it yours.",
                "End on reflection — what changed, what you'd do next — not a summary.",
                "Respect the word limit. The Common App personal essay is capped at 650 words.",
                "Read it aloud before you call it done."
            ],
            steps: [
                .init(title: "Reread the prompt and brainstorm 5 possible stories", minutes: 20),
                .init(title: "Pick one and outline it", minutes: 20),
                .init(title: "Write a rough first draft — no editing", minutes: 60),
                .init(title: "Revise for story and structure", minutes: 45),
                .init(title: "Get one reader's feedback", minutes: 20),
                .init(title: "Cut to the word limit and polish", minutes: 30),
                .init(title: "Proofread aloud and finalize", minutes: 15)
            ]
        ),
        DeadlinePlaybook(
            id: "peer-review",
            keywords: ["peer review"],
            heading: "Good peer reviews",
            noun: "competition peer review",
            guidance: [
                "Read the rubric before your first review so every score means the same thing.",
                "Be specific: one real strength and one concrete improvement for each entry.",
                "Spread reviews over a few days instead of one tired marathon.",
                "Double-check that every review actually submitted."
            ],
            steps: [
                .init(title: "Read the review rubric and instructions", minutes: 15),
                .init(title: "Do the first batch of reviews", minutes: 45),
                .init(title: "Finish the remaining reviews", minutes: 45),
                .init(title: "Confirm everything submitted", minutes: 10)
            ]
        ),
        DeadlinePlaybook(
            id: "registration",
            keywords: ["registration", "register", "sign up", "signup"],
            heading: "Before you register",
            noun: "competition registration",
            guidance: [
                "Confirm eligibility first: age or grade, team size, and location rules.",
                "Gather what the form needs up front: school details, teammate info, any fee or ID.",
                "For team events, lock your teammates before the form, not after.",
                "Save the confirmation and add every next date to Moi straight away."
            ],
            steps: [
                .init(title: "Check eligibility and the rules", minutes: 15),
                .init(title: "Confirm teammates, if it's a team event", minutes: 20),
                .init(title: "Fill out and submit the registration", minutes: 20),
                .init(title: "Save the confirmation and add the next dates", minutes: 10)
            ]
        ),
        DeadlinePlaybook(
            id: "recommendation",
            keywords: ["recommendation", "reference letter"],
            heading: "Getting great recommendations",
            noun: "recommendation letter request",
            guidance: [
                "Ask early — several weeks before the deadline — and in person or with a personal note.",
                "Give each recommender a short brag sheet: your goals, what you did in their class or team, and 2–3 things you'd love them to mention.",
                "Make deadlines and the submission method unmissable.",
                "Follow up politely a week before, and thank them afterwards."
            ],
            steps: [
                .init(title: "List who you'll ask and why", minutes: 15),
                .init(title: "Ask each recommender", minutes: 20),
                .init(title: "Send each a brag sheet and the deadlines", minutes: 45),
                .init(title: "Follow up a week before", minutes: 10),
                .init(title: "Send thank-you notes", minutes: 15)
            ]
        ),
        DeadlinePlaybook(
            id: "university-list",
            keywords: ["university research", "college list", "shortlist", "school list"],
            heading: "Building a good list",
            noun: "university shortlist",
            guidance: [
                "Start from what you need: program, location, cost, size, and admission odds.",
                "Balance the list across reach, target, and likely schools.",
                "For each school, note deadlines, required essays, tests, and any portfolio.",
                "Take requirements from each university's official site — they change every year."
            ],
            steps: [
                .init(title: "Write your 5 must-haves", minutes: 15),
                .init(title: "Build a long list of schools", minutes: 45),
                .init(title: "Record deadlines and requirements for each", minutes: 60),
                .init(title: "Cut it to a balanced shortlist", minutes: 30)
            ]
        ),
        DeadlinePlaybook(
            id: "submission",
            keywords: ["deck", "pitch", "video", "submission", "submit", "official deadline", "final"],
            heading: "What judges look for",
            noun: "competition submission",
            guidance: [
                "Reread the official rules and judging rubric, and build to the rubric.",
                "Nail the one-sentence version: the problem, who has it, your solution, and why it wins.",
                "Lead with the problem and evidence it's real — numbers, quotes, research.",
                "Show, don't tell: a demo, prototype, visuals, or real data.",
                "Respect every limit exactly: length, slide count, file format, naming.",
                "Submit a day early. Portals get slow near deadlines."
            ],
            steps: [
                .init(title: "Reread the rules and rubric; list every requirement", minutes: 20),
                .init(title: "Write the one-sentence pitch and an outline", minutes: 30),
                .init(title: "Gather research, data, and visuals", minutes: 60),
                .init(title: "Build the first full draft", minutes: 90),
                .init(title: "Get feedback against the rubric", minutes: 30),
                .init(title: "Revise and check every requirement", minutes: 60),
                .init(title: "Submit early and save the confirmation", minutes: 15)
            ]
        ),
        DeadlinePlaybook(
            id: "kickoff",
            keywords: ["launch", "begins", "released", "opens", "kickoff"],
            heading: "When something launches",
            noun: "competition kickoff",
            guidance: [
                "Read everything that's released once, end to end, before planning.",
                "Write down every key date and add them to Moi.",
                "Decide what 'done' looks like and the very first step."
            ],
            steps: [
                .init(title: "Read the full brief and materials", minutes: 30),
                .init(title: "Add the key dates to Moi", minutes: 10),
                .init(title: "Write the plan and first step", minutes: 20)
            ]
        )
    ]

    static let general = DeadlinePlaybook(
        id: "general",
        keywords: [],
        heading: "Getting it done",
        noun: "deliverable",
        guidance: [
            "Define what 'done' looks like in one sentence.",
            "Find a first step that takes under 20 minutes, and do it today.",
            "Finish a rough version early, then improve it.",
            "Aim to finish a day before the real deadline."
        ],
        steps: [
            .init(title: "Write what 'done' looks like", minutes: 10),
            .init(title: "Gather what you need", minutes: 30),
            .init(title: "Make a rough first version", minutes: 60),
            .init(title: "Review and improve it", minutes: 45),
            .init(title: "Finish and hand it in a day early", minutes: 30)
        ]
    )
}

/// Spreads a playbook over the days left, so the plan fits the real calendar.
enum DeadlinePlan {
    /// The first step lands today and the last the day before the deadline (the due date
    /// itself stays as buffer). With no room, everything lands today.
    static func tasks(for deadline: Deadline, steps: [PlaybookStep], now: Date, calendar: Calendar) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: deadline.date)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: due) ?? due
        let lastDay = max(today, dayBefore)
        let span = calendar.dateComponents([.day], from: today, to: lastDay).day ?? 0
        return steps.enumerated().map { index, step in
            let offset = steps.count > 1 ? Int((Double(index) * Double(span) / Double(steps.count - 1)).rounded()) : 0
            return TaskItem(
                title: step.title,
                date: calendar.date(byAdding: .day, value: offset, to: today),
                durationMinutes: step.minutes,
                priority: deadline.priority >= .high ? .high : .normal,
                projectID: deadline.projectID,
                category: deadline.category,
                deadlineID: deadline.id
            )
        }
    }
}

/// A ready-to-send research brief, so "research this for me" is one click into Claude.
enum ResearchPrompt {
    static func make(deadline: Deadline, project: Project?, steps: [TaskItem], aboutMe: String, now: Date, calendar: Calendar) -> String {
        let playbook = DeadlinePlaybook.match(deadline.title)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline.date)).day ?? 0
        let when = days > 0 ? "\(days) day\(days == 1 ? "" : "s") from now" : days == 0 ? "today" : "\(-days) days ago"

        var lines = ["I'm working toward “\(deadline.title)”, due \(deadline.date.formattedDate(in: calendar.timeZone)) — \(when)."]
        let about = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty { lines.append("About me: \(about)") }
        if let project {
            lines.append("It's part of \(project.title).\(project.notes.isEmpty ? "" : " Notes: \(project.notes)")")
        }
        if !steps.isEmpty {
            let done = steps.filter(\.isCompleted).map(\.title)
            let open = steps.filter { !$0.isCompleted }.map(\.title)
            if !done.isEmpty { lines.append("Done so far: \(done.joined(separator: "; ")).") }
            if !open.isEmpty { lines.append("Still planned: \(open.joined(separator: "; ")).") }
        }
        lines.append("")
        lines.append("Please research this for me:")
        lines.append("1. What does an excellent \(playbook.noun) look like here? Be specific, and point to official requirements or sources where they exist.")
        lines.append("2. A step-by-step plan that fits the time I have, broken into 20–60 minute steps, starting with something I can do today.")
        lines.append("3. The most common mistakes to avoid.")
        lines.append("4. Two or three strong examples or resources worth looking at.")
        return lines.joined(separator: "\n")
    }

    /// claude.ai pre-fills a new conversation from `q`; callers also copy the prompt so it survives if it doesn't.
    static func claudeURL(for prompt: String) -> URL? {
        URL(string: "https://claude.ai/new")
    }
}
