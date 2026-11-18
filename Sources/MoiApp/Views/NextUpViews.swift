import AppKit
import SwiftUI

/// Legacy call sites ask for a mood; they all render the one moi character now.
struct MoiFace: View {
    enum Mood { case calm, happy, alert, sleepy }
    var mood: Mood = .calm
    var size: CGFloat = 20
    var blink = false

    var body: some View {
        MoiCharacter(state: state, size: size, pose: .peek, blink: blink)
    }

    private var state: MoiCharacterState {
        switch mood {
        case .calm: .idle
        case .happy: .happy
        case .alert: .attention
        case .sleepy: .sleeping
        }
    }

    /// Moi's mood for a list of next-up items: happy when clear, alert when something is due today.
    static func mood(for items: [NextUpItem], quietHours: Bool = false) -> Mood {
        guard let top = items.first else { return quietHours ? .sleepy : .happy }
        return top.urgency >= .today ? .alert : .calm
    }
}

/// One checkable next thing. The same row appears in Today, the menu bar, and Moi Pocket,
/// so something can be ticked off wherever you happen to be.
struct NextUpRow: View {
    @EnvironmentObject var store: AppStore
    let item: NextUpItem
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Button { store.complete(item.target) } label: {
                Image(systemName: "circle").font(compact ? .body : .title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.urgency >= .today ? Color.orange : Color.secondary)
            .help(item.target.isSuggestion ? "Done — Moi will lay out the rest of the plan" : "Mark done")
            .accessibilityLabel("Mark \(item.title) done")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).fontWeight(.medium).lineLimit(1)
                Text(detailLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let deadlineID = item.deadlineID {
                Button { store.openPlan(for: deadlineID) } label: { Image(systemName: "list.bullet.rectangle") }
                    .buttonStyle(.borderless)
                    .help("Open the plan")
                    .accessibilityLabel("Open plan for \(item.detail)")
            }
        }
        .font(compact ? .callout : .body)
    }

    private var detailLine: String {
        var parts = [item.detail]
        if let minutes = item.minutes { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}

/// The countdown as a small pill, colored by urgency, so the reminder survives any truncation.
struct CountdownPill: View {
    let item: NextUpItem

    var body: some View {
        if let countdown = item.countdown {
            Text(countdown)
                .font(.caption2.weight(.bold)).monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(color.opacity(0.16), in: Capsule())
                .fixedSize()
        }
    }

    private var color: Color {
        switch item.urgency {
        case .overdue, .today: .orange
        case .soon: MoiStyle.accent
        case .later: .secondary
        }
    }
}

extension NextUpItem.Target {
    var isSuggestion: Bool { if case .suggestedStep = self { true } else { false } }
}

/// A deadline's plan: its steps, what good looks like, and a hand-off to Claude for deeper research.
struct DeadlinePlanView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let deadlineID: UUID
    @State private var newStep = ""
    @State private var copied = false

    var body: some View {
        Group {
            if let deadline = store.data.deadlines.first(where: { $0.id == deadlineID }) {
                content(deadline)
            } else {
                VStack(spacing: 16) {
                    Text("This deadline no longer exists.").foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }.padding(40)
            }
        }
        .frame(width: 640, height: 700)
        .background(MoiStyle.background)
        .preferredColorScheme(.dark)
    }

    private func content(_ deadline: Deadline) -> some View {
        let playbook = DeadlinePlaybook.match(deadline.title)
        let steps = NextUpEngine.steps(for: deadline, in: store.data)
        let days = daysLeft(deadline)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CategoryPill(category: deadline.category)
                        if deadline.priority >= .high { Text(deadline.priority.rawValue.capitalized).font(MoiType.ui(11, weight: 600)).foregroundStyle(.orange) }
                    }
                    Text(deadline.title).font(.title2.bold()).lineLimit(2)
                    Text("Due \(deadline.date.formattedDate(in: store.calendar.timeZone, includeTime: !deadline.isDateOnly)) · \(ReminderVoice.countdownPhrase(days: days))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MoiFace(mood: deadline.completedAt != nil ? .happy : days <= 1 ? .alert : .calm, size: 48)
            }
            .padding(24)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    stepsSection(deadline, playbook: playbook, steps: steps, days: days)
                    guidanceSection(playbook)
                    researchSection(deadline, playbook: playbook, steps: steps)
                }
                .padding(24)
            }

            Divider()
            HStack {
                Button(deadline.completedAt == nil ? "Mark deadline done" : "Reopen deadline") {
                    if deadline.completedAt == nil { store.complete(.deadline(deadline.id)) } else { store.setDeadline(deadline.id, completed: false) }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func stepsSection(_ deadline: Deadline, playbook: DeadlinePlaybook, steps: [TaskItem], days: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Steps").font(MoiType.display(15, weight: 640))
                Spacer()
                if !steps.isEmpty { Text("\(steps.filter(\.isCompleted).count) of \(steps.count) done").font(.caption).foregroundStyle(.secondary) }
            }
            if steps.isEmpty {
                let preview = DeadlinePlan.tasks(for: deadline, steps: playbook.steps, now: Date(), calendar: store.calendar)
                Text(days > 1 ? "Here's a plan spread across the \(days) days you have. Each step is small on purpose." : "Not much time — here's the shortest path.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(preview) { step in
                    HStack(spacing: 10) {
                        Text(dayLabel(step.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                        Text(step.title)
                        Spacer()
                        Text("\(step.durationMinutes ?? 30) min").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { store.adoptPlan(forDeadline: deadline.id) } label: { Label("Use this plan", systemImage: "checklist") }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            } else {
                ForEach(steps) { step in
                    HStack(spacing: 10) {
                        Button { store.setTask(step.id, completed: !step.isCompleted); if !step.isCompleted { MoiSoundController.shared.play(.success, settings: store.data.settings) } } label: {
                            Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(step.isCompleted ? .green : .secondary)
                        Text(dayLabel(step.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                        Text(step.title).strikethrough(step.isCompleted).foregroundStyle(step.isCompleted ? .secondary : .primary)
                        Spacer()
                        if let minutes = step.durationMinutes { Text("\(minutes) min").font(.caption).foregroundStyle(.secondary) }
                        Button { store.update { $0.tasks.removeAll { $0.id == step.id } } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).foregroundStyle(.tertiary).help("Remove step")
                    }
                }
            }
            HStack {
                TextField("Add your own step…", text: $newStep).textFieldStyle(.roundedBorder).onSubmit { addStep(deadline) }
                Button("Add") { addStep(deadline) }.disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func guidanceSection(_ playbook: DeadlinePlaybook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(playbook.heading).font(MoiType.display(15, weight: 640))
            ForEach(playbook.guidance, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(MoiStyle.accent).frame(width: 5, height: 5).offset(y: -2)
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }

    private func researchSection(_ deadline: Deadline, playbook: DeadlinePlaybook, steps: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Want more depth?").font(MoiType.display(15, weight: 640))
            Text("Moi writes a research brief for Claude: what an excellent \(playbook.noun) looks like, a plan for the time you have, mistakes to avoid, and examples.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { research(deadline, steps: steps) } label: { Label("Research with Claude", systemImage: "sparkle.magnifyingglass") }
                    .buttonStyle(.bordered)
                if copied { Text("Prompt copied — paste it if Claude opens empty.").font(.caption).foregroundStyle(.secondary) }
            }
            if store.data.settings.researchContext.isEmpty {
                Text("Tip: add a line about yourself in Settings → Plans & research to make the brief specific.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: MoiStyle.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MoiStyle.corner).stroke(MoiStyle.border, lineWidth: 1))
    }

    private func research(_ deadline: Deadline, steps: [TaskItem]) {
        let project = deadline.projectID.flatMap { id in store.data.projects.first { $0.id == id } }
        let prompt = ResearchPrompt.make(deadline: deadline, project: project, steps: steps, aboutMe: store.data.settings.researchContext, now: Date(), calendar: store.calendar)
        let review = NSAlert()
        review.messageText = "Copy research brief to clipboard?"
        review.informativeText = "Review the full brief below. Copying makes it available to other clipboard apps. moi opens Claude without sending the brief; paste and send only if you choose."
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
        text.string = prompt; text.isEditable = false
        let scroll = NSScrollView(frame: text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true
        review.accessoryView = scroll
        review.addButton(withTitle: "Copy & Open Claude"); review.addButton(withTitle: "Cancel")
        guard review.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        NSWorkspace.shared.open(URL(string: "https://claude.ai/new")!)
    }

    private func addStep(_ deadline: Deadline) {
        store.addStep(newStep, toDeadline: deadline.id)
        newStep = ""
    }

    private func daysLeft(_ deadline: Deadline) -> Int {
        store.calendar.dateComponents([.day], from: store.calendar.startOfDay(for: store.now), to: store.calendar.startOfDay(for: deadline.date)).day ?? 0
    }

    private func dayLabel(_ date: Date?) -> String {
        guard let date else { return "Anytime" }
        if store.calendar.isDateInToday(date) { return "Today" }
        if store.calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.timeZone = store.calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}
