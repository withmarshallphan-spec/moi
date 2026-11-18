import SwiftUI

/// For anyone who has moi already: what it can do, where it lives, and its keys in one place.
/// Tapping an example puts it in Ask moi, ready to send (nothing runs by itself).
struct GuideView: View {
    @EnvironmentObject private var workspace: MoiWorkspace
    private let examples: [(String, String, [String])] = [
        ("Your plan", "calendar", ["gym tomorrow 16:30", "move it to 5pm", "the essay is done", "what's tomorrow?"]),
        ("Photos", "photo.on.rectangle", ["sort my flower photos and my trips", "photos from my trip in Italy", "make a sunset photo my wallpaper"]),
        ("Your Mac", "macbook", ["quit everything except Safari", "remove Discord from my Dock", "open YouTube in a private window", "clean up my downloads"]),
        ("Focus", "timer", ["focus on the essay for 50 minutes", "wrap up my day"]),
    ]
    private let places: [(String, String, String)] = [
        ("rectangle.topthird.inset.filled", "The notch", "Rest your pointer on it for music. Click it for your day and newest downloads."),
        ("rectangle.bottomthird.inset.filled", "The Pocket · ⌃⌥H", "The sticky bar: ask or tell moi anything, from any app."),
        ("command", "⌘K · ⇧⌘N", "Ask moi, or add a task, from inside moi."),
        ("mic", "Talk · ⌃⌥V", "Tap the mic or hold the keys. Speech is recognised on this Mac."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Guide").font(MoiType.display(30, weight: 660))
                        Text("What moi can do, where to find it, and the keys it needs.").font(MoiType.ui(14)).foregroundStyle(MoiStyle.quiet)
                    }
                    Spacer()
                    Button("Replay the introduction") { UserDefaults.standard.set(0, forKey: "moi.onboardingStep"); workspace.onboarding = true }.buttonStyle(.moiGhost)
                }
                section("Things to say") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                        ForEach(examples, id: \.0) { title, symbol, lines in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(title, systemImage: symbol).font(MoiType.ui(13.5, weight: 640))
                                ForEach(lines, id: \.self) { line in
                                    Button { Intelligence.shared.draft = line; workspace.showMain(.intelligence) } label: {
                                        Text("“\(line)”").font(MoiType.ui(13)).frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10).padding(.vertical, 7)
                                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }.buttonStyle(.plain).help("Put this in Ask moi")
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
                            .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                section("moi's keys") {
                    MoiKeysGrid()
                    Text("Each is optional and only used when you ask. Change them any time in System Settings → Privacy & Security.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                }
                section("Where moi lives") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                        ForEach(places, id: \.1) { symbol, title, text in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: symbol).foregroundStyle(MoiStyle.accent).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) { Text(title).font(MoiType.ui(13.5, weight: 620)); Text(text).font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet) }
                                Spacer(minLength: 0)
                            }
                            .padding(12).background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                section("Good to know") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Say “undo” after anything moi changed: a plan edit, quit apps, the Dock, the wallpaper.")
                        Text("• moi never deletes files or photos by itself. Albums leave photos untouched; files can always be put back.")
                        Text("• With a free Gemini or Groq key (Settings → Brain & voice), moi understands much more, including several things at once.")
                        Text("• Desktop widgets can't be changed by apps; macOS doesn't allow it. The Dock and wallpaper can.")
                    }.font(MoiType.ui(13))
                }
                Button("About moi · meet Marshall") { workspace.about = true }.buttonStyle(.moiSecondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 24)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(MoiType.display(17, weight: 640))
            content()
        }
    }
}
