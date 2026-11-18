import SwiftUI

/// "Wrap up my day": what you finished, what's tomorrow, then moi tidies the desktop and closes
/// your apps on screen, and hands you a card of the day.
struct WrapUpView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tidy = ScreenTidyStore.shared
    @State private var tidyDesktop = true
    @State private var closeApps = true

    private var doneToday: [String] {
        let cal = store.calendar
        return store.data.tasks.filter { $0.completedAt.map { cal.isDate($0, inSameDayAs: store.now) } ?? false }.map(\.title)
            + store.data.deadlines.filter { $0.completedAt.map { cal.isDate($0, inSameDayAs: store.now) } ?? false }.map(\.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                MoiCharacter(state: .happy, size: 56, sticker: true, essential: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wrap up your day").font(MoiType.display(24, weight: 660))
                    Text(store.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                }
            }
            section("Done today") {
                if doneToday.isEmpty { Text("Nothing ticked off today. That's okay, some days are like that.").font(MoiType.body).foregroundStyle(MoiStyle.quiet) }
                ForEach(doneToday.prefix(6), id: \.self) { Label($0, systemImage: "checkmark.circle.fill").font(MoiType.body).foregroundStyle(Color.primary).symbolRenderingMode(.multicolor) }
                if doneToday.count > 6 { Text("and \(doneToday.count - 6) more").font(MoiType.small).foregroundStyle(MoiStyle.quiet) }
            }
            section("Tomorrow") {
                Text(DayAnswers.answer(.tomorrow, data: store.data, now: store.now, calendar: store.calendar)).font(MoiType.body).fixedSize(horizontal: false, vertical: true)
            }
            section("Before you go") {
                Toggle("Tidy my desktop" + (tidy.fileCount > 0 ? " (\(tidy.fileCount) loose files)" : ""), isOn: $tidyDesktop)
                Toggle("Close my apps" + (tidy.apps.isEmpty ? "" : " (\(tidy.apps.count) open)"), isOn: $closeApps)
                Text("Apps with unsaved work will ask you first. Put back undoes the tidy.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
            }
            HStack {
                Button("Not yet") { dismiss() }.buttonStyle(.moiGhost).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Wrap up") { wrapUp() }.buttonStyle(.moiPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 480)
        .onAppear { tidy.preview() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(MoiType.ui(13, weight: 650)).foregroundStyle(MoiStyle.quiet); content() }
    }

    private func wrapUp() {
        let done = doneToday.count
        if !tidyDesktop { tidy.skipped = Set(tidy.plan?.moves.map(\.from) ?? []) }
        tidy.quitting = closeApps ? Set(tidy.apps.map(\.id)) : []
        dismiss()
        Task {
            if tidyDesktop || closeApps { await tidy.cleanUp() }
            let last = tidy.last ?? TidyStats(files: 0, apps: 0)
            MoiWorkspace.shared.shareCard = TidyStats(files: last.files, apps: last.apps, doneToday: done)
        }
    }
}
