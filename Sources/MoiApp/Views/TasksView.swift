import SwiftUI

/// Tasks, deadlines and the calendar in one place. One box adds anything ("gym tomorrow 16:30",
/// "essay due fri"); the list puts tasks and deadlines on the same timeline.
struct PlanView: View {
    enum Tab: String, CaseIterable { case list = "List", calendar = "Calendar" }
    @EnvironmentObject var store: AppStore
    @State var tab: Tab
    @State private var add = ""
    @State private var added = ""
    @State private var editorPresented = false
    @EnvironmentObject private var workspace: MoiWorkspace

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                PageTitle(title: "Plan", line: "Tasks, deadlines and your calendar, together.")
                Spacer()
                MoiSegmented(options: Tab.allCases, title: \.rawValue, selection: $tab)
                Button { editorPresented = true } label: { Label("New", systemImage: "plus") }.buttonStyle(.moiPrimary).help("Add with a form, with every option")
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle").foregroundStyle(MoiStyle.quiet)
                    TextField("Add anything: “gym tomorrow 16:30”, “essay due fri”, “call mum”", text: $add).textFieldStyle(.plain).font(MoiType.ui(14.5))
                        .onSubmit {
                            guard let parsed = store.quickAdd(add) else { return }
                            added = "Added " + MoiCommand.describe(parsed, now: Date(), calendar: store.calendar) + "."
                            add = ""
                        }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MoiStyle.border))
                if !added.isEmpty { Text(added).font(MoiType.small).foregroundStyle(MoiStyle.mint) }
            }
            .padding(.horizontal, 28).padding(.bottom, 8)
            switch tab {
            case .list: TasksView()
            case .calendar: CalendarView(embedded: true)
            }
        }
        .sheet(isPresented: $editorPresented) { TaskEditor().environmentObject(store) }
        .onAppear { workspace.planMode = tab.rawValue }
        .onChange(of: tab) { _, value in workspace.planMode = value.rawValue }
    }
}

/// A task or a deadline on the plan's timeline.
private enum PlanEntry: Identifiable {
    case task(TaskItem), deadline(Deadline)
    var id: UUID { switch self { case let .task(t): t.id; case let .deadline(d): d.id } }
    var date: Date? { switch self { case let .task(t): t.date; case let .deadline(d): d.date } }
    var done: Bool { switch self { case let .task(t): t.isCompleted; case let .deadline(d): d.completedAt != nil } }
    var title: String { switch self { case let .task(t): t.title; case let .deadline(d): d.title } }
}

struct TasksView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var showCompleted = false
    @State private var editingReminder: Deadline?
    @State private var editingTask: TaskItem?

    private var entries: [PlanEntry] {
        (store.data.tasks.map(PlanEntry.task) + store.data.deadlines.map(PlanEntry.deadline))
            .filter { (showCompleted || !$0.done) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
            .sorted { ($0.date ?? .distantFuture, $0.title) < ($1.date ?? .distantFuture, $1.title) }
    }
    private var groups: [(String, [PlanEntry])] {
        let cal = store.calendar
        let today = cal.startOfDay(for: store.now), tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let open = entries.filter { !$0.done }
        func day(_ e: PlanEntry) -> Date? { e.date.map { cal.startOfDay(for: $0) } }
        let result: [(String, [PlanEntry])] = [
            ("Overdue", open.filter { day($0).map { $0 < today } ?? false }),
            ("Today", open.filter { day($0) == today }),
            ("Tomorrow", open.filter { day($0) == tomorrow }),
            ("Later", open.filter { day($0).map { $0 > tomorrow } ?? false }),
            ("Whenever", open.filter { $0.date == nil }),
            ("Done", showCompleted ? entries.filter(\.done) : []),
        ]
        return result.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(MoiStyle.quiet)
                    TextField("Find", text: $search).textFieldStyle(.plain).font(MoiType.ui(13)).frame(width: 140)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(MoiStyle.surface, in: Capsule()).overlay(Capsule().stroke(MoiStyle.border))
                Button { withAnimation(.easeOut(duration: 0.2)) { showCompleted.toggle() } } label: {
                    Label(showCompleted ? "Showing done" : "Show done", systemImage: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(MoiType.ui(12.5, weight: 580)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(showCompleted ? MoiStyle.accent.opacity(0.16) : MoiStyle.surface, in: Capsule()).overlay(Capsule().stroke(MoiStyle.border))
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 28).padding(.vertical, 10)
            if groups.isEmpty {
                VStack(spacing: 14) {
                    MoiCharacter(state: .happy, size: 90, sticker: true)
                    Text(search.isEmpty ? MoiVoice.noTasks : "Nothing matches “\(search)”.").font(MoiType.display(20, weight: 640))
                    if search.isEmpty { Text("Type in the box above, like “gym tomorrow 16:30”.").font(MoiType.ui(13.5)).foregroundStyle(MoiStyle.quiet) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(groups, id: \.0) { title, items in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(title).font(MoiType.display(18, weight: 650)).foregroundStyle(title == "Overdue" ? MoiStyle.coral : .primary)
                                    Text("\(items.count)").font(MoiType.ui(12, weight: 600)).foregroundStyle(MoiStyle.quiet)
                                }
                                ForEach(items) { entry in
                                    switch entry {
                                    case let .task(task): TaskCard(task: task, onDelete: confirmDelete) { editingTask = task }
                                    case let .deadline(deadline): DeadlineCard(deadline: deadline) { editingReminder = deadline }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .sheet(item: $editingReminder) { item in DeadlineReminderEditor(deadline: item).environmentObject(store) }
        .sheet(item: $editingTask) { item in TaskEditor(editing: item).environmentObject(store) }
    }
    private func confirmDelete(_ task: TaskItem) { let alert = NSAlert(); alert.messageText = "Delete this task?"; alert.informativeText = task.title; alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel"); if alert.runModal() == .alertFirstButtonReturn { store.update { $0.tasks.removeAll { $0.id == task.id } } } }
}

/// A deadline on the same timeline as tasks: a flag, the countdown, its plan progress, and Plan.
private struct DeadlineCard: View {
    @EnvironmentObject var store: AppStore
    let deadline: Deadline
    var reminders: () -> Void
    @State private var hovering = false
    var body: some View {
        let steps = NextUpEngine.steps(for: deadline, in: store.data)
        let done = deadline.completedAt != nil
        HStack(spacing: 14) {
            Button { store.setDeadline(deadline.id, completed: !done) } label: {
                Image(systemName: done ? "flag.fill" : "flag").font(.system(size: 14, weight: .semibold)).foregroundStyle(done ? MoiStyle.quiet : MoiStyle.butter).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).accessibilityLabel(done ? "Reopen \(deadline.title)" : "Mark \(deadline.title) done")
            VStack(alignment: .leading, spacing: 6) {
                Text(deadline.title).font(MoiType.ui(14.5, weight: 600)).strikethrough(done, color: MoiStyle.quiet)
                HStack(spacing: 8) {
                    CategoryPill(category: deadline.category)
                    Text("Due " + deadline.date.formattedDate(in: store.calendar.timeZone, includeTime: !deadline.isDateOnly)).font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet)
                    if !steps.isEmpty { Text("\(steps.filter(\.isCompleted).count) of \(steps.count) steps").font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet) }
                    if deadline.needsVerification { Label("Check the date", systemImage: "exclamationmark.triangle").font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.butter) }
                }
            }
            Spacer()
            Text(DeadlineEngine.countdown(to: deadline, now: store.now, calendar: store.calendar)).font(MoiType.ui(13, weight: 650)).monospacedDigit()
            Button(steps.isEmpty ? "Plan it" : "Plan") { store.openPlan(for: deadline.id) }.buttonStyle(.moiGhost).help("Break it into steps")
            Menu {
                Button("Reminders…", action: reminders)
                Button("Delete", role: .destructive) {
                    let alert = NSAlert(); alert.messageText = "Delete this deadline?"; alert.informativeText = deadline.title
                    alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { store.update { $0.deadlines.removeAll { $0.id == deadline.id } } }
                }
            } label: { Image(systemName: "ellipsis").foregroundStyle(MoiStyle.quiet) }
                .menuStyle(.borderlessButton).frame(width: 28).opacity(hovering ? 1 : 0.4)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(hovering ? MoiStyle.raisedSurface : MoiStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MoiStyle.butter.opacity(done ? 0 : 0.35)))
        .onHover { hovering = $0 }
    }
}

/// One task as a soft card: a round yellow check, the title, and small chips for what matters.
private struct TaskCard: View {
    @EnvironmentObject var store: AppStore
    let task: TaskItem
    var onDelete: (TaskItem) -> Void
    var onEdit: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        let today = store.calendar.startOfDay(for: store.now)
        let overdue = !task.isCompleted && (task.date.map { store.calendar.startOfDay(for: $0) < today } ?? false)
        HStack(spacing: 14) {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { store.toggleTask(task) } } label: {
                ZStack {
                    Circle().fill(task.isCompleted ? MoiStyle.butterFill : Color.clear)
                    Circle().stroke(task.isCompleted ? MoiStyle.accent : overdue ? MoiStyle.coral : MoiStyle.quiet.opacity(0.7), lineWidth: 2)
                    if task.isCompleted { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.white) }
                }.frame(width: 22, height: 22).scaleEffect(task.isCompleted ? 1.08 : 1)
            }
            .buttonStyle(.plain).accessibilityLabel(task.isCompleted ? "Mark \(task.title) not done" : "Mark \(task.title) done")
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).font(MoiType.ui(14.5, weight: 580)).strikethrough(task.isCompleted, color: MoiStyle.quiet).foregroundStyle(task.isCompleted ? MoiStyle.quiet : .primary)
                HStack(spacing: 6) {
                    CategoryPill(category: task.category)
                    if let date = task.date { chip(overdue ? "Overdue · \(date.formatted(.dateTime.month(.abbreviated).day()))" : store.calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), symbol: "calendar", color: overdue ? MoiStyle.coral : MoiStyle.quiet) }
                    if let time = task.startTime { chip(time.display, symbol: "clock", color: MoiStyle.quiet) }
                    if let deadline = task.deadlineID.flatMap({ id in store.data.deadlines.first { $0.id == id } }) { chip(deadline.title, symbol: "flag", color: MoiStyle.quiet) }
                }
            }
            Spacer()
            if task.priority >= .high { chip(task.priority.rawValue.capitalized, symbol: "exclamationmark", color: task.priority == .critical ? MoiStyle.coral : MoiStyle.butter) }
            if task.date == nil, !task.isCompleted { Button("Set a time", action: onEdit).buttonStyle(.moiGhost) }
            Menu { Button("Edit…", action: onEdit); Button("Delete", role: .destructive) { onDelete(task) } } label: { Image(systemName: "ellipsis").foregroundStyle(MoiStyle.quiet) }
                .menuStyle(.borderlessButton).frame(width: 28).opacity(hovering ? 1 : 0.4)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(hovering ? MoiStyle.raisedSurface : MoiStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(MoiType.ui(11.5, weight: 560)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.1), in: Capsule())
    }
}

/// Adds or edits a task: when it happens (day, start time, length), or make it a deadline with a countdown.
struct TaskEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var editing: TaskItem?
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDate = true
    @State private var date = Date()
    @State private var hasTime = false
    @State private var time = Date()
    @State private var duration = 60
    @State private var isDeadline = false
    @State private var due = Date()
    @State private var priority: Priority = .normal
    @State private var category: ItemCategory = .personal
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "New task" : "Edit task").font(MoiType.display(24, weight: 660))
            Form {
                TextField("Task", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                Toggle("This is a deadline (countdown and reminders)", isOn: $isDeadline)
                if isDeadline {
                    DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
                } else {
                    Toggle("On a day", isOn: $hasDate)
                    if hasDate { DatePicker("Day", selection: $date, displayedComponents: .date) }
                    Toggle("At a time", isOn: $hasTime)
                    if hasTime { DatePicker("Starts", selection: $time, displayedComponents: .hourAndMinute); Stepper("Takes about \(duration) min", value: $duration, in: 5...480, step: 5) }
                }
                Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Category", selection: $category) { ForEach(ItemCategory.options(in: store.data)) { Text($0.rawValue).tag($0) } }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.buttonStyle(.moiGhost); Button(editing == nil ? "Add it" : "Save") { save() }.buttonStyle(.moiPrimary).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(24).frame(width: 520)
        .onAppear(perform: load)
    }
    private func load() {
        guard let task = editing else { return }
        title = task.title; notes = task.notes; priority = task.priority; category = task.category
        hasDate = task.date != nil; date = task.date ?? Date()
        hasTime = task.startTime != nil; duration = task.durationMinutes ?? 60
        if let t = task.startTime { time = store.calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) ?? Date() }
        due = task.date.flatMap { day in task.startTime.flatMap { store.calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day) } ?? day } ?? Date()
    }
    private func save() {
        let components = store.calendar.dateComponents([.hour, .minute], from: time)
        let name = title.trimmingCharacters(in: .whitespaces)
        if isDeadline {
            let deadline = Deadline(title: name, date: due, isDateOnly: false, category: category, priority: priority >= .high ? priority : .high)
            store.update { data in
                if let id = editing?.id { data.tasks.removeAll { $0.id == id } }
                data.deadlines.append(deadline)
            }
        } else {
            var task = editing ?? TaskItem(title: name)
            task.title = name; task.notes = notes; task.priority = priority; task.category = category
            task.date = hasDate || hasTime ? store.calendar.startOfDay(for: hasDate ? date : Date()) : nil
            task.startTime = hasTime ? LocalTime(components.hour ?? 0, components.minute ?? 0) : nil
            task.durationMinutes = hasTime ? duration : nil
            store.update { data in
                if let i = data.tasks.firstIndex(where: { $0.id == task.id }) { data.tasks[i] = task } else { data.tasks.append(task) }
            }
        }
        dismiss()
    }
}
