import AppKit
import Photos
import SwiftUI

/// Clean up → Photos: search by what's in a photo, where or when; then make an album or a folder.
struct PhotoResultsView: View {
    @ObservedObject private var finder = PhotoFinder.shared
    @ObservedObject private var tidy = TidyStore.shared
    @State private var text = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MoiStyle.quiet)
                    TextField("“flowers and my trips”, “trip in Italy”, “dog 2023”", text: $text).textFieldStyle(.plain).font(MoiType.ui(14.5)).onSubmit { finder.search(text) }
                    if finder.progress != nil { Button("Stop") { finder.cancel() }.buttonStyle(.moiGhost) }
                    else { Button("Find") { finder.search(text) }.buttonStyle(.moiPrimary).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MoiStyle.border))
                Text("Searches your Photos library plus Pictures, Desktop and Downloads, on this Mac. Ask for several things at once, or “my trips” to sort every trip by place. Right-click any photo to make it your wallpaper.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                if let progress = finder.progress { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(progress).font(MoiType.ui(13)) } }
                if !finder.message.isEmpty { Text(finder.message).font(MoiType.ui(13.5, weight: 600)) }
                ModuleMessage(text: finder.error)
                if !finder.wallpaperPicks.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(Array(finder.wallpaperPicks.enumerated()), id: \.element.id) { index, pick in
                            let current = finder.applied == pick.id
                            VStack(alignment: .leading, spacing: 6) {
                                PhotoTile(source: pick.id)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(current ? MoiStyle.accent : .clear, lineWidth: 2.5))
                                Text(index == 0 ? "Best match" : "Option \(index + 1)").font(MoiType.ui(13.5, weight: 640))
                                Text(pick.reason).font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                if current { Label("On your desktop", systemImage: "checkmark.circle.fill").font(MoiType.ui(12, weight: 600)).foregroundStyle(MoiStyle.mint) }
                                else { Button("Use this one") { Task { await finder.applyWallpaper(pick) } }.buttonStyle(.moiSecondary) }
                            }
                        }
                    }
                }
                if finder.canRestoreWallpaper { Button("Go back to my old wallpaper") { finder.restoreWallpaper() }.buttonStyle(.moiGhost) }
                if !finder.hits.isEmpty { actions; grid }
                ModuleMessage(text: tidy.error)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .onAppear { if text.isEmpty { text = finder.request } }
    }

    private func picked(_ group: PhotoFinder.Group) -> (assets: Int, files: Int) {
        group.hits.reduce(into: (0, 0)) { n, hit in
            guard finder.chosen.contains(hit.id) else { return }
            if case .asset = hit.id { n.0 += 1 } else { n.1 += 1 }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            let all = Set(finder.hits.map(\.id))
            Button(finder.chosen == all ? "Unpick all" : "Pick all") { finder.chosen = finder.chosen == all ? [] : all }.buttonStyle(.moiGhost)
            Spacer()
            if finder.groups.count > 1 {
                let albums = finder.groups.filter { picked($0).assets > 0 }, folders = finder.groups.filter { picked($0).files > 0 }
                if !albums.isEmpty { Button("Make \(albums.count) \(albums.count == 1 ? "album" : "albums") in Photos") { makeAlbums(albums) }.buttonStyle(.moiPrimary) }
                if !folders.isEmpty { Button("Sort files into \(folders.count) \(folders.count == 1 ? "folder" : "folders")") { moveFiles(folders) }.buttonStyle(albums.isEmpty ? .moiPrimary : .moiGhost) }
            }
        }
    }

    private func makeAlbums(_ groups: [PhotoFinder.Group]) {
        Task {
            var made: [String] = []
            for group in groups {
                do { made.append(try await finder.makeAlbum(group)) } catch { finder.error = error.localizedDescription }
            }
            if !made.isEmpty { finder.message = "Made \(made.count == 1 ? "the album “\(made[0])”" : "\(made.count) albums (\(made.joined(separator: ", ")))") in Photos. Your photos weren't changed." }
        }
    }

    private func moveFiles(_ groups: [PhotoFinder.Group]) {
        // A photo in two groups goes into the first one's folder; later plans skip what already moved.
        let moved = groups.compactMap(finder.folderPlan).compactMap { plan -> String? in
            var plan = plan
            plan.moves.removeAll { !FileManager.default.fileExists(atPath: $0.from) }
            return plan.moves.isEmpty ? nil : tidy.apply(plan)
        }
        finder.message = moved.joined(separator: " ") + " Put back from Clean up → Files any time."
        finder.search(finder.request)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(finder.groups) { group in
                let n = picked(group)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(group.title).font(MoiType.display(15.5, weight: 640))
                        Text("\(group.hits.count)").font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet)
                        Spacer()
                        if n.assets > 0 { Button("Album of \(n.assets)") { makeAlbums([group]) }.buttonStyle(.moiSecondary) }
                        if n.files > 0, let plan = finder.folderPlan(group) { Button("Move \(n.files) into “\(plan.folder.lastPathComponent)”") { moveFiles([group]) }.buttonStyle(.moiSecondary) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(group.hits) { hit in
                            let on = finder.chosen.contains(hit.id)
                            PhotoTile(source: hit.id)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(on ? MoiStyle.accent : MoiStyle.border, lineWidth: on ? 2.5 : 1))
                                .overlay(alignment: .topTrailing) { if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, MoiStyle.accent).padding(4) } }
                                .onTapGesture { if on { finder.chosen.remove(hit.id) } else { finder.chosen.insert(hit.id) } }
                                .contextMenu {
                                    Button("Use as wallpaper") { Task { do { _ = try await finder.setWallpaper(hit.id); finder.message = "That's your wallpaper now. Your old one is still in System Settings → Wallpaper." } catch { finder.error = error.localizedDescription } } }
                                    if case let .file(url) = hit.id { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                                }
                                .help(hit.date?.formatted(date: .abbreviated, time: .omitted) ?? "")
                        }
                    }
                }
            }
        }
    }
}

private struct PhotoTile: View {
    let source: PhotoFinder.Source
    @State private var image: NSImage?
    var body: some View {
        Group {
            switch source {
            case let .file(url): FileThumbnail(url: url, size: CGSize(width: 110, height: 110))
            case .asset:
                ZStack { Color.primary.opacity(0.05); if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) } }
                    .frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .task(id: source) {
            guard case let .asset(id) = source, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                  let cg = await PhotoFinder.shared.thumbnail(asset, size: 220) else { return }
            image = NSImage(cgImage: cg, size: .zero)
        }
    }
}

/// Clean up → Open apps: everything that's open on every desktop; pick several, then quit or hide them.
struct OpenAppsView: View {
    @State private var apps: [MacControl.OpenApp] = []
    @State private var picked = Set<pid_t>()
    @State private var message = ""
    @State private var lastQuit: [MacControl.OpenApp] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("\(apps.count) apps open · \(apps.reduce(0) { $0 + $1.windows }) windows").font(MoiType.display(17, weight: 640))
                    Spacer()
                    Button(picked.count == apps.count ? "Unpick all" : "Pick all") { picked = picked.count == apps.count ? [] : Set(apps.map(\.id)) }.buttonStyle(.moiGhost)
                    Button("Hide \(picked.count)") { MacControl.hide(apps.filter { picked.contains($0.id) }); message = "Hidden. Click their Dock icons to bring them back."; refresh() }.buttonStyle(.moiGhost).disabled(picked.isEmpty)
                    Button("Quit \(picked.count)") {
                        lastQuit = MacControl.quit(apps.filter { picked.contains($0.id) })
                        message = "Asked \(lastQuit.count) to quit. Apps with unsaved work will ask first."
                        picked = []
                        Task { try? await Task.sleep(for: .seconds(1.2)); refresh() }
                    }.buttonStyle(.moiPrimary).disabled(picked.isEmpty)
                }
                if !message.isEmpty {
                    HStack { Text(message).font(MoiType.ui(13)).foregroundStyle(MoiStyle.mint); if !lastQuit.isEmpty { Button("Reopen them") { MacControl.reopen(lastQuit); lastQuit = []; message = ""; Task { try? await Task.sleep(for: .seconds(1.5)); refresh() } }.buttonStyle(.moiGhost) } }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
                    ForEach(apps) { app in
                        let on = picked.contains(app.id)
                        HStack(spacing: 10) {
                            Image(nsImage: app.url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()).resizable().frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(MoiType.ui(13.5, weight: 600)).lineLimit(1)
                                Text(app.windows == 0 ? (app.hidden ? "Hidden" : "No windows") : "\(app.windows) window\(app.windows == 1 ? "" : "s")").font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet)
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? MoiStyle.accent : MoiStyle.quiet)
                        }
                        .padding(10)
                        .background(on ? MoiStyle.accent.opacity(0.12) : MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { if on { picked.remove(app.id) } else { picked.insert(app.id) } }
                        .accessibilityElement(children: .combine).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
                Text("Window counts include every desktop. Finder always stays. Tip: say “quit everything except Safari”.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .onAppear(perform: refresh)
    }
    private func refresh() { apps = MacControl.openApps(); picked = picked.intersection(apps.map(\.id)) }
}

/// Clean up → Dock: take apps out, add one, or go back to how it was.
struct DockView: View {
    @State private var items: [DockLayout.Item] = []
    @State private var picked = Set<String>()
    @State private var backup: [DockLayout.Item]?
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("\(items.count) apps in your Dock").font(MoiType.display(17, weight: 640))
                    Spacer()
                    if let backup { Button("Go back to my old Dock") { MacControl.setDockItems(backup); self.backup = nil; message = "Your Dock is back the way it was."; reload() }.buttonStyle(.moiGhost) }
                    Button("Add an app…") {
                        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]
                        if panel.runModal() == .OK, let url = panel.url { change(DockLayout.adding(appAt: url, bundleID: Bundle(url: url)?.bundleIdentifier, to: items), "Added \(url.deletingPathExtension().lastPathComponent).") }
                    }.buttonStyle(.moiGhost)
                    Button("Take \(picked.count) out") { change(DockLayout.removing(Array(picked), from: items).items, "Took \(picked.count) out. The apps are still installed.") }.buttonStyle(.moiPrimary).disabled(picked.isEmpty)
                }
                if !message.isEmpty { Text(message).font(MoiType.ui(13)).foregroundStyle(MoiStyle.mint) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                    ForEach(items.indices, id: \.self) { index in
                        let label = DockLayout.label(items[index]), on = picked.contains(label)
                        HStack(spacing: 10) {
                            Image(nsImage: DockLayout.path(items[index]).map { NSWorkspace.shared.icon(forFile: $0) } ?? NSImage()).resizable().frame(width: 28, height: 28)
                            Text(label).font(MoiType.ui(13.5, weight: 560)).lineLimit(1)
                            Spacer()
                            Image(systemName: on ? "minus.circle.fill" : "circle").foregroundStyle(on ? MoiStyle.coral : MoiStyle.quiet)
                        }
                        .padding(10)
                        .background(on ? MoiStyle.coral.opacity(0.1) : MoiStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { if on { picked.remove(label) } else { picked.insert(label) } }
                    }
                }
                Text("Taking an app out of the Dock doesn't uninstall it. The Dock restarts for a moment to show the change.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .onAppear(perform: reload)
    }
    private func reload() { items = MacControl.dockItems(); picked = [] }
    private func change(_ new: [DockLayout.Item], _ text: String) {
        if backup == nil { backup = items }
        MacControl.setDockItems(new); message = text
        Task { try? await Task.sleep(for: .seconds(0.8)); reload() }
    }
}
