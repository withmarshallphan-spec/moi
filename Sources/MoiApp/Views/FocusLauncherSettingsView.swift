import SwiftUI
import UserNotifications

struct FocusView: View {
    @EnvironmentObject var store: AppStore
    @State private var objective = ""
    @State private var duration = 50
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(title: "Focus mode", line: "Keeps distracting apps away for a while, so you can do one thing. Like Opal, built in and free.")
                if let session = store.activeFocus {
                    Card {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 20) {
                                Text(session.title).font(MoiType.display(28, weight: 650))
                                Text(focusRemaining(session, now: context.date)).font(.system(size: 58, weight: .medium, design: .rounded)).monospacedDigit()
                                ProgressView(value: progress(session, now: context.date)).tint(.accentColor).frame(maxWidth: 520)
                                HStack { Button("Complete") { store.endFocus() }.buttonStyle(.borderedProminent); Button(session.pausedAt == nil ? "Pause" : "Resume") { togglePause(session) }; Button("Extend 15 min") { extend(session) }; Button("End Focus", role: .destructive) { store.endFocus() } }
                                Text("\(session.distractionAttempts) distraction attempts · stored locally").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(34)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        step(1, "Say what you're doing", "and for how long. The notch shows the time left.")
                        step(2, "Open a distracting app?", "moi steps in and asks you to get back to it, or closes the app if you allow that below.")
                        step(3, "Time's up", "moi lets you know. Your sessions stay on this Mac.")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What are you working on?").font(MoiType.display(18, weight: 640))
                            TextField("e.g. Essay draft", text: $objective).textFieldStyle(.roundedBorder).font(MoiType.ui(14))
                            HStack(spacing: 8) {
                                ForEach([25, 50, 90], id: \.self) { minutes in
                                    Button("\(minutes) min") { duration = minutes }.buttonStyle(duration == minutes ? .moiPrimary : .moiGhost)
                                }
                                Stepper("\(duration) minutes", value: $duration, in: 5...240, step: 5).labelsHidden()
                                Text("\(duration) min").font(MoiType.ui(13)).foregroundStyle(MoiStyle.quiet)
                                Spacer()
                                Button("Start focusing") { store.startFocus(title: objective.isEmpty ? "Focus" : objective, durationMinutes: duration) }.buttonStyle(.moiPrimary)
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your distraction list").font(MoiType.display(18, weight: 640))
                        Text("While you focus, opening one of these makes moi step in. Remove one with ×, or add any app.").font(MoiType.ui(13)).foregroundStyle(MoiStyle.quiet)
                        FocusSetup()
                        if !store.data.settings.softBlockEnabled { Label("The list is switched off, so Focus is only a timer right now.", systemImage: "exclamationmark.circle").font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.butter) }
                        Text("moi can't block websites yet, only apps.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card { VStack(alignment: .leading, spacing: 10) { Text("Recent sessions").font(MoiType.label).foregroundStyle(.secondary); ForEach(store.data.focusSessions.suffix(5).reversed()) { item in HStack { Text(item.title).lineLimit(1); Spacer(); Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } }; if store.data.focusSessions.isEmpty { Text("No sessions yet").foregroundStyle(.secondary) } } }.frame(maxWidth: .infinity)
                }
            }.padding(24)
        }
    }
    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(MoiType.ui(13, weight: 700)).frame(width: 24, height: 24).background(MoiStyle.surface, in: Circle()).overlay(Circle().stroke(MoiStyle.border))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MoiType.ui(14, weight: 620))
                Text(detail).font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func focusRemaining(_ session: FocusSession, now: Date) -> String {
        let seconds = max(0, Int(session.plannedEnd.timeIntervalSince(session.pausedAt ?? now)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
    private func progress(_ session: FocusSession, now: Date) -> Double { min(1, max(0, ((session.pausedAt ?? now).timeIntervalSince(session.startedAt) - session.accumulatedPauseSeconds) / max(1, session.plannedEnd.timeIntervalSince(session.startedAt) - session.accumulatedPauseSeconds))) }
    private func togglePause(_ session: FocusSession) { store.update { data in guard let i = data.focusSessions.firstIndex(where: { $0.id == session.id }) else { return }; if let paused = data.focusSessions[i].pausedAt { data.focusSessions[i].plannedEnd = data.focusSessions[i].plannedEnd.addingTimeInterval(Date().timeIntervalSince(paused)); data.focusSessions[i].accumulatedPauseSeconds += Date().timeIntervalSince(paused); data.focusSessions[i].pausedAt = nil } else { data.focusSessions[i].pausedAt = Date() } } }
    private func extend(_ session: FocusSession) { store.update { data in if let i = data.focusSessions.firstIndex(where: { $0.id == session.id }) { data.focusSessions[i].plannedEnd = data.focusSessions[i].plannedEnd.addingTimeInterval(15 * 60) } } }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var notch: NotchController
    @State private var loginEnabled = LoginItemService.isEnabled
    @State private var loginError: String?
    @State private var editingBlock: ScheduleBlock?
    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable notifications", isOn: setting(\.notificationsEnabled))
                Toggle("Morning summary", isOn: setting(\.morningSummaryEnabled))
                TimeField(label: "Morning time", value: setting(\.morningSummaryTime))
                Toggle("Evening review", isOn: setting(\.eveningReviewEnabled))
                TimeField(label: "Evening time", value: setting(\.eveningReviewTime))
                TextField("Deadline reminder days", text: reminderList(days: true)).help("Comma-separated days before a deadline")
                TextField("Exact-time extras (minutes)", text: reminderList(days: false))
                Picker("Schedule block reminders", selection: setting(\.blockReminders)) {
                    ForEach(BlockReminderStyle.allCases) { Text($0.label).tag($0) }
                }
                Button("Request Notification Permission") { NotificationService.shared.requestPermission { _ in NotificationService.shared.reschedule(using: store.data) } }
                Text("Deadlines always come first: 30, 14, 7, 3 and 1 day before, plus the morning of (exact-time deadlines also get 3- and 1-hour reminders). Each reminder names the next small step and has Done, Remind me later, and Open plan buttons. Schedule blocks can't crowd deadlines out.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Sounds") {
                Toggle("Master Moi Sounds", isOn: setting(\.moiSoundsEnabled))
                Group {
                    Toggle("Summon Sound", isOn: setting(\.moiSummonSoundEnabled))
                    Toggle("Notification Sound", isOn: setting(\.moiNotificationSoundEnabled))
                    Toggle("Success Sound", isOn: setting(\.moiSuccessSoundEnabled))
                    Toggle("Attention Sound", isOn: setting(\.moiAttentionSoundEnabled))
                    Button("Send Test Notification") {
                        NotificationService.shared.sendIdentitySoundTest(settings: store.data.settings)
                    }
                }
                .disabled(!store.data.settings.moiSoundsEnabled)
                Text("Identity sounds are reserved for summons, reminders, meaningful completions, and items that need attention.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Plans & research") {
                TextField("About me", text: setting(\.researchContext), prompt: Text("e.g. High-school senior applying to design programs in the US and UK"))
                Text("Added to every “Research with Claude” brief so the answers fit you. Review before copying to the clipboard. Claude opens without receiving the brief; paste and send it yourself.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notch Glance") {
                NotchSettingsSection(notch: notch)
            }
            Section("Moi Presence") {
                Toggle("Glow around the screen while we talk", isOn: setting(\.moiHaloEnabled, syncHalo: true))
                Picker("Halo Intensity", selection: setting(\.moiHaloIntensity, syncHalo: true)) {
                    ForEach(MoiHaloIntensity.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("The click-through halo appears briefly with the notch glance and becomes static when Reduce Motion is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Schedule") {
                Picker("Timezone", selection: setting(\.timeZoneID)) { ForEach(Array(Set([TimeZone.current.identifier, store.data.settings.timeZoneID])).sorted(), id: \.self) { Text($0).tag($0) } }
                Toggle("Week starts Monday", isOn: setting(\.weekStartsMonday))
                ForEach(store.data.scheduleBlocks) { block in
                    HStack {
                        Image(systemName: block.category.symbol).foregroundStyle(block.category.color).frame(width: 22)
                        Text("\(block.startTime.display)–\(block.endTime.display)").monospacedDigit().frame(width: 105, alignment: .leading)
                        Text(block.title).lineLimit(1)
                        Spacer()
                        if !block.isEnabled { Text("Off").font(MoiType.ui(11, weight: 600)).foregroundStyle(.secondary) }
                        Button("Edit") { editingBlock = block }.controlSize(.small)
                    }
                }
                Button("Add recurring block") { editingBlock = ScheduleBlock(title: "New Block", startTime: LocalTime(9), endTime: LocalTime(10), category: .personal, recurrence: RecurringRule(weekdays: Set(1...7), startDate: store.calendar.startOfDay(for: Date()))) }
                Text("Calendar → Day offers occurrence, future-occurrence, and entire-series actions.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Focus & blocking") {
                Toggle("Soft blocker", isOn: setting(\.softBlockEnabled))
                Toggle("Attempt to quit blocked apps", isOn: setting(\.quitBlockedApps))
                TextField("Blocked websites (advisory, comma-separated)", text: Binding(get: { store.data.settings.blockedWebsites.joined(separator: ", ") }, set: { value in store.update { $0.settings.blockedWebsites = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } }))
                Text("Public macOS APIs do not provide system-wide website blocking to a normal app. Moi does not alter hosts files or claim Screen Time access.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch automatically when I log in", isOn: Binding(get: { loginEnabled }, set: { value in do { try LoginItemService.setEnabled(value); loginEnabled = value } catch { loginError = error.localizedDescription } }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Data") {
                HStack { Button("Export JSON Backup") { DataTransferService.exportJSON(data: store.data) }; Button("Import JSON Backup") { DataTransferService.importJSON(into: store) }; Button("Export CSV") { DataTransferService.exportCSV(data: store.data) } }
                Text("Productivity records are local. Optional artwork and provider requests use the network. JSON includes productivity and notes; module settings/indexes and credentials are separate.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(.horizontal, 16).navigationTitle("Settings")
            .sheet(item: $editingBlock) { block in ScheduleBlockEditor(block: block).environmentObject(store) }
    }
    private func setting<T>(_ path: WritableKeyPath<UserSettings, T>, syncHalo: Bool = false) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: path] }, set: { value in
            store.update { $0.settings[keyPath: path] = value }
            if syncHalo { MoiHaloController.shared.refreshSettings() }
        })
    }
    private func reminderList(days: Bool) -> Binding<String> {
        Binding(get: { let value = store.data.reminderDefaults ?? ReminderDefaults(); return (days ? value.deadlineDays : value.exactTimeExtraMinutes).map(String.init).joined(separator: ", ") }, set: { value in
            let parsed = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
            if !parsed.isEmpty { store.update { data in var defaults = data.reminderDefaults ?? ReminderDefaults(); if days { defaults.deadlineDays = parsed } else { defaults.exactTimeExtraMinutes = parsed }; data.reminderDefaults = defaults } }
        })
    }
}

struct ScheduleBlockEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var block: ScheduleBlock
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recurring Schedule Block").font(.title2.bold())
            Form {
                TextField("Title", text: $block.title)
                Picker("Category", selection: $block.category) { ForEach(ItemCategory.options(in: store.data)) { Text($0.rawValue).tag($0) } }
                Toggle("Enabled", isOn: $block.isEnabled)
                TimeField(label: "Start", value: $block.startTime)
                TimeField(label: "End", value: $block.endTime)
                LabeledContent("Repeats") {
                    HStack { ForEach(Array(1...7), id: \.self) { weekday in Button(store.calendar.veryShortWeekdaySymbols[weekday - 1]) { if block.recurrence.weekdays.contains(weekday) { block.recurrence.weekdays.remove(weekday) } else { block.recurrence.weekdays.insert(weekday) } }.buttonStyle(.bordered).tint(block.recurrence.weekdays.contains(weekday) ? .accentColor : .gray) } }
                }
                Toggle("Notify at start", isOn: $block.notificationRule.atStart)
                Toggle("Notify at end", isOn: $block.notificationRule.atEnd)
                TextField("Minutes before start", text: Binding(get: { block.notificationRule.minutesBefore.map(String.init).joined(separator: ", ") }, set: { block.notificationRule.minutesBefore = $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }))
                TextField("Minutes before end", text: Binding(get: { block.notificationRule.minutesBeforeEnd.map(String.init).joined(separator: ", ") }, set: { block.notificationRule.minutesBeforeEnd = $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }))
                DisclosureGroup("Workspace items") {
                    ForEach(store.data.launcherItems) { item in
                        Toggle(item.title, isOn: Binding(get: { block.workspaceItemIDs.contains(item.id) }, set: { enabled in if enabled { if !block.workspaceItemIDs.contains(item.id) { block.workspaceItemIDs.append(item.id) } } else { block.workspaceItemIDs.removeAll { $0 == item.id } } }))
                    }
                }
            }
            HStack {
                Button("Delete", role: .destructive) { confirmDelete() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { store.update { data in if let i = data.scheduleBlocks.firstIndex(where: { $0.id == block.id }) { data.scheduleBlocks[i] = block } else { data.scheduleBlocks.append(block) } }; dismiss() }.buttonStyle(.borderedProminent).disabled(block.title.isEmpty || block.recurrence.weekdays.isEmpty)
            }
        }.padding(24).frame(width: 620)
    }
    private func confirmDelete() { let alert = NSAlert(); alert.messageText = "Delete this schedule series?"; alert.informativeText = "Past completion records are preserved, but future occurrences will disappear."; alert.addButton(withTitle: "Delete Series"); alert.addButton(withTitle: "Cancel"); if alert.runModal() == .alertFirstButtonReturn { store.update { $0.scheduleBlocks.removeAll { $0.id == block.id } }; dismiss() } }
}

struct TimeField: View {
    let label: String
    @Binding var value: LocalTime
    var body: some View {
        HStack { Text(label); Spacer(); Stepper(value.display, value: $value.hour, in: 0...23); Stepper("\(value.minute)m", value: $value.minute, in: 0...59, step: 5) }.frame(maxWidth: 420)
    }
}

struct NotchSettingsSection: View {
    @ObservedObject var notch: NotchController
    @State private var panelEnabled = NotchPreferences().panelEnabled
    @State private var opensOnHover = NotchPreferences().opensOnHover
    @State private var shortcut = NotchPreferences().shortcut

    var body: some View {
        Button("Edit the notch…") { MoiWorkspace.shared.notchEditor = true }
        Toggle("Notch glance", isOn: $panelEnabled)
            .onChange(of: panelEnabled) { _, value in
                NotchPreferences().panelEnabled = value
                notch.setVisible(value)
            }
        Picker("Open it by", selection: $opensOnHover) {
            Text("Resting the pointer on the notch").tag(true)
            Text("Clicking the notch").tag(false)
        }
        .onChange(of: opensOnHover) { _, value in NotchPreferences().opensOnHover = value }
        Text("Only the notch itself counts — nothing beside or below it. Shows Spotify, what you're doing now, and the next thing to tick off. Move away to dismiss it; the shortcut pins it until you press it again.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Picker("Global shortcut", selection: $shortcut) {
            ForEach(NotchShortcut.allCases) { Text($0.label).tag($0) }
        }
        .onChange(of: shortcut) { _, value in
            NotchPreferences().shortcut = value
            notch.refreshHotKey()
        }
    }
}
