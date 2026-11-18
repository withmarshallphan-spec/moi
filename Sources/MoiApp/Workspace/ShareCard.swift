import AppKit
import SwiftUI

/// What a clean-up did, for the share card (and moi's lifetime count).
struct TidyStats: Identifiable, Equatable {
    var id = UUID()
    var files: Int
    var apps: Int
    /// Set by Wrap up my day: things ticked off today.
    var doneToday: Int?

    static var lifetimeFiles: Int { UserDefaults.standard.integer(forKey: "moi.stats.files") }
    static func addToLifetime(_ stats: TidyStats) {
        UserDefaults.standard.set(lifetimeFiles + stats.files, forKey: "moi.stats.files")
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "moi.stats.apps") + stats.apps, forKey: "moi.stats.apps")
    }
}

/// The card itself: made to be posted.
struct ShareCardImage: View {
    let stats: TidyStats
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            MoiCharacter(state: .success, size: 180, sticker: true, essential: true)
            VStack(spacing: 6) {
                if stats.files > 0 { line("\(stats.files)", stats.files == 1 ? "file tidied" : "files tidied") }
                if stats.apps > 0 { line("\(stats.apps)", stats.apps == 1 ? "app closed" : "apps closed") }
                if let done = stats.doneToday, done > 0 { line("\(done)", done == 1 ? "thing done today" : "things done today") }
            }
            Text(stats.doneToday != nil ? "Day wrapped. Desk clear." : "Desk clear. Mind clear.").font(MoiType.display(22, weight: 600)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Text("moi, a little helper for your Mac · marshallphan.com").font(MoiType.ui(14, weight: 560)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(36)
        .frame(width: 540, height: 540)
        .background(LinearGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.35), Color(red: 0.55, green: 0.35, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    private func line(_ number: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number).font(MoiType.display(56, weight: 720)).foregroundStyle(.white).monospacedDigit()
            Text(label).font(MoiType.display(26, weight: 620)).foregroundStyle(.white.opacity(0.9))
        }
    }
}

extension ShareCardImage {
    /// Renders the card at 1080 × 1080 (development: checking how it looks).
    static func export(_ stats: TidyStats, to url: URL) {
        let renderer = ImageRenderer(content: ShareCardImage(stats: stats)); renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }
}

/// Shows the card with Share and Copy.
struct ShareCardSheet: View {
    let stats: TidyStats
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var image: NSImage? {
        let renderer = ImageRenderer(content: ShareCardImage(stats: stats))
        renderer.scale = 2 // 1080 × 1080
        return renderer.nsImage
    }
    var body: some View {
        VStack(spacing: 16) {
            ShareCardImage(stats: stats).scaleEffect(0.7).frame(width: 378, height: 378)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack {
                Button("Done") { dismiss() }.buttonStyle(.moiGhost).keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? "Copied" : "Copy image") {
                    guard let image else { return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]); copied = true
                }.buttonStyle(.moiGhost)
                if let image {
                    ShareLink(item: Image(nsImage: image), preview: SharePreview("moi tidied up", image: Image(nsImage: image))) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.moiPrimary)
                }
            }
            Text("moi has tidied \(TidyStats.lifetimeFiles) files for you so far.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
        }
        .padding(24).frame(width: 430)
    }
}
