import SwiftUI

struct PageGuide: Identifiable {
    let section: SidebarSection
    var mode: String? = nil
    var id: String { section.rawValue + (mode.map { "." + $0 } ?? "") }
    var title: String { section.title + (mode.map { " · " + $0 } ?? "") }
    var seenKey: String { "moi.pageGuide.v1." + id }
    /// Each page's first-visit walkthrough: what to do, with an example. Short, in moi's voice.
    var steps: [(String, String)] {
        if section == .clean, let mode {
            switch mode {
            case "Photos": return [("Say what you're looking for", "Things, places or years, even several at once: “flowers and my trips”, “dog 2023”, “trip in Italy”."),
                                  ("Pick what to keep", "Every photo moi finds is picked. Tap any you don't want."),
                                  ("Make albums or folders", "Albums go into Photos and never change your photos. Right-click any photo to make it your wallpaper.")]
            case "Open apps": return [("See what's open", "Every app on every desktop, with how many windows it has."),
                                     ("Pick, then quit or hide", "Apps with unsaved work will ask you to save first. moi never force-quits."),
                                     ("Changed your mind?", "“Reopen them” brings the apps back.")]
            case "Dock": return [("Pick apps to take out", "This only changes your Dock. The apps stay installed."),
                                ("Or add one", "“Add an app…” pins any app."),
                                ("There's always a way back", "“Go back to my old Dock” undoes everything.")]
            case "Files": return [("Choose a folder", "Desktop, Downloads, Documents, Pictures, or any folder you like."),
                                 ("See every file first", "Thumbnails for everything loose, with exact copies flagged."),
                                 ("Sort, or trash the ones you pick", "Sorting moves files into a dated folder. Trash only takes what you pick and never empties itself. Put back is under Earlier clean-ups.")]
            default: break
            }
        }
        if mode == "Calendar" { return [("Your week at a glance", "Tasks, deadlines and blocks, by day."),
                                       ("Tap anything to change it", "Time, length and reminders live in each item."),
                                       ("Or just ask", "“What's tomorrow?” in Ask moi.")] }
        return switch section {
        case .focus:
            [("Pick one thing", "What deserves your attention right now? “Essay”, “Inbox zero”, anything."),
             ("Pick how long", "25 minutes is a good start. Pause or stop any time."),
             ("moi keeps watch", "Open an app on your distraction list and moi will ask if you want to get back to it. Try a 5-minute session below.")]
        case .clean:
            [("Desktop", "Sorts loose files into folders and quits the apps you're not using, in one go. Try saying “clean up my desktop”."),
             ("Files, Photos, Open apps, Dock", "Each tab tidies one thing: a folder, your photos, what's running, or your Dock."),
             ("Nothing is lost", "moi shows you everything first, never deletes on its own, and Put back undoes any clean-up.")]
        case .tasks, .calendar, .deadlines:
            [("Add anything", "Type like you'd text a friend: “gym tomorrow 16:30”, “essay due fri”."),
             ("Today and tomorrow, sorted", "Overdue, today, tomorrow, later. Tick things off as you go."),
             ("Change it by asking", "“Move the dentist to 5pm”, “the essay is done”. Say “undo” if moi gets one wrong.")]
        case .intelligence:
            [("Just ask", "Plans, photos, apps, files: “clean up my desktop”, “find my flower photos”, “what's tomorrow?”."),
             ("Several things at once", "“Sort my trips and quit Spotify” works too."),
             ("Pick a brain", "Brain shows the ones that are ready and how much of today's quota is used. When one runs out, the next takes over.")]
        case .settings:
            [("Make it yours", "Colours, the notch, shortcuts and the Pocket."),
             ("Give moi a brain", "Paste a free key under Brain & voice. moi works out whose it is."),
             ("Your data stays yours", "Offline mode blocks every cloud request. Keys live in your Keychain.")]
        case .overview:
            [("Your day, first", "What's happening now and what's next."),
             ("Ask from here", "Type or tap the mic: “gym tomorrow 4pm”."),
             ("moi lives in the notch too", "Rest your pointer on it for music, click it for your day.")]
        case .guide:
            [("Things to say", "Tap any example and it's ready in Ask moi."),
             ("Keys", "Allow the permissions moi needs, all in one place."),
             ("Meet Marshall", "The person who made moi.")]
        }
    }
}

struct PageGuideView: View {
    let guide: PageGuide
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: MoiWorkspace
    @State private var step = 0
    @State private var focusTitle = ""
    @State private var result = ""
    private func finish() { UserDefaults.standard.set(true, forKey: guide.seenKey); dismiss() }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(guide.title).font(MoiType.display(24, weight: 650)); Spacer(); Button("Skip") { finish() }.buttonStyle(.moiGhost) }
            Text("Step \(step + 1) of \(guide.steps.count)").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            ProgressView(value: Double(step + 1), total: Double(guide.steps.count))
            Text(guide.steps[step].0).font(MoiType.display(20, weight: 630))
            Text(guide.steps[step].1).font(MoiType.body).fixedSize(horizontal: false, vertical: true)
            if step == guide.steps.count - 1 {
                if guide.section == .focus {
                    TextField("What will you focus on?", text: $focusTitle).textFieldStyle(.roundedBorder)
                    Button("Start a 5-minute session") {
                        store.startFocus(title: focusTitle.trimmingCharacters(in: .whitespacesAndNewlines), durationMinutes: 5)
                        result = store.persistenceError ?? "Started! Pause or stop it in Focus mode."
                    }.buttonStyle(.moiSecondary).disabled(focusTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isReadOnly || store.activeFocus != nil)
                    if store.activeFocus != nil { Text("You're already focusing. End that session first.").font(MoiType.small) }
                } else {
                    Button("Try it in Ask moi") {
                        Intelligence.shared.draft = guide.section == .clean ? "clean up my desktop" : "What's tomorrow?"
                        finish(); workspace.showMain(.intelligence)
                    }.buttonStyle(.moiSecondary)
                    Text("It's typed in for you; nothing happens until you press send.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                }
            }
            if !result.isEmpty { Text(result).font(MoiType.small) }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.moiGhost) }
                Spacer()
                Button(step == guide.steps.count - 1 ? "Done" : "Next") { if step == guide.steps.count - 1 { finish() } else { step += 1 } }.buttonStyle(.moiPrimary).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 580, height: 430).background(MoiStyle.background)
            .interactiveDismissDisabled()
    }
}

struct AboutMOIView: View {
    @Environment(\.dismiss) private var dismiss
    static let repo = URL(string: "https://github.com/withmarshallphan-spec/moi")!
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MoiCharacter(state: .happy, size: 64, sticker: true, essential: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("moi").font(MoiType.display(30, weight: 680))
                    Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")).font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.moiSecondary).keyboardShortcut(.defaultAction)
            }
            Text("Made by Marshall Phan, who thinks computers shouldn't feel like a hundred windows shouting at once. moi is free and open source, and it runs on your Mac.").font(MoiType.body).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Link(destination: Self.repo) { Label("Star moi on GitHub", systemImage: "star.fill") }
                Link(destination: Self.repo.appendingPathComponent("issues")) { Label("Report a bug or ask for a feature", systemImage: "ladybug") }
                Text("Liked it? Starring it on GitHub or telling a friend is the best thank-you.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
            .font(MoiType.ui(13.5, weight: 600))
        }.padding(28).frame(width: 520).background(MoiStyle.background)
    }
}
