import SwiftUI

enum CalendarMode: String, CaseIterable, Identifiable { case day = "Day", week = "Week", month = "Month", agenda = "Agenda"; var id: String { rawValue } }
enum AgendaRange: String, CaseIterable, Identifiable { case today = "Today", seven = "7 days", thirty = "30 days", ninety = "90 days", all = "All upcoming"; var id: String { rawValue } }

struct CalendarView: View {
    @EnvironmentObject var store: AppStore
    /// Inside Plan, which already has the title.
    var embedded = false
    @State private var mode: CalendarMode = .agenda
    @State private var range: AgendaRange = .ninety
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !embedded { PageTitle(title: "Calendar", line: "Your schedule and everything with a date.") }
                Spacer()
                if mode != .agenda {
                    HStack(spacing: 6) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).background(MoiStyle.surface, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Previous")
                        Button { selectedDate = Date() } label: { Text("Today").font(MoiType.ui(12.5, weight: 600)).padding(.horizontal, 12).padding(.vertical, 6).background(MoiStyle.surface, in: Capsule()) }.buttonStyle(.plain)
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28).background(MoiStyle.surface, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Next")
                        Text(selectedDate.formatted(mode == .month ? .dateTime.month(.wide).year() : .dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(MoiType.display(16, weight: 640)).frame(minWidth: 110)
                    }
                }
                MoiSegmented(options: CalendarMode.allCases, title: \.rawValue, selection: $mode)
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
            Group {
                switch mode {
                case .day: DaySchedule(date: selectedDate)
                case .week: WeekSchedule(date: selectedDate)
                case .month: MonthSchedule(date: selectedDate, selectedDate: $selectedDate)
                case .agenda: AgendaView(range: $range)
                }
            }
        }.background(MoiStyle.background)
    }

    private func shift(_ direction: Int) {
        let component: Calendar.Component = mode == .month ? .month : mode == .week ? .weekOfYear : .day
        selectedDate = store.calendar.date(byAdding: component, value: direction, to: selectedDate) ?? selectedDate
    }
}

struct DaySchedule: View {
    @EnvironmentObject var store: AppStore
    let date: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ScheduleEngine.occurrences(on: date, data: store.data, calendar: store.calendar)) { item in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .trailing) { Text(item.start.formattedTime(in: store.calendar.timeZone)).font(MoiType.ui(13.5, weight: 620)); Text(item.end.formattedTime(in: store.calendar.timeZone)).font(MoiType.ui(12.5)).foregroundStyle(MoiStyle.quiet) }.monospacedDigit().frame(width: 70)
                        RoundedRectangle(cornerRadius: 3).fill(item.source.category.color).frame(width: 5, height: 58)
                        VStack(alignment: .leading, spacing: 5) { Text(item.title).font(MoiType.ui(15, weight: 620)); CategoryPill(category: item.source.category); if item.isSkipped { Text("Skipped for this occurrence").font(.caption).foregroundStyle(.orange) }; if ScheduleEngine.hasConflict(item, in: ScheduleEngine.occurrences(on: date, data: store.data, calendar: store.calendar)) { Label("Overlaps another block", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) } }
                        Spacer()
                        Menu {
                            Button("Mark complete") { store.complete(item) }
                            Divider()
                            Button("Skip this occurrence") { store.update { $0.overrides.append(DailyOverride(blockID: item.source.id, date: item.start, isSkipped: true)) } }
                            Button("Move this occurrence one hour later") { store.update { $0.overrides.append(DailyOverride(blockID: item.source.id, date: item.start, replacementStart: shifted(item.source.startTime), replacementEnd: shifted(item.source.endTime))) } }
                            Button("Move this & future one hour later") { moveFuture(item) }
                            Button("Disable entire series") { store.update { data in if let i = data.scheduleBlocks.firstIndex(where: { $0.id == item.source.id }) { data.scheduleBlocks[i].isEnabled = false } } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28)
                    }
                    .padding(14).background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24).padding(.vertical, 4)
                }
            }.padding(.vertical, 12)
        }
    }
    private func shifted(_ time: LocalTime) -> LocalTime { LocalTime((time.hour + 1) % 24, time.minute) }
    private func moveFuture(_ item: ScheduleOccurrence) {
        store.update { data in
            guard let index = data.scheduleBlocks.firstIndex(where: { $0.id == item.source.id }),
                  let previousDay = store.calendar.date(byAdding: .day, value: -1, to: store.calendar.startOfDay(for: item.start)) else { return }
            data.scheduleBlocks[index].recurrence.endDate = previousDay
            var future = item.source
            future.id = UUID()
            future.startTime = shifted(future.startTime)
            future.endTime = shifted(future.endTime)
            future.recurrence.id = UUID()
            future.recurrence.startDate = store.calendar.startOfDay(for: item.start)
            future.recurrence.endDate = nil
            data.scheduleBlocks.append(future)
        }
    }
}

struct WeekSchedule: View {
    @EnvironmentObject var store: AppStore
    let date: Date
    var days: [Date] {
        guard let interval = store.calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { store.calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading) { Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold()).foregroundStyle(.secondary); Text(day.formatted(.dateTime.day())).font(.title2.bold()) }
                        Divider()
                        ForEach(ScheduleEngine.occurrences(on: day, data: store.data, calendar: store.calendar).filter { !$0.isSkipped }) { item in
                            VStack(alignment: .leading, spacing: 3) { Text(item.start.formattedTime(in: store.calendar.timeZone)).font(.caption).monospacedDigit(); Text(item.title).font(.callout.weight(.medium)).lineLimit(2) }
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(item.source.category.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(10).frame(width: 150, alignment: .top).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }.padding(20)
        }
    }
}

struct MonthSchedule: View {
    @EnvironmentObject var store: AppStore
    let date: Date
    @Binding var selectedDate: Date
    var cells: [Date?] {
        guard let interval = store.calendar.dateInterval(of: .month, for: date), let days = store.calendar.range(of: .day, in: .month, for: date) else { return [] }
        let offset = (store.calendar.component(.weekday, from: interval.start) - store.calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + days.compactMap { store.calendar.date(bySetting: .day, value: $0, of: interval.start) }
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(rotatedWeekdays, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(8) }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { selectedDate = day } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(day.formatted(.dateTime.day())).fontWeight(store.calendar.isDateInToday(day) ? .bold : .regular)
                                ForEach(deadlines(on: day).prefix(3)) { item in HStack(spacing: 3) { Circle().fill(item.category.color).frame(width: 5, height: 5); Text(item.title).font(.caption2).lineLimit(1) } }
                                Spacer()
                            }.padding(8).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading).background(store.calendar.isDate(day, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                        }.buttonStyle(.plain)
                    } else { Color.clear.frame(minHeight: 88) }
                }
            }.padding(20)
        }
    }
    private var rotatedWeekdays: [String] {
        let symbols = store.calendar.shortWeekdaySymbols
        let offset = store.calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
    private func deadlines(on day: Date) -> [Deadline] { store.data.deadlines.filter { store.calendar.isDate($0.date, inSameDayAs: day) } }
}

struct AgendaView: View {
    @EnvironmentObject var store: AppStore
    @Binding var range: AgendaRange
    var end: Date {
        switch range {
        case .today: store.calendar.date(byAdding: .day, value: 1, to: store.calendar.startOfDay(for: store.now))!
        case .seven: store.calendar.date(byAdding: .day, value: 7, to: store.now)!
        case .thirty: store.calendar.date(byAdding: .day, value: 30, to: store.now)!
        case .ninety: store.calendar.date(byAdding: .day, value: 90, to: store.now)!
        case .all: .distantFuture
        }
    }
    var items: [Deadline] { store.data.deadlines.filter { $0.date >= store.calendar.startOfDay(for: store.now) && $0.date < end }.sorted { $0.date < $1.date } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Picker("Range", selection: $range) { ForEach(AgendaRange.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 500); Spacer(); Text("\(items.count) commitments").font(.caption).foregroundStyle(.secondary) }.padding(16)
            Divider()
            if items.isEmpty { EmptyState(symbol: "calendar.badge.checkmark", title: "Clear horizon", detail: "No deadlines in this range.") }
            else {
                List(items) { item in DeadlineRow(deadline: item).padding(.vertical, 5) }.listStyle(.inset)
            }
        }
    }
}
