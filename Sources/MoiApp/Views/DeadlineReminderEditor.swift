import SwiftUI

struct DeadlineReminderEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let deadline: Deadline
    @State private var custom = false
    @State private var offsets = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deadline Reminders").font(.title2.bold())
            Text(deadline.title).foregroundStyle(.secondary)
            Toggle("Use custom reminder offsets", isOn: $custom)
            TextField("Minutes before deadline, comma-separated", text: $offsets).disabled(!custom)
            Text("Examples: 43200 = 30 days, 1440 = 1 day, 180 = 3 hours.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 500).onAppear { custom = deadline.reminderOffsetsMinutes != nil; offsets = (deadline.reminderOffsetsMinutes ?? []).map(String.init).joined(separator: ", ") }
    }
    private func save() {
        let values = offsets.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 >= 0 }
        store.update { data in if let i = data.deadlines.firstIndex(where: { $0.id == deadline.id }) { data.deadlines[i].reminderOffsetsMinutes = custom ? values : nil } }
        dismiss()
    }
}
