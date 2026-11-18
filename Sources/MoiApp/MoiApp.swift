import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
#if DEBUG
        if let dir = ProcessInfo.processInfo.environment["MOI_EXPORT_CHARACTER"] { MoiCharacterSheet.export(to: URL(fileURLWithPath: dir)); exit(0) }
#endif
        NSApp.applicationIconImage = NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? URL(fileURLWithPath: "/")) ?? MoiIdentity.logo
        // The notch, shortcuts and reminders start even when no window opens (moi lives in the notch).
        DispatchQueue.main.async { MainActor.assumeIsolated { MoiApp.startup?() } }
    }
    func applicationWillTerminate(_ notification: Notification) {
        VoiceService.shared.cancel()
        Intelligence.shared.cancel()
        MoiSoundController.shared.stopAll()
        MoiHaloController.shared.hide(animated: false)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MoiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = MoiWorkspace.shared
    @StateObject private var store: AppStore
    @StateObject private var notch: NotchController
    @StateObject private var pocket: PocketController

    /// Starts everything that doesn't need a window, once: from launch, or from the window, whichever is first.
    static var startup: (() -> Void)?

    init() {
        UserDefaults.standard.register(defaults: ["moi.offline": true, "moi.artworkNetwork": true])
        MoiType.register()
        let store = AppStore(), notch = NotchController(), pocket = PocketController(), workspace = MoiWorkspace.shared
        _store = StateObject(wrappedValue: store)
        _notch = StateObject(wrappedValue: notch)
        _pocket = StateObject(wrappedValue: pocket)
        var started = false
        Self.startup = {
            guard !started else { return }
            started = true
            workspace.configure(store: store)
            notch.configure(store: store)
            pocket.configure(store: store, notch: notch)
            NotificationService.shared.configure(store: store)
            if store.data.settings.notificationsEnabled { NotificationService.shared.reschedule(using: store.data) }
            if store.activeFocus != nil { SoftBlocker.shared.begin(store: store) }
        }
    }

    var body: some Scene {
        WindowGroup("moi") {
            RootView(notch: notch)
                .environmentObject(store)
                .environmentObject(workspace)
                .frame(minWidth: 960, minHeight: 600)
                .task { MoiApp.startup?() }
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About moi") { workspace.about = true; workspace.showMain() } }
            CommandGroup(replacing: .newItem) {} // one main window; moi isn't a document app
            CommandGroup(after: .newItem) {
                Button("Quick Add Task…") { store.quickAddPresented = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Ask moi…") { workspace.showCommand() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("moi Guide") { workspace.showMain(.guide) }
                Button("Meet moi (the introduction)") { UserDefaults.standard.set(0, forKey: "moi.onboardingStep"); workspace.onboarding = true }
            }
        }

        MenuBarExtra { MenuBarContent(notch: notch, pocket: pocket).environmentObject(store) } label: {
            Label(menuTitle, systemImage: store.activeFocus == nil ? "circle.dotted.circle" : "timer")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuTitle: String {
        switch ScheduleEngine.state(at: store.now, data: store.data, calendar: store.calendar) {
        case let .active(item, _): "\(item.title) · \(ScheduleEngine.remainingText(until: item.end, from: store.now))"
        case let .gap(_, next), let .beforeDay(next): next.map { "Free · \($0.title) \($0.start.formattedTime(in: store.calendar.timeZone))" } ?? "Free"
        case .afterDay: "Day complete"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var notch: NotchController
    @EnvironmentObject private var workspace: MoiWorkspace
    @State private var pageGuide: PageGuide?
    @ObservedObject private var tidy = TidyStore.shared
    private var currentGuide: PageGuide {
        PageGuide(section: store.selectedSection, mode: store.selectedSection == .clean ? tidy.tab.rawValue : store.selectedSection == .tasks ? workspace.planMode : store.selectedSection == .calendar ? "Calendar" : nil)
    }

    var body: some View {
        NavigationSplitView {
            MoiSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: MoiStyle.sidebarWidth, max: 260)
        } detail: {
            GeometryReader { geometry in
              Group {
                switch store.selectedSection {
                case .overview: WorkspaceOverview()
                case .intelligence: IntelligenceView()
                case .clean: TidyUpView()
                case .tasks, .deadlines: PlanView(tab: .list)
                case .calendar: PlanView(tab: .calendar)
                case .focus: FocusView()
                case .guide: GuideView()
                case .settings: WorkspaceSettingsView(notch: notch)
                }
            }
              .frame(width: geometry.size.width, height: geometry.size.height)
              .scrollContentBackground(.hidden) // lists and forms sit on moi's ink, not system grey
              .background(MoiStyle.background)
            }
        }
        .sheet(isPresented: $store.quickAddPresented) { QuickAddView().environmentObject(store) }
        .sheet(isPresented: $workspace.onboarding) { OnboardingView().environmentObject(store).environmentObject(workspace) }
        .sheet(isPresented: $workspace.notchEditor) { NotchEditorView(notch: notch).environmentObject(store) }
        .sheet(isPresented: $workspace.about) { AboutMOIView() }
        .sheet(item: $pageGuide) { guide in PageGuideView(guide: guide).environmentObject(store).environmentObject(workspace) }
        .toolbar { Button { pageGuide = currentGuide } label: { Label("Page guide", systemImage: "questionmark.circle") } }
        .sheet(isPresented: Binding(get: { store.planningDeadlineID != nil }, set: { if !$0 { store.planningDeadlineID = nil } })) {
            if let id = store.planningDeadlineID { DeadlinePlanView(deadlineID: id).environmentObject(store) }
        }
        .alert("Local data could not be saved", isPresented: Binding(get: { store.persistenceError != nil }, set: { if !$0 { store.persistenceError = nil } })) {
            Button("OK") { store.persistenceError = nil }
        } message: { Text(store.persistenceError ?? "Unknown error") }
        .background(MoiStyle.background)
        .font(MoiType.body)
        .tint(MoiStyle.accent)
        .preferredColorScheme(workspace.theme == "Light" ? .light : workspace.theme == "System" ? nil : .dark)
        .onOpenURL { url in
            guard url.scheme == "moi-development", url.host == "screen",
                  let section = SidebarSection.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "-") == url.lastPathComponent.lowercased() }) else { return }
            workspace.showMain(section)
        }
    }

}

/// moi's own sidebar: moi and your name at the top, sections separated by space instead of
/// labels, small understated type, and a persimmon mark on the current page.
struct MoiSidebar: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var intelligence = Intelligence.shared
    /// Plan holds tasks, deadlines and the calendar. Ask moi only shows when moi has a brain.
    private var sections: [SidebarSection] {
        [.overview, .tasks, .focus, .clean] + (intelligence.provider.kind == .none ? [] : [.intelligence])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    MoiLogo(size: 22)
                    Text(MoiVoice.name.isEmpty ? store.now.formatted(.dateTime.weekday(.wide).day().month()) : "with \(MoiVoice.name)").font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet).lineLimit(1)
                }
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) { ForEach(sections) { SidebarRow(section: $0) } }
                    VStack(alignment: .leading, spacing: 1) { SidebarRow(section: .guide); SidebarRow(section: .settings) }
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }
        }
        .background(MoiStyle.background)
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var store: AppStore
    let section: SidebarSection
    @State private var hovering = false
    var body: some View {
        let selected = store.selectedSection == section || (section == .tasks && [.deadlines, .calendar].contains(store.selectedSection))
        Button { store.selectedSection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol).font(.system(size: 12.5, weight: .medium)).frame(width: 18)
                    .foregroundStyle(selected ? MoiStyle.accent : MoiStyle.quiet)
                Text(section.title).font(MoiType.ui(13.5, weight: selected ? 620 : 470))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10).padding(.vertical, 6.5)
            .background(selected ? MoiStyle.accent.opacity(0.13) : hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .offset(x: hovering && !selected ? 2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var notch: NotchController
    @ObservedObject var pocket: PocketController
    @State private var draft = ""

    var body: some View {
        let items = NextUpEngine.items(data: store.data, now: store.now, calendar: store.calendar, limit: 5)
        VStack(alignment: .leading, spacing: 12) {
            CurrentBlockCard(compact: true)
            Divider()
            HStack(spacing: 8) {
                MoiFace(mood: MoiFace.mood(for: items), size: 20)
                Text("Up next").font(MoiType.display(14, weight: 650))
                Spacer()
                Text("Tick things off right here").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(items) { NextUpRow(item: $0, compact: true) }
            if items.isEmpty {
                Text("Nothing pressing. Enjoy it.").font(.callout).foregroundStyle(.secondary)
            }
            TextField("Add something — try “essay due fri”", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.quickAdd(draft); draft = "" }
            Divider()
            HStack {
                Button("Pocket") { pocket.toggle() }
                Button("Notch") { notch.toggleExpanded() }
                Spacer()
                if store.activeFocus == nil {
                    Button("Focus 25") { store.startFocus(title: items.first?.title ?? "Focus", durationMinutes: 25) }
                } else { Button("End Focus") { store.endFocus() } }
                Button("Open Moi") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                }
            }
            .controlSize(.small)
        }
        .padding().frame(width: 380)
        .background(MoiStyle.background)
        .tint(MoiStyle.accent)
        .preferredColorScheme(.dark)
    }
}

struct QuickAddView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Quick Add").font(.title2.bold())
            TextField("Finish the storyboard tomorrow 10:45", text: $text)
                .textFieldStyle(.roundedBorder).onSubmit(add)
            Text("Understands today, tomorrow, weekdays, “in 3 days”, “oct 3”, and 24-hour times. Add “due” to make it a deadline with countdown reminders — “portfolio v2 due oct 15”.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add Task", action: add).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 520)
    }
    private func add() { store.quickAdd(text); dismiss() }
}
