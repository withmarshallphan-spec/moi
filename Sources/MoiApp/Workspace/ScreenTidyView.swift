import AppKit
import SwiftUI

/// "Clean up my desktop": loose files into folders by kind, and the apps you're not using quit,
/// in one go. Everything is shown first, and one button puts it all back.
@MainActor
final class ScreenTidyStore: ObservableObject {
    static let shared = ScreenTidyStore()
    @Published var plan: DesktopTidy.Plan?
    /// Files left out of the clean-up (all are in by default).
    @Published var skipped = Set<String>()
    @Published var apps: [MacControl.OpenApp] = []
    @Published var quitting = Set<pid_t>()
    @Published var message = ""
    @Published var error: String?
    @Published private(set) var running = false
    @Published private(set) var lastRecord: DesktopTidy.Record?
    @Published private(set) var lastQuit: [MacControl.OpenApp] = []
    /// What the last clean-up did, for the share card.
    @Published var last: TidyStats?

    var desktop: URL { ProcessInfo.processInfo.environment["MOI_TIDY_DESKTOP"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true) }

    /// Files grouped by the folder they'd go into ("Screenshots", "Documents", …).
    var groups: [(folder: String, moves: [DesktopTidy.Move])] {
        Dictionary(grouping: plan?.moves ?? []) { URL(fileURLWithPath: $0.to).deletingLastPathComponent().lastPathComponent }
            .map { ($0.key, $0.value) }.sorted { $0.moves.count > $1.moves.count }
    }
    var fileCount: Int { (plan?.moves.count ?? 0) - skipped.count }
    var summary: String {
        let folders = groups.filter { $0.moves.contains { !skipped.contains($0.from) } }.count
        let files = fileCount == 0 ? "No loose files" : "\(fileCount) \(fileCount == 1 ? "file" : "files") into \(folders) \(folders == 1 ? "folder" : "folders")"
        let quits = quitting.isEmpty ? "no apps to quit" : "quit \(quitting.count) \(quitting.count == 1 ? "app" : "apps") you're not using"
        return files + " · " + quits
    }

    /// Looks only. The apps that look unused are picked; you can change any of it.
    func preview() {
        error = nil; message = ""; skipped = []
        do { plan = try DesktopTidy.plan(desktop: desktop) } catch { plan = nil; self.error = "I couldn't look at your Desktop. If macOS asked, allow moi in System Settings → Privacy & Security → Files and Folders." }
        apps = MacControl.openApps().filter { $0.bundleID != "com.apple.finder" }
        quitting = Set(apps.filter { MacControl.idleReason($0) != nil }.map(\.id))
    }

    /// Opened from Ask moi: "go" or "yes" in the chat starts the clean-up.
    @Published var awaitingGo = false

    /// The review on screen is the confirmation (and everything can be put back): apps quit first,
    /// so the desktop shows, then moi tidies the files in front of you.
    func cleanUp() async {
        guard !running else { return }
        awaitingGo = false
        var files = plan
        files?.moves.removeAll { skipped.contains($0.from) }
        let targets = apps.filter { quitting.contains($0.id) }
        guard (files?.moves.isEmpty == false) || !targets.isEmpty else { return }
        running = true; defer { running = false }
        let outcome = await TidyShow.shared.run(files: files, apps: targets)
        var said: [String] = []
        if let record = outcome.record, let files {
            TidyStore.shared.remember(record, failures: outcome.failures)
            error = TidyStore.shared.error
            lastRecord = record.moves.isEmpty ? nil : record
            said.append("Sorted \(record.moves.count) \(record.moves.count == 1 ? "file" : "files") into “\(files.folder.lastPathComponent)”.")
        }
        lastQuit = outcome.quit
        if !targets.isEmpty { said.append("Quit \(outcome.quit.count) \(outcome.quit.count == 1 ? "app" : "apps")." + (outcome.waiting.isEmpty ? "" : " \(outcome.waiting.map(\.name).joined(separator: ", ")) \(outcome.waiting.count == 1 ? "is" : "are") waiting for you to save.")) }
        last = TidyStats(files: outcome.record?.moves.count ?? 0, apps: outcome.quit.count)
        TidyStats.addToLifetime(last!)
        Intelligence.shared.record("desktop clean-up", error == nil ? "Completed" : "Partial", said.joined(separator: " "))
        preview(); message = said.joined(separator: " ")
    }

    func putBack() {
        if let lastRecord { TidyStore.shared.undo(lastRecord); error = TidyStore.shared.error }
        MacControl.reopen(lastQuit)
        lastRecord = nil; lastQuit = []; last = nil
        message = "Everything's back where it was."
        Task { try? await Task.sleep(for: .seconds(1.5)); let note = message; preview(); message = note }
    }
}

struct ScreenTidyView: View {
    @ObservedObject private var tidy = ScreenTidyStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clean up your desktop").font(MoiType.display(20, weight: 650))
                        Text(tidy.summary).font(MoiType.ui(13.5)).foregroundStyle(MoiStyle.quiet)
                    }
                    Spacer()
                    if let last = tidy.last, last.files + last.apps > 0 { Button { MoiWorkspace.shared.shareCard = last } label: { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.moiGhost) }
                    if tidy.lastRecord != nil || !tidy.lastQuit.isEmpty { Button("Put everything back") { tidy.putBack() }.buttonStyle(.moiGhost) }
                    Button(tidy.running ? "Cleaning…" : "Clean up") { Task { await tidy.cleanUp() } }
                        .buttonStyle(.moiPrimary).disabled(tidy.running || (tidy.fileCount == 0 && tidy.quitting.isEmpty))
                }
                .padding(16).background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !tidy.message.isEmpty { Text(tidy.message).font(MoiType.ui(13)).foregroundStyle(MoiStyle.mint) }
                ModuleMessage(text: tidy.error)
                if !tidy.groups.isEmpty {
                    Text("Files → folders").font(MoiType.display(16, weight: 640))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(tidy.groups, id: \.folder) { group in folderCard(group.folder, group.moves) }
                    }
                }
                if !tidy.apps.isEmpty {
                    HStack {
                        Text("Apps").font(MoiType.display(16, weight: 640))
                        Text("Picked: the ones you're not using").font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet)
                        Spacer()
                        Button(tidy.quitting.count == tidy.apps.count ? "Keep all" : "Quit all") { tidy.quitting = tidy.quitting.count == tidy.apps.count ? [] : Set(tidy.apps.map(\.id)) }.buttonStyle(.moiGhost)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                        ForEach(tidy.apps) { app in appTile(app) }
                    }
                }
                Text("Folders and apps stay where they are, and files still downloading are left alone.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .onAppear { if tidy.plan == nil && tidy.apps.isEmpty { tidy.preview() } }
    }

    private func folderCard(_ folder: String, _ moves: [DesktopTidy.Move]) -> some View {
        let on = moves.contains { !tidy.skipped.contains($0.from) }
        let symbol = DesktopTidy.Kind(rawValue: folder)?.symbol ?? "folder"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(folder, systemImage: symbol).font(MoiType.ui(13.5, weight: 620))
                Spacer()
                Text("\(moves.count)").font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? MoiStyle.accent : MoiStyle.quiet)
            }
            HStack(spacing: 6) {
                ForEach(moves.prefix(4), id: \.from) { FileThumbnail(url: URL(fileURLWithPath: $0.from), size: CGSize(width: 44, height: 44)) }
                if moves.count > 4 { Text("+\(moves.count - 4)").font(MoiType.ui(12)).foregroundStyle(MoiStyle.quiet) }
            }
        }
        .padding(12).opacity(on ? 1 : 0.5)
        .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { let paths = moves.map(\.from); if on { tidy.skipped.formUnion(paths) } else { tidy.skipped.subtract(paths) } }
        .help(on ? "Leave these where they are" : "Sort these too")
    }

    private func appTile(_ app: MacControl.OpenApp) -> some View {
        let on = tidy.quitting.contains(app.id)
        return HStack(spacing: 10) {
            Image(nsImage: app.url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(MoiType.ui(13.5, weight: 600)).lineLimit(1)
                Text(MacControl.idleReason(app) ?? "In use").font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet).lineLimit(1)
            }
            Spacer()
            Image(systemName: on ? "xmark.circle.fill" : "circle").foregroundStyle(on ? MoiStyle.coral : MoiStyle.quiet)
        }
        .padding(10)
        .background(on ? MoiStyle.coral.opacity(0.1) : MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if on { tidy.quitting.remove(app.id) } else { tidy.quitting.insert(app.id) } }
        .accessibilityElement(children: .combine).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(on ? "Will quit" : "Will stay open")
    }
}
