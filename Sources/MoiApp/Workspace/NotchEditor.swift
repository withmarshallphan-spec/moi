import SwiftUI

/// Edit the notch like a Lock Screen: a live preview on top, the parts below. Turn parts on or
/// off, drag to reorder; the first one is what resting the pointer shows.
struct NotchEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var notch: NotchController
    @StateObject private var preview = NotchController.preview()
    @ObservedObject private var weather = WeatherGlance.shared
    @ObservedObject private var calendar = CalendarGlance.shared
    @State private var order: [NotchPart] = []
    @State private var on: Set<NotchPart> = []
    @State private var city = WeatherGlance.shared.city
    @State private var live = NotchPreferences().liveActivity
    @AppStorage("moi.notchSystemFont") private var systemFont = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [MoiStyle.accent.opacity(0.35), MoiStyle.sky.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                NotchPanelView(controller: preview, spotify: preview.spotify).environmentObject(store)
                    .allowsHitTesting(false)
                    .scaleEffect(0.72, anchor: .top) // the whole glance fits, even with every part on
            }
            .frame(height: 290).clipped()
            .overlay(alignment: .bottomLeading) { Text("Preview · first part shows when you rest the pointer").font(MoiType.small).foregroundStyle(.white.opacity(0.8)).padding(12) }
            List {
                Section("Parts") {
                    ForEach(order) { part in row(part) }
                        .onMove { order.move(fromOffsets: $0, toOffset: $1); save() }
                }
                Section("Style") {
                    Toggle("Mini notch while music plays or Focus runs (like an iPhone)", isOn: $live)
                        .onChange(of: live) { _, value in NotchPreferences().liveActivity = value; notch.collapse() }
                    Picker("Font", selection: $systemFont) { Text("Apple system (native)").tag(true); Text("moi's own").tag(false) }
                        .pickerStyle(.segmented)
                }
            }
            HStack {
                Text("Drag to reorder. Changes show in the real notch straight away.").font(MoiType.small).foregroundStyle(MoiStyle.quiet)
                Spacer()
                Button("Show me the notch") { notch.expand(sticky: true) }.buttonStyle(.moiGhost)
                Button("Done") { dismiss() }.buttonStyle(.moiPrimary).keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 620, height: 820)
        .onAppear {
            let chosen = NotchPreferences().parts
            on = Set(chosen); order = chosen + NotchPart.allCases.filter { !chosen.contains($0) }
            CalendarGlance.shared.refresh(); Task { await WeatherGlance.shared.refresh() }
        }
        .onChange(of: systemFont) { _, _ in preview.partsChanged(); notch.partsChanged() }
    }

    private func row(_ part: NotchPart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: part.symbol).foregroundStyle(MoiStyle.accent).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.title).font(MoiType.ui(13.5, weight: 620))
                    Text(part.detail).font(MoiType.ui(12)).foregroundStyle(MoiStyle.quiet)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { on.contains(part) }, set: { value in
                    if value { on.insert(part) } else { on.remove(part) }
                    save()
                    if value, part == .calendar, !calendar.allowed { calendar.requestAccess() }
                })).labelsHidden().toggleStyle(.switch)
            }
            if on.contains(part), part == .weather {
                HStack {
                    TextField("Your city, e.g. Jakarta", text: $city).textFieldStyle(.roundedBorder).onSubmit { Task { await weather.setCity(city); preview.partsChanged() } }
                    Button("Set") { Task { await weather.setCity(city); preview.partsChanged() } }.buttonStyle(.moiGhost)
                }
                Text("UV and temperature come from Open-Meteo (free, no account), using only your city's location. " + (weather.message ?? "")).font(MoiType.ui(11.5)).foregroundStyle(MoiStyle.quiet)
            }
            if on.contains(part), part == .calendar, !calendar.allowed {
                Button("Allow moi to read Calendar") { calendar.requestAccess() }.buttonStyle(.moiGhost)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        NotchPreferences().parts = order.filter(on.contains)
        preview.partsChanged(); notch.partsChanged()
    }
}
