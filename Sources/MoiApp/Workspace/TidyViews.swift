import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Desktop clean-up: look first, then sort into folders or move chosen files to the Trash, and
/// put anything back. The state lives here so the companion can start a preview.
@MainActor
final class TidyStore: ObservableObject {
    static let shared = TidyStore()
    @Published var plan: DesktopTidy.Plan?
    @Published var chosen = Set<String>()
    /// Exact copies in the current preview, oldest first in each group.
    @Published private(set) var duplicates: [[String]] = []
    var extraCopies: Set<String> { Set(duplicates.flatMap { $0.dropFirst() }) }
    @Published private(set) var history: [DesktopTidy.Record]
    @Published var message = ""
    @Published var error: String?
    private let historyURL = MoiPaths.root.appendingPathComponent("tidy-history.json")
    enum Tab: String, CaseIterable { case screen = "Desktop", files = "Files", photos = "Photos", apps = "Open apps", dock = "Dock" }
    @Published var tab = Tab.files
    /// Which folder Files cleans: one of the usual places, or any folder you pick.
    struct Folder: Hashable {
        var url: URL
        var title: String { url.path == FileManager.default.homeDirectoryForCurrentUser.path ? "your home folder" : "your " + url.lastPathComponent }
        static func named(_ name: String) -> Folder { Folder(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name, isDirectory: true)) }
        static let presets = ["Desktop", "Downloads", "Documents", "Pictures"].map(named)
        init(url: URL) { self.url = url }
        /// "downloads", "home folder", … from what someone said.
        init(spoken: String) {
            let s = spoken.lowercased()
            if s.contains("home screen") { url = Folder.named("Desktop").url }
            else if s.hasPrefix("home") { url = FileManager.default.homeDirectoryForCurrentUser }
            else { url = (Folder.presets.first { s.hasPrefix($0.url.lastPathComponent.lowercased().prefix(5)) } ?? Folder.named("Desktop")).url }
        }
    }
    /// `MOI_TIDY_DESKTOP` points tests and screenshots at a synthetic folder instead of the real Desktop.
    @Published var folder = Folder(url: ProcessInfo.processInfo.environment["MOI_TIDY_DESKTOP"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true))

    private init() {
        history = (try? LocalStorage.load([DesktopTidy.Record].self, from: historyURL, default: [])) ?? []
    }

    /// Reading the Desktop is when macOS asks for Desktop access, so this only runs when asked.
    func preview() {
        error = nil; message = ""; chosen = []
        do {
            let plan = try DesktopTidy.plan(desktop: folder.url)
            self.plan = plan
            duplicates = DesktopTidy.duplicateGroups(plan.moves.map(\.from))
            if plan.moves.isEmpty { message = "\(folder.title.prefix(1).uppercased() + folder.title.dropFirst()) is already clear. Nothing loose to look at." }
        } catch {
            plan = nil
            self.error = "I couldn't look at \(folder.title). If macOS asked, allow moi to access that folder (System Settings → Privacy & Security → Files and Folders). \(error.localizedDescription)"
        }
    }

    /// Sorts every file still in the preview (not the ones just trashed) into the dated folder.
    func sortIntoFolders() {
        guard let plan, !plan.moves.isEmpty else { return }
        let (record, failures) = DesktopTidy.apply(plan)
        self.plan = nil; chosen = []
        if !record.moves.isEmpty { history.insert(record, at: 0); save() }
        message = record.moves.isEmpty ? "Nothing moved." : "Sorted \(count(record.moves.count)) into “\(URL(fileURLWithPath: record.folder).lastPathComponent)” in \(folder.title). Nothing was deleted."
        error = failures.isEmpty ? nil : Self.summary("Left in place: ", failures)
    }

    /// Only the files the person picked, after they confirm. Never empties the Trash.
    func trashChosen() {
        guard var plan, !chosen.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Move \(count(chosen.count)) to the Trash?"
        alert.informativeText = "They stay in the Trash until you empty it yourself. You can put them back from here (Earlier clean-ups) or from Finder."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let (record, failures) = DesktopTidy.trash(Array(chosen).sorted())
        if !record.moves.isEmpty { history.insert(record, at: 0); save() }
        let gone = Set(record.moves.map(\.from))
        plan.moves.removeAll { gone.contains($0.from) }
        duplicates = duplicates.map { $0.filter { !gone.contains($0) } }.filter { $0.count > 1 }
        self.plan = plan.moves.isEmpty ? nil : plan
        chosen = []
        message = "Moved \(count(record.moves.count)) to the Trash." + (plan.moves.isEmpty ? "" : " Sort the other \(plan.moves.count) into folders, or leave them.")
        error = failures.isEmpty ? nil : Self.summary("Couldn't move: ", failures)
    }

    /// Applies any move plan (also used by photo results) and keeps it in the history for Put back.
    func apply(_ plan: DesktopTidy.Plan) -> String {
        let (record, failures) = DesktopTidy.apply(plan)
        if !record.moves.isEmpty { history.insert(record, at: 0); save() }
        error = failures.isEmpty ? nil : Self.summary("Left in place: ", failures)
        return "Moved \(count(record.moves.count)) into “\(URL(fileURLWithPath: record.folder).lastPathComponent)”."
    }

    /// Keeps a clean-up done elsewhere (moi's on-screen tidy) in the history, so Put back works.
    func remember(_ record: DesktopTidy.Record, failures: [String]) {
        if !record.moves.isEmpty { history.insert(record, at: 0); save() }
        error = failures.isEmpty ? nil : Self.summary("Left in place: ", failures)
    }

    func undo(_ record: DesktopTidy.Record) {
        let (restored, failures) = DesktopTidy.undo(record)
        if let index = history.firstIndex(where: { $0.id == record.id }) { history[index].undone = failures.isEmpty; save() }
        message = "Put \(count(restored)) back where \(restored == 1 ? "it was" : "they were")."
        error = failures.isEmpty ? nil : Self.summary("Couldn't put back: ", failures) + (record.trashed == true ? ". You can also use Finder → Trash → Put Back." : "")
    }

    /// The first few problems in full, then a count, so a big clean-up can't fill the screen.
    static func summary(_ prefix: String, _ failures: [String]) -> String {
        prefix + failures.prefix(3).joined(separator: "; ") + (failures.count > 3 ? "; and \(failures.count - 3) more." : "")
    }

    private func count(_ n: Int) -> String { "\(n) \(n == 1 ? "file" : "files")" }

    private func save() {
        do { try LocalStorage.save(Array(history.prefix(50)), to: historyURL) }
        catch { self.error = "Done, but I couldn't save the history for putting things back: \(error.localizedDescription)" }
    }
}

struct TidyUpView: View {
    @ObservedObject private var tidy = TidyStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                PageTitle(title: "Clean up", line: "Review your files, photos, open apps and Dock before making changes.")
                Spacer()
                MoiSegmented(options: TidyStore.Tab.allCases, title: \.rawValue, selection: $tidy.tab)
            }
            .padding([.horizontal, .top], 24)
            switch tidy.tab {
            case .screen: ScreenTidyView()
            case .files: DesktopTidyView()
            case .photos: PhotoResultsView()
            case .apps: OpenAppsView()
            case .dock: DockView()
            }
        }
    }
}

struct DesktopTidyView: View {
    @ObservedObject private var tidy = TidyStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                folderPicker
                if let plan = tidy.plan, !plan.moves.isEmpty { preview(plan) }
                else { start }
                if !tidy.message.isEmpty { Label(tidy.message, systemImage: "checkmark.circle").font(MoiType.ui(13.5)).foregroundStyle(MoiStyle.mint) }
                ModuleMessage(text: tidy.error)
                if !tidy.history.isEmpty { history }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private var folderPicker: some View {
        HStack(spacing: 8) {
            ForEach(TidyStore.Folder.presets, id: \.self) { folder in
                Button(folder.url.lastPathComponent) { tidy.folder = folder; tidy.plan = nil; tidy.message = "" }.buttonStyle(tidy.folder == folder ? .moiPrimary : .moiGhost)
            }
            Button("Other folder…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url { tidy.folder = TidyStore.Folder(url: url); tidy.plan = nil; tidy.preview() }
            }.buttonStyle(.moiGhost)
        }
    }

    private var start: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "menubar.dock.rectangle").font(.system(size: 26, weight: .light)).foregroundStyle(MoiStyle.quiet).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean up \(tidy.folder.title)").font(MoiType.display(18, weight: 640))
                    Text("I'll show every loose file with a preview. Pick what you don't need and move it to the Trash, and/or sort the rest into one folder by kind. Folders, apps and anything still saving are left alone.").font(MoiType.ui(13)).foregroundStyle(MoiStyle.quiet).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Show me the files") { tidy.preview() }.buttonStyle(.moiPrimary)
            }
        }
    }

    private func preview(_ plan: DesktopTidy.Plan) -> some View {
        let groups = Dictionary(grouping: plan.moves) { URL(fileURLWithPath: $0.to).deletingLastPathComponent().lastPathComponent }
        return VStack(alignment: .leading, spacing: 16) {
            Card {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(plan.moves.count) loose \(plan.moves.count == 1 ? "file" : "files") in \(tidy.folder.title)").font(MoiType.display(18, weight: 640))
                        Text(tidy.chosen.isEmpty ? "Click files you don't need to pick them. Double-click to open one." : "\(tidy.chosen.count) picked for the Trash.").font(MoiType.ui(13)).foregroundStyle(MoiStyle.quiet)
                    }
                    Spacer()
                    if !tidy.extraCopies.isEmpty, !tidy.extraCopies.isSubset(of: tidy.chosen) {
                        Button("Pick \(tidy.extraCopies.count) extra \(tidy.extraCopies.count == 1 ? "copy" : "copies")") { tidy.chosen.formUnion(tidy.extraCopies) }
                            .buttonStyle(.moiGhost).help("Exact duplicates. Keeps the oldest of each and picks the rest")
                    }
                    Button("Cancel") { tidy.plan = nil; tidy.chosen = [] }.buttonStyle(.moiGhost).keyboardShortcut(.cancelAction)
                    if !tidy.chosen.isEmpty {
                        Button("Move \(tidy.chosen.count) to Trash") { tidy.trashChosen() }.buttonStyle(.moiGhost)
                    }
                    Button("Sort all into folders") { tidy.sortIntoFolders() }
                        .buttonStyle(.moiPrimary).disabled(!tidy.chosen.isEmpty)
                        .help(tidy.chosen.isEmpty ? "Into “\(plan.folder.lastPathComponent)” in \(tidy.folder.title), one folder per kind" : "Move the picked files to the Trash first, or unpick them")
                }
            }
            ForEach(DesktopTidy.Kind.allCases.filter { groups[$0.rawValue] != nil }, id: \.self) { kind in
                let moves = groups[kind.rawValue] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("\(kind.rawValue) · \(moves.count)", systemImage: kind.symbol).font(MoiType.ui(13.5, weight: 620))
                        Spacer()
                        let paths = Set(moves.map(\.from))
                        Button(paths.isSubset(of: tidy.chosen) ? "Unpick all" : "Pick all") {
                            if paths.isSubset(of: tidy.chosen) { tidy.chosen.subtract(paths) } else { tidy.chosen.formUnion(paths) }
                        }.buttonStyle(.moiGhost)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                        ForEach(moves, id: \.self) { move in tile(move.from) }
                    }
                }
            }
            if !plan.left.isEmpty {
                Text("Leaving alone: " + plan.left.joined(separator: ", ")).font(MoiType.small).foregroundStyle(MoiStyle.quiet).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let picked = tidy.chosen.contains(path)
        return VStack(spacing: 5) {
            FileThumbnail(url: url, size: CGSize(width: 108, height: 76))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(picked ? MoiStyle.coral : MoiStyle.border, lineWidth: picked ? 2.5 : 1))
                .overlay(alignment: .topTrailing) {
                    if picked { Image(systemName: "trash.circle.fill").font(.system(size: 18)).foregroundStyle(.white, MoiStyle.coral).padding(4) }
                }
                .overlay(alignment: .bottomLeading) {
                    if tidy.extraCopies.contains(path) { Text("Copy").font(MoiType.ui(10.5, weight: 700)).padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.65), in: Capsule()).foregroundStyle(.white).padding(5) }
                }
            Text(url.lastPathComponent).font(MoiType.ui(11)).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center).frame(width: 110)
        }
        .opacity(picked ? 0.75 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onTapGesture { if picked { tidy.chosen.remove(path) } else { tidy.chosen.insert(path) } }
        .help(path)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(picked ? "Picked for the Trash" : "")
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earlier clean-ups").font(MoiType.display(16, weight: 640)).padding(.top, 6)
            ForEach(tidy.history.prefix(10)) { record in
                let trashed = record.trashed == true
                HStack(spacing: 10) {
                    Image(systemName: record.undone ? "arrow.uturn.backward.circle" : trashed ? "trash" : "folder").foregroundStyle(MoiStyle.quiet).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trashed ? "Moved to the Trash" : URL(fileURLWithPath: record.folder).lastPathComponent).font(MoiType.ui(13.5, weight: 560))
                        Text("\(record.moves.count) files · \(record.date.formatted(date: .abbreviated, time: .shortened))\(record.undone ? " · put back" : "")").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                    }
                    Spacer()
                    if !record.undone {
                        if !trashed, FileManager.default.fileExists(atPath: record.folder) {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.folder)]) }.buttonStyle(.moiGhost)
                        }
                        Button("Put back") { tidy.undo(record) }.buttonStyle(.moiGhost)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

/// A real Quick Look thumbnail (falls back to the Finder icon while loading or for unknown types).
struct FileThumbnail: View {
    let url: URL
    var size: CGSize
    @State private var image: NSImage?
    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().aspectRatio(contentMode: image == nil ? .fit : .fill)
            .padding(image == nil ? 10 : 0)
            .frame(width: size.width, height: size.height)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
                image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
    }
}
