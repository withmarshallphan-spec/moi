import SwiftUI
import CoreText

/// moi's type. Bricolage Grotesque (display, moi's voice): warm, a little quirky with ink
/// traps, still professional. Instrument Sans (interface): understated and precise, not an
/// Apple imitation. Both SIL OFL 1.1, bundled, so the open-source app can ship them.
extension Bundle {
    /// moi's resources (fonts, sounds, voice). The app keeps them in Contents/Resources; SwiftPM's own
    /// `Bundle.module` only looks beside the app and in the build folder, so it fails once the app is moved.
    static let moi: Bundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Moi_MoiApp.bundle")) } ?? .module
}

enum MoiType {
    static func register() {
        for name in ["BricolageGrotesque", "InstrumentSans"] {
            guard let url = Bundle.moi.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") ?? Bundle.moi.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    /// Headings, greetings, moi speaking. Optical size follows point size.
    static func display(_ size: CGFloat, weight: CGFloat = 620, width: CGFloat = 94) -> Font {
        font("Bricolage Grotesque", size, [0x77676874: weight, 0x77647468: width, 0x6F70737A: min(96, max(12, size))])
    }
    /// Everything else: controls, body, navigation.
    static func ui(_ size: CGFloat = 13, weight: CGFloat = 440) -> Font {
        font("Instrument Sans", size, [0x77676874: weight, 0x77647468: 100])
    }
    static let body = ui(13.5)
    static let small = ui(12, weight: 470)
    static let label = ui(12.5, weight: 560)

    private static var cache: [String: Font] = [:]
    private static func font(_ family: String, _ size: CGFloat, _ axes: [UInt32: CGFloat]) -> Font {
        let key = "\(family)-\(size)-\(axes.sorted { $0.key < $1.key }.map { "\($0.value)" }.joined(separator: ","))"
        if let cached = cache[key] { return cached }
        let variations = Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) })
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family, kCTFontVariationAttribute: variations] as CFDictionary)
        let font = Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        cache[key] = font
        return font
    }
}

/// moi's palette. The app chrome uses ordinary macOS colours (your system accent, standard
/// green/orange/red for states) so it reads as a serious tool; moi itself, the character, is the
/// one splash of colour, in whichever shade you picked (MoiPalette).
enum MoiStyle {
    static let corner: CGFloat = 14
    static let sidebarWidth: CGFloat = 220
    static let background = adaptive(dark: 0x0F0F11, light: 0xECECEF)
    static let surface = adaptive(dark: 0x18181B, light: 0xFFFFFF)
    static let raisedSurface = adaptive(dark: 0x232327, light: 0xDCDDE2)
    static let border = adaptive(dark: 0xFFFFFF, light: 0x000000, alpha: 0.085)
    /// Secondary text with real contrast (≥ 4.5:1 on surface in both modes).
    static let quiet = adaptive(dark: 0x9A9AA3, light: 0x5C5C66)
    /// Your macOS accent colour: buttons, selection, links.
    static let accent = Color.accentColor
    /// Fills that carry white text.
    static let butterFill = Color.accentColor
    static let mint = Color.green
    /// "Due today".
    static let butter = Color.orange
    /// Overdue, destructive, failed.
    static let coral = Color.red
    static let sky = Color.blue
    /// The hardware notch is pure black; anything touching it must be too, or a seam shows.
    static let notch = Color.black
    static let accentWarm = mint

    private static func adaptive(dark: UInt32, light: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
        })
    }

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24

    /// Matches the existing notch-button press animation.
    static let motionQuick: Double = 0.1
    /// Matches the existing panel-resize/reminder-transition animation.
    static let motionStandard: Double = 0.18
    /// For entrance/state-change animations (message bubbles, checkmarks, countdowns).
    static let motionGentle: Double = 0.28
}

extension Animation {
    /// Returns `nil` under Reduce Motion so the change applies instantly instead of stuttering.
    static func moi(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

extension ItemCategory {
    var color: Color {
        switch self {
        case .work: Color(red: 0.53, green: 0.65, blue: 1.0)
        case .study: Color(red: 0.25, green: 0.75, blue: 1.0)
        case .creative: Color(red: 0.20, green: 0.90, blue: 0.82)
        case .gym: Color(red: 0.35, green: 0.90, blue: 0.42)
        case .personal: Color.secondary
        case .deadline: Color(red: 1.0, green: 0.38, blue: 0.36)
        case .deepWork: Color(red: 1.0, green: 0.67, blue: 0.22)
        case .admin: Color(red: 1.0, green: 0.84, blue: 0.28)
        default: Color.secondary
        }
    }
}

/// The app-wide button style. Every variant shares the same press feedback
/// (scale 0.92, opacity 0.72, quick ease-out, Reduce Motion gated) that the
/// original notch-only button style established; only resting chrome differs.
struct MoiButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost, destructive }
    var variant: Variant = .secondary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MoiType.ui(13, weight: 580))
            .padding(.horizontal, MoiStyle.spacingMD)
            .padding(.vertical, MoiStyle.spacingSM)
            .background(background, in: RoundedRectangle(cornerRadius: MoiStyle.corner - 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MoiStyle.corner - 4, style: .continuous)
                    .stroke(borderColor, lineWidth: variant == .secondary ? 1 : 0)
            )
            .foregroundStyle(foreground)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.moi(MoiStyle.motionQuick, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var background: Color {
        switch variant {
        case .primary: MoiStyle.butterFill
        case .secondary: MoiStyle.raisedSurface
        case .ghost: .clear
        case .destructive: MoiStyle.coral.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: Color.white
        case .secondary: .primary
        case .ghost: .primary.opacity(0.85)
        case .destructive: MoiStyle.coral
        }
    }

    private var borderColor: Color { variant == .secondary ? MoiStyle.border : .clear }
}

extension ButtonStyle where Self == MoiButtonStyle {
    static var moiPrimary: MoiButtonStyle { MoiButtonStyle(variant: .primary) }
    static var moiSecondary: MoiButtonStyle { MoiButtonStyle(variant: .secondary) }
    static var moiGhost: MoiButtonStyle { MoiButtonStyle(variant: .ghost) }
    static var moiDestructive: MoiButtonStyle { MoiButtonStyle(variant: .destructive) }
}

/// Unifies the icon-only "ellipsis menu" idiom that was previously hand-rolled
/// at each call site with slightly different sizing/chrome.
struct MoiIconMenu<Content: View>: View {
    let symbol: String
    let accessibilityLabel: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(MoiStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MoiStyle.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Unifies the text-label dropdown idiom (e.g. "Status: Active", category filters)
/// that previously used bare `Menu("...")` with default system chrome.
struct MoiMenu<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Text(label).font(.callout.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, MoiStyle.spacingMD)
            .padding(.vertical, MoiStyle.spacingSM)
            .background(MoiStyle.raisedSurface, in: RoundedRectangle(cornerRadius: MoiStyle.corner - 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MoiStyle.corner - 4, style: .continuous).stroke(MoiStyle.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }
}

struct Card<Content: View>: View {
    /// When true, the card's background stretches to match the tallest sibling in
    /// its row instead of hugging its own content — for cards placed side-by-side
    /// in a fixed HStack row. Defaults to false because a handful of standalone
    /// cards sit directly in a ScrollView with no enclosing row to bound them;
    /// an unconditional `maxHeight: .infinity` there would blow up to the full
    /// scroll height instead of just evening out a row.
    var fillHeight: Bool = false
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(MoiStyle.surface, in: RoundedRectangle(cornerRadius: MoiStyle.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MoiStyle.corner).stroke(MoiStyle.border, lineWidth: 1))
    }
}

struct CategoryPill: View {
    let category: ItemCategory
    var body: some View {
        Label(category.rawValue, systemImage: category.symbol)
            .font(MoiType.ui(11.5, weight: 560))
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(category.color.opacity(0.13), in: Capsule())
    }
}

/// moi's segmented control: a pill track with a butter-yellow highlight that slides between options.
struct MoiSegmented<T: Hashable>: View {
    let options: [T]
    var title: (T) -> String
    @Binding var selection: T
    @Namespace private var namespace
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option } } label: {
                    Text(title(option)).font(MoiType.ui(12.5, weight: 600))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background { if selected { Capsule().fill(MoiStyle.butterFill).matchedGeometryEffect(id: "pill", in: namespace) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3).background(MoiStyle.surface, in: Capsule()).overlay(Capsule().stroke(MoiStyle.border))
    }
}

/// A screen's title: the heading in moi's display face, and optionally one line in moi's voice.
/// No eyebrow labels above headings.
struct PageTitle: View {
    var title: String
    var line: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MoiType.display(30, weight: 660))
            if let line { Text(line).font(MoiType.ui(14)).foregroundStyle(MoiStyle.quiet) }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
    }
}

struct CurrentBlockCard: View {
    @EnvironmentObject var store: AppStore
    let compact: Bool

    var body: some View {
        Group {
            if store.activeFocus != nil { TimelineView(.periodic(from: .now, by: 1)) { context in content(at: context.date) } }
            else { content(at: store.now) }
        }
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        let state = ScheduleEngine.state(at: date, data: store.data, calendar: store.calendar)
        switch state {
        case let .active(item, next): active(item, next: next, now: date)
        case let .gap(previous, next): gap(previous: previous, next: next, now: date)
        case let .beforeDay(next): gap(previous: nil, next: next, now: date)
        case let .afterDay(previous): gap(previous: previous, next: nil, now: date)
        }
    }

    @ViewBuilder private func active(_ item: ScheduleOccurrence, next: ScheduleOccurrence?, now: Date) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(now.formatted(date: .omitted, time: .shortened)).monospacedDigit().bold()
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.title).lineLimit(1).font(MoiType.ui(13, weight: 620))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(ScheduleEngine.remainingText(until: item.end, from: now)) left").monospacedDigit()
                }
                ProgressView(value: ScheduleEngine.progress(of: item, at: now)).tint(item.source.category.color)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(now.formatted(date: .omitted, time: .shortened)).font(MoiType.display(31, weight: 560)).monospacedDigit()
                    Spacer()
                    CategoryPill(category: item.source.category)
                }
                Text(item.title).font(MoiType.display(24, weight: 660)).lineLimit(2)
                if !item.source.notes.isEmpty { Text(item.source.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                HStack {
                    Text("\(ScheduleEngine.remainingText(until: item.end, from: now)) left").font(.headline).monospacedDigit()
                    Spacer()
                    Text("\(item.start.formattedTime(in: store.calendar.timeZone))–\(item.end.formattedTime(in: store.calendar.timeZone))").foregroundStyle(.secondary)
                }
                ProgressView(value: ScheduleEngine.progress(of: item, at: now)).tint(item.source.category.color)
                if let next {
                    Text("Then \(next.title) at \(next.start.formattedTime(in: store.calendar.timeZone))")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
                if !item.source.workspaceItemIDs.isEmpty {
                    Button("Start workspace") { LauncherService.openWorkspace(ids: item.source.workspaceItemIDs, data: store.data) }
                        .font(.caption.bold()).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private func gap(previous: ScheduleOccurrence?, next: ScheduleOccurrence?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 12) {
            HStack {
                Text(now.formatted(date: .omitted, time: .shortened)).font(compact ? MoiType.ui(14, weight: 620) : MoiType.display(31, weight: 560)).monospacedDigit()
                Text("· free").font(compact ? MoiType.ui(14, weight: 620) : MoiType.display(24, weight: 640))
            }
            if let next {
                Text("Next: \(next.title) at \(next.start.formattedTime(in: store.calendar.timeZone)) · in \(ScheduleEngine.remainingText(until: next.start, from: now))")
                    .foregroundStyle(.secondary).lineLimit(1)
            } else { Text("No more scheduled blocks today").foregroundStyle(.secondary) }
            if !compact, let previous, previous.completion == nil {
                HStack {
                    Text("\(previous.title) was not marked complete").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Complete") { store.complete(previous) }.buttonStyle(.borderless)
                    Button("Skip") { store.complete(previous, state: .skipped) }.buttonStyle(.borderless)
                }
            }
        }
    }
}

struct DeadlineRow: View {
    @EnvironmentObject var store: AppStore
    let deadline: Deadline
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(deadline.category.color).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 6) {
                    Text(deadline.date.formattedDate(in: store.calendar.timeZone, includeTime: !deadline.isDateOnly))
                    if deadline.isTentative { Text("Tentative").foregroundStyle(MoiStyle.butter) }
                    if deadline.needsVerification { Label("Check the date", systemImage: "exclamationmark.triangle").foregroundStyle(MoiStyle.butter) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(DeadlineEngine.countdown(to: deadline, now: store.now, calendar: store.calendar))
                .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(deadline.priority >= .high ? .primary : .secondary)
        }
    }
}

struct ModuleHeader: View {
    var title: String
    var subtitle: String
    var status = "Working"
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.hasPrefix("moi ") ? String(title.dropFirst(4)) : title).font(MoiType.display(30, weight: 660))
                Text(subtitle).font(MoiType.ui(14)).foregroundStyle(MoiStyle.quiet).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            // Honest status, said quietly: a dot and a word, not a badge competing with the title.
            HStack(spacing: 6) {
                Circle().fill(status == "Working" ? MoiStyle.mint : status == "Blocked" ? MoiStyle.coral : MoiStyle.sky).frame(width: 7, height: 7)
                Text(status == "Partially Working" ? "Partly working" : status).font(MoiType.ui(12, weight: 560)).foregroundStyle(MoiStyle.quiet)
            }.padding(.top, 10)
        }.padding(.bottom, 12)
    }
}
struct ModuleMessage: View {
    var text: String?
    var body: some View {
        if let text, !text.isEmpty {
            Label(text, systemImage: "info.circle").font(MoiType.ui(13)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(MoiStyle.butter.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
