import SwiftUI

/// Every state moi's character can show. Each one the app emits is driven by a real event;
/// none is played for decoration. See MOI_DESIGN.md → Character.
enum MoiCharacterState: String, CaseIterable {
    case idle, happy, curious, attention, listening, understanding, working, speaking, success, uncertain, error, permissionRequired, sleeping

    var label: String {
        switch self {
        case .permissionRequired: "Asking permission"
        case .understanding: "Thinking it over"
        default: rawValue.capitalized
        }
    }
}

/// moi: a chubby butter-yellow mochi with a curl, drawn like a sticker from a sketchbook:
/// soft hand-drawn brown outline, crayon hatching, tiny dot eyes, an "ω" mouth, stub paws.
/// Drawn in a unit box so it reads at 16 pt in the sidebar and 180 pt in the introduction.
///
/// `sticker` adds the white die-cut border and soft shadow. `gaze` (-1…1) moves the eyes,
/// e.g. toward the pointer. Motion is event-driven: rare blinks/glances, loops only while
/// listening, working or speaking, nothing with Reduce Motion.
struct MoiCharacter: View {
    enum Pose { case full, peek }
    var state: MoiCharacterState
    var size: CGFloat
    var pose: Pose = .full
    var gaze: CGSize = .zero
    var blink = false
    /// Idle life (blinks, glances, hello wave). The companion's "occasional blinking" setting turns it off.
    var lively = true
    var sticker = false
    /// Bops along (music playing).
    var dancing = false
    /// Shown even when the person has turned off "show moi around the app" (introduction, companion, logo).
    var essential = false
    @AppStorage("moi.color") private var colorName = MoiPalette.butter.rawValue
    @AppStorage("moi.showCharacter") private var showEverywhere = true
    private var palette: MoiPalette { MoiPalette(rawValue: colorName) ?? .butter }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var glance: CGSize = .zero
    @State private var hop: CGFloat = 0
    @State private var squash: CGFloat = 1
    @State private var shake: CGFloat = 0
    @State private var wave: Double = 0
    @State private var phase = false
    @State private var talk = false

    var body: some View {
        if showEverywhere || essential { figure }
    }

    private var figure: some View {
        let s = size
        return ZStack {
            if sticker { stickerBacking(s) }
            curl(s)
            if pose == .full { feet(s) }
            bodyShape(s)
            paws(s)
            face(s)
            props(s)
        }
        .frame(width: s, height: s)
        .rotationEffect(.degrees(tilt), anchor: .bottom)
        .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
        .offset(x: shake * s * 0.03, y: -hop * s)
        .accessibilityHidden(true)
        .task(id: state) { await react(to: state) }
        .task(id: loopKey) { await runLoops() }
        .task { await idleLife() }
    }

    // MARK: Palette (character-only; app tokens live in MoiStyle)

    static let butter = Color(red: 1.0, green: 0.84, blue: 0.42)       // #FFD66B
    static let shade = Color(red: 0.96, green: 0.70, blue: 0.27)       // crayon shadow
    static let light = Color(red: 1.0, green: 0.94, blue: 0.70)        // highlight
    static let outline = Color(red: 0.36, green: 0.23, blue: 0.07)     // warm pencil brown
    static let ink = Color(red: 0.23, green: 0.14, blue: 0.06)         // eyes, mouth
    static let blush = Color(red: 1.0, green: 0.62, blue: 0.55)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let tear = Color(red: 0.55, green: 0.8, blue: 1)

    // MARK: Sticker

    /// The white die-cut border: moi's own silhouette drawn fat in white, with one soft shadow.
    private func stickerBacking(_ s: CGFloat) -> some View {
        let r = bodyRect(s), k = max(3, s * 0.07)
        return ZStack {
            Mochi(rect: r).fill(.white)
            Mochi(rect: r).stroke(.white, style: StrokeStyle(lineWidth: k, lineJoin: .round))
            CurlShape(kind: curlKind).stroke(.white, style: StrokeStyle(lineWidth: max(1.2, s * 0.038) + k, lineCap: .round, lineJoin: .round))
                .frame(width: s * 0.2, height: s * 0.2).rotationEffect(.degrees(curlWiggle), anchor: .bottom).position(x: s * 0.52, y: r.minY - s * 0.08)
            if pose == .full {
                Capsule().fill(.white).frame(width: s * 0.55, height: s * 0.085 + k).position(x: s / 2, y: r.maxY + s * 0.005)
            }
            if state != .success {
                Circle().fill(.white).frame(width: s * 0.1 + k).position(x: r.minX + s * 0.03, y: r.midY + s * 0.1)
                Circle().fill(.white).frame(width: s * 0.1 + k).position(x: r.maxX - s * 0.03, y: r.midY + s * 0.1)
            }
        }
        .shadow(color: .black.opacity(0.32), radius: s * 0.035, x: 0, y: s * 0.025)
    }

    // MARK: Body

    private func bodyRect(_ s: CGFloat) -> CGRect {
        pose == .full ? CGRect(x: s * 0.13, y: s * 0.27, width: s * 0.74, height: s * 0.62)
                      : CGRect(x: s * 0.08, y: s * 0.2, width: s * 0.84, height: s * 0.74)
    }
    private func line(_ s: CGFloat) -> CGFloat { max(1, s * 0.032) }

    @ViewBuilder private func bodyShape(_ s: CGFloat) -> some View {
        let r = bodyRect(s)
        ZStack {
            Mochi(rect: r).fill(palette.body)
            if s >= 36 { Hatching(rect: r).stroke(palette.shade, style: StrokeStyle(lineWidth: max(1, s * 0.018), lineCap: .round)).clipShape(Mochi(rect: r)).opacity(0.6) }
            Mochi(rect: r).fill(palette.shade).mask(Ellipse().frame(width: r.width * 1.3, height: r.height * 0.5).position(x: r.midX + r.width * 0.12, y: r.maxY + r.height * 0.06)).opacity(0.75)
            Ellipse().fill(palette.light).frame(width: r.width * 0.22, height: r.height * 0.12).rotationEffect(.degrees(-25)).position(x: r.minX + r.width * 0.26, y: r.minY + r.height * 0.2)
            // Hand-drawn outline: a main line plus a faint second pass slightly off, like a pencil going over twice.
            Mochi(rect: r).stroke(Self.outline, style: StrokeStyle(lineWidth: line(s), lineCap: .round, lineJoin: .round))
            if s >= 36 { Mochi(rect: r.offsetBy(dx: s * 0.006, dy: -s * 0.004)).stroke(Self.outline.opacity(0.35), lineWidth: line(s) * 0.5) }
        }
    }

    private func curl(_ s: CGFloat) -> some View {
        let r = bodyRect(s)
        return CurlShape(kind: curlKind)
            .stroke(Self.outline, style: StrokeStyle(lineWidth: max(1.2, s * 0.038), lineCap: .round, lineJoin: .round))
            .frame(width: s * 0.2, height: s * 0.2)
            .overlay(alignment: .bottom) {
                if curlKind == .question { Circle().fill(Self.outline).frame(width: s * 0.04).offset(y: s * 0.06) }
            }
            .rotationEffect(.degrees(curlWiggle), anchor: .bottom)
            .position(x: s * 0.5 + s * 0.02, y: r.minY - s * 0.08)
    }

    private func feet(_ s: CGFloat) -> some View {
        let r = bodyRect(s)
        return HStack(spacing: s * 0.17) {
            ForEach(0..<2, id: \.self) { _ in
                Ellipse().fill(palette.body).overlay(Ellipse().stroke(Self.outline, lineWidth: line(s))).frame(width: s * 0.16, height: s * 0.085)
            }
        }.position(x: s / 2, y: r.maxY + s * 0.005)
    }

    /// Little paws, always there (the sketches' characters hold things); they wave, cheer and hold the key.
    private func paws(_ s: CGFloat) -> some View {
        let r = bodyRect(s)
        let up = state == .success
        let holding = state == .permissionRequired
        func paw(_ angle: Double) -> some View {
            Capsule().fill(palette.body).overlay(Capsule().stroke(Self.outline, lineWidth: line(s)))
                .frame(width: s * 0.1, height: s * 0.13).rotationEffect(.degrees(angle))
        }
        return ZStack {
            paw(up ? 150 : holding ? -30 : 25).position(x: r.minX + s * 0.03, y: r.midY + (up ? -s * 0.08 : s * 0.1))
            paw(up ? -150 : holding ? 30 : -25 - wave).position(x: r.maxX - s * 0.03, y: r.midY + (up ? -s * 0.08 : wave != 0 ? -s * 0.02 : s * 0.1))
        }
    }

    // MARK: Face

    private func face(_ s: CGFloat) -> some View {
        let r = bodyRect(s)
        let look = CGSize(width: (gaze.width + glance.width) * s * 0.04, height: (gaze.height + glance.height) * s * 0.03)
        let eyeY = r.minY + r.height * 0.48
        return ZStack {
            HStack(spacing: s * 0.2) { eye(s, left: true); eye(s, left: false) }
                .offset(look).position(x: s / 2, y: eyeY)
            HStack(spacing: s * 0.38) {
                Ellipse().fill(Self.blush.opacity(blushStrength)).frame(width: s * 0.11, height: s * 0.06)
                Ellipse().fill(Self.blush.opacity(blushStrength)).frame(width: s * 0.11, height: s * 0.06)
            }.position(x: s / 2 + look.width * 0.4, y: eyeY + s * 0.085)
            if s >= 22 { mouth(s).position(x: s / 2 + look.width * 0.5, y: eyeY + s * 0.075) }
        }
    }

    @ViewBuilder private func eye(_ s: CGFloat, left: Bool) -> some View {
        let d = max(2, s * 0.075)
        let stroke = StrokeStyle(lineWidth: max(1.1, s * 0.03), lineCap: .round, lineJoin: .round)
        switch eyeKind(left: left) {
        case .dot(let scale):
            ZStack(alignment: .topTrailing) {
                Ellipse().fill(Self.ink).frame(width: d * scale, height: d * 1.12 * scale)
                // Both eyes sparkle when moi is wide-eyed, even if one eye is drawn bigger (curious).
                if s >= 60, Self.wideEyed.contains(state) { Circle().fill(.white).frame(width: d * 0.35 * min(scale, 1.2)).offset(x: -d * 0.1, y: d * 0.12) }
            }
        case .closed: Capsule().fill(Self.ink).frame(width: d * 1.3, height: max(1, s * 0.022))
        case .happy: ArcShape(up: true).stroke(Self.ink, style: stroke).frame(width: d * 1.5, height: d * 0.7)
        case .sleepy: ArcShape(up: false).stroke(Self.ink, style: stroke).frame(width: d * 1.5, height: d * 0.55)
        case .squint: Chevron(pointsRight: left).stroke(Self.ink, style: stroke).frame(width: d * 1.1, height: d * 1.2)
        }
    }

    @ViewBuilder private func mouth(_ s: CGFloat) -> some View {
        let stroke = StrokeStyle(lineWidth: max(1, s * 0.024), lineCap: .round, lineJoin: .round)
        switch mouthKind {
        case .omega: OmegaMouth().stroke(Self.ink, style: stroke).frame(width: s * 0.09, height: s * 0.035)
        case .grin: GrinShape().fill(Self.ink).frame(width: s * 0.1, height: s * 0.055)
        case .open(let o): Ellipse().fill(Self.ink).frame(width: s * 0.05, height: s * 0.055 * o)
        case .flat: Capsule().fill(Self.ink).frame(width: s * 0.06, height: max(1, s * 0.02))
        case .wobble: WobbleShape().stroke(Self.ink, style: stroke).frame(width: s * 0.09, height: s * 0.03)
        }
    }

    // MARK: Props: one small thing per state, only when there's room

    @ViewBuilder private func props(_ s: CGFloat) -> some View {
        let r = bodyRect(s)
        if s >= 40 {
            switch state {
            case .success:
                Sparkle().fill(Self.gold).overlay(Sparkle().stroke(Self.outline, lineWidth: line(s) * 0.6)).frame(width: s * 0.12, height: s * 0.12).position(x: r.maxX + s * 0.04, y: r.minY)
                Sparkle().fill(Self.gold).frame(width: s * 0.07, height: s * 0.07).position(x: r.minX - s * 0.01, y: r.minY + s * 0.04)
            case .sleeping:
                Text("z").font(MoiType.display(s * 0.15, weight: 700)).foregroundStyle(Self.outline.opacity(0.8))
                    .position(x: r.maxX + s * 0.03, y: r.minY - s * (phase ? 0.06 : 0.0))
            case .error:
                Teardrop().fill(Self.tear).overlay(Teardrop().stroke(Self.outline, lineWidth: line(s) * 0.5)).frame(width: s * 0.07, height: s * 0.1)
                    .position(x: r.maxX - s * 0.05, y: r.minY + s * 0.12)
            case .working, .understanding:
                HStack(spacing: s * 0.035) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(Self.outline).frame(width: s * 0.04)
                            .offset(y: phase && !reduceMotion ? -s * 0.03 * CGFloat(i % 2 == 0 ? 1 : -1) : 0)
                    }
                }.position(x: r.maxX + s * 0.03, y: r.minY - s * 0.04)
            case .permissionRequired:
                Image(systemName: "key.fill").font(.system(size: s * 0.12, weight: .bold)).foregroundStyle(Self.gold)
                    .shadow(color: Self.outline, radius: 0, x: 0.5, y: 0.5)
                    .rotationEffect(.degrees(-30)).position(x: r.maxX + s * 0.02, y: r.midY - s * 0.02)
            default: EmptyView()
            }
        }
    }

    // MARK: Expression table

    private enum EyeKind { case dot(CGFloat), closed, happy, sleepy, squint }
    private static let wideEyed: Set<MoiCharacterState> = [.curious, .attention, .listening, .permissionRequired, .uncertain]
    private enum MouthKind { case omega, grin, open(CGFloat), flat, wobble }

    private func eyeKind(left: Bool) -> EyeKind {
        if blink || blinking, ![.happy, .success, .sleeping].contains(state) { return .closed }
        switch state {
        case .idle, .speaking: return .dot(1)
        case .happy: return .happy
        case .success: return .squint
        case .curious: return .dot(left ? 1.2 : 1.0)
        case .attention, .listening, .permissionRequired: return .dot(1.3)
        case .understanding: return left ? .dot(0.8) : .dot(1)
        case .working: return .squint
        case .uncertain: return .dot(left ? 1.25 : 0.8)
        case .error: return .dot(0.85)
        case .sleeping: return .sleepy
        }
    }

    private var mouthKind: MouthKind {
        switch state {
        case .idle, .curious, .happy: .omega
        case .success: .grin
        case .attention, .permissionRequired: .open(0.7)
        case .listening: .open(0.55)
        case .speaking: .open(talk ? 1.0 : 0.35)
        case .working, .understanding: .flat
        case .uncertain, .error: .wobble
        case .sleeping: .open(0.4)
        }
    }

    private var blushStrength: Double {
        switch state {
        case .happy, .success: 0.95
        case .error, .uncertain, .permissionRequired: 0.8 // a little embarrassed
        case .sleeping, .working: 0.4
        default: 0.6
        }
    }

    private var curlKind: CurlShape.Kind {
        switch state {
        case .uncertain: .question
        case .attention, .listening, .permissionRequired: .up
        case .sleeping, .error: .droop
        default: .curl
        }
    }

    private var tilt: Double {
        switch state {
        case .curious: -7
        case .uncertain: 8
        case .listening: -4
        case .sleeping: 3
        default: 0
        }
    }

    private var curlWiggle: Double { state == .listening && phase && !reduceMotion ? 12 : 0 }
    private var loopKey: String { "\(state.rawValue)-\(reduceMotion)-\(dancing)" }

    // MARK: Motion

    /// One-shot reaction when the state changes: anticipation, then action (Luxo Jr.-style acting).
    private func react(to state: MoiCharacterState) async {
        guard !reduceMotion else { return }
        switch state {
        case .success:
            withAnimation(.easeOut(duration: 0.08)) { squash = 0.86 }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { squash = 1.08; hop = 0.12 }
            try? await Task.sleep(for: .milliseconds(240))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { hop = 0; squash = 1 }
        case .error:
            for x in [1.0, -1.0, 0.6, -0.4, 0] {
                withAnimation(.easeInOut(duration: 0.06)) { shake = x }
                try? await Task.sleep(for: .milliseconds(60))
            }
        case .attention, .listening, .permissionRequired:
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { squash = 1.06 }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { squash = 1 }
        default: break
        }
    }

    private func runLoops() async {
        phase = false; talk = false
        guard !reduceMotion else { return }
        if dancing {
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.18)) { hop = 0.05; squash = 1.03 }
                try? await Task.sleep(for: .milliseconds(240))
                withAnimation(.easeIn(duration: 0.2)) { hop = 0; squash = 0.97 }
                try? await Task.sleep(for: .milliseconds(240))
            }
            return
        }
        switch state {
        case .listening, .working, .understanding, .sleeping:
            let beat: Duration = state == .sleeping ? .seconds(1.4) : .milliseconds(380)
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: state == .sleeping ? 1.2 : 0.32)) { phase.toggle() }
                try? await Task.sleep(for: beat)
            }
        case .speaking:
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.1)) { talk.toggle() }
                try? await Task.sleep(for: .milliseconds(Int.random(in: 110...190)))
            }
        default: break
        }
    }

    /// Sparse life while idle: a blink every few seconds and an occasional look around.
    private func idleLife() async {
        guard lively, !reduceMotion, size >= 18 else { return }
        if pose == .full {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { wave = 35 }
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { wave = 0 }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3.5...7)))
            guard !Task.isCancelled else { return }
            blinking = true
            try? await Task.sleep(for: .milliseconds(110))
            blinking = false
            if Int.random(in: 0..<4) == 0, state == .idle {
                withAnimation(.easeInOut(duration: 0.25)) { glance = CGSize(width: [-1, 1].randomElement()!, height: -0.3) }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.25)) { glance = .zero }
            }
        }
    }
}

/// moi's colour, chosen by the person from a small curated set so it always works with the
/// brown pencil outline. Stored in `moi.color`.
enum MoiPalette: String, CaseIterable, Identifiable {
    case butter, peach, mint, sky, lilac, pink, cloud
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    private var rgb: (body: (Double, Double, Double), shade: (Double, Double, Double), light: (Double, Double, Double)) {
        switch self {
        case .butter: ((1.0, 0.84, 0.42), (0.96, 0.70, 0.27), (1.0, 0.94, 0.70))
        case .peach: ((1.0, 0.76, 0.62), (0.95, 0.60, 0.46), (1.0, 0.89, 0.81))
        case .mint: ((0.67, 0.88, 0.71), (0.50, 0.76, 0.57), (0.85, 0.96, 0.87))
        case .sky: ((0.64, 0.81, 1.0), (0.48, 0.66, 0.92), (0.84, 0.92, 1.0))
        case .lilac: ((0.80, 0.73, 0.98), (0.66, 0.58, 0.90), (0.92, 0.88, 1.0))
        case .pink: ((1.0, 0.74, 0.83), (0.94, 0.56, 0.69), (1.0, 0.88, 0.93))
        case .cloud: ((0.95, 0.94, 0.92), (0.82, 0.80, 0.78), (1.0, 1.0, 1.0))
        }
    }
    var body: Color { Color(red: rgb.body.0, green: rgb.body.1, blue: rgb.body.2) }
    var shade: Color { Color(red: rgb.shade.0, green: rgb.shade.1, blue: rgb.shade.2) }
    var light: Color { Color(red: rgb.light.0, green: rgb.light.1, blue: rgb.light.2) }
}

/// Swatches for choosing moi's colour (Settings and the introduction).
struct MoiColorPicker: View {
    @AppStorage("moi.color") private var colorName = MoiPalette.butter.rawValue
    var body: some View {
        HStack(spacing: 10) {
            ForEach(MoiPalette.allCases) { palette in
                Button { colorName = palette.rawValue } label: {
                    Circle().fill(palette.body).frame(width: 24, height: 24)
                        .overlay(Circle().stroke(MoiCharacter.outline.opacity(0.6), lineWidth: 1.5))
                        .padding(3)
                        .overlay(Circle().stroke(colorName == palette.rawValue ? Color.primary : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain).help(palette.name).accessibilityLabel(palette.name).accessibilityAddTraits(colorName == palette.rawValue ? .isSelected : [])
            }
        }
    }
}

// MARK: Shapes

/// Round and squishy, a touch wider than tall, softly flattened where it sits.
private struct Mochi: Shape {
    let rect: CGRect
    func path(in _: CGRect) -> Path {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: x + 0.5 * w, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + 0.56 * h), control1: CGPoint(x: x + 0.86 * w, y: y), control2: CGPoint(x: x + w, y: y + 0.22 * h))
        p.addCurve(to: CGPoint(x: x + 0.5 * w, y: y + h), control1: CGPoint(x: x + w, y: y + 0.92 * h), control2: CGPoint(x: x + 0.8 * w, y: y + h))
        p.addCurve(to: CGPoint(x: x, y: y + 0.56 * h), control1: CGPoint(x: x + 0.2 * w, y: y + h), control2: CGPoint(x: x, y: y + 0.92 * h))
        p.addCurve(to: CGPoint(x: x + 0.5 * w, y: y), control1: CGPoint(x: x, y: y + 0.22 * h), control2: CGPoint(x: x + 0.14 * w, y: y))
        p.closeSubpath()
        return p
    }
}

/// Crayon shading: short diagonal strokes on the shadow side, slightly irregular, always the same.
private struct Hatching: Shape {
    let rect: CGRect
    func path(in _: CGRect) -> Path {
        var p = Path()
        let step = rect.width / 9
        for i in 0..<12 {
            let jitter = CGFloat((i * 37) % 7) / 7 * step * 0.4
            let start = CGPoint(x: rect.minX + rect.width * 0.35 + CGFloat(i) * step * 0.7 + jitter, y: rect.maxY + 2)
            p.move(to: start)
            p.addLine(to: CGPoint(x: start.x + rect.width * 0.32, y: rect.maxY - rect.height * (0.38 + CGFloat(i % 3) * 0.05)))
        }
        return p
    }
}

/// > and < eyes: concentrating, or squeezed shut with joy.
private struct Chevron: Shape {
    let pointsRight: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tip = pointsRight ? r.maxX : r.minX, back = pointsRight ? r.minX : r.maxX
        p.move(to: CGPoint(x: back, y: r.minY)); p.addLine(to: CGPoint(x: tip, y: r.midY)); p.addLine(to: CGPoint(x: back, y: r.maxY))
        return p
    }
}

/// The little cat-like "ω" mouth.
private struct OmegaMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY * 1.5 - r.minY * 0.5))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.75, y: r.maxY * 1.5 - r.minY * 0.5))
        return p
    }
}

/// The curl on moi's head, its signature: curls when content, springs up when alert,
/// bends into a question mark when unsure, droops when sleepy or sorry.
private struct CurlShape: Shape {
    enum Kind { case curl, up, question, droop }
    let kind: Kind
    func path(in r: CGRect) -> Path {
        var p = Path()
        let base = CGPoint(x: r.midX, y: r.maxY)
        p.move(to: base)
        switch kind {
        case .curl:
            p.addCurve(to: CGPoint(x: r.midX + r.width * 0.05, y: r.minY + r.height * 0.15), control1: CGPoint(x: r.midX - r.width * 0.05, y: r.maxY - r.height * 0.4), control2: CGPoint(x: r.midX + r.width * 0.35, y: r.minY + r.height * 0.35))
            p.addCurve(to: CGPoint(x: r.midX - r.width * 0.2, y: r.minY + r.height * 0.35), control1: CGPoint(x: r.midX - r.width * 0.15, y: r.minY), control2: CGPoint(x: r.midX - r.width * 0.3, y: r.minY + r.height * 0.15))
        case .up:
            p.addCurve(to: CGPoint(x: r.midX + r.width * 0.08, y: r.minY), control1: CGPoint(x: r.midX - r.width * 0.06, y: r.midY), control2: CGPoint(x: r.midX + r.width * 0.12, y: r.minY + r.height * 0.3))
        case .question:
            p.move(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.28))
            p.addCurve(to: CGPoint(x: r.midX + r.width * 0.28, y: r.minY + r.height * 0.22), control1: CGPoint(x: r.midX, y: r.midY), control2: CGPoint(x: r.midX + r.width * 0.3, y: r.midY))
            p.addCurve(to: CGPoint(x: r.midX - r.width * 0.25, y: r.minY + r.height * 0.25), control1: CGPoint(x: r.midX + r.width * 0.26, y: r.minY - r.height * 0.1), control2: CGPoint(x: r.midX - r.width * 0.25, y: r.minY - r.height * 0.05))
        case .droop:
            p.addCurve(to: CGPoint(x: r.midX + r.width * 0.42, y: r.midY + r.height * 0.12), control1: CGPoint(x: r.midX, y: r.midY - r.height * 0.1), control2: CGPoint(x: r.midX + r.width * 0.3, y: r.midY - r.height * 0.15))
        }
        return p
    }
}

private struct ArcShape: Shape {
    let up: Bool // ∩ when true, ∪ when false
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: up ? r.maxY : r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: up ? r.maxY : r.minY), control: CGPoint(x: r.midX, y: up ? r.minY - r.height * 0.6 : r.maxY + r.height * 0.6))
        return p
    }
}

private struct GrinShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.8))
        return p
    }
}

private struct WobbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY), control1: CGPoint(x: r.minX + r.width * 0.33, y: r.minY - r.height), control2: CGPoint(x: r.minX + r.width * 0.66, y: r.maxY + r.height))
        return p
    }
}

private struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), k = r.width * 0.12
        p.move(to: CGPoint(x: c.x, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
}

private struct Teardrop: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX * 1.05, y: r.midY), control2: CGPoint(x: r.maxX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX, y: r.maxY), control2: CGPoint(x: r.minX - r.width * 0.05, y: r.midY))
        return p
    }
}

/// moi's wordmark: lowercase "moi" in heavy Bricolage, where the dot of the i is a tiny moi.
struct MoiLogo: View {
    var size: CGFloat = 28
    var color: Color = .primary
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: -size * 0.02) {
            Text("mo").font(MoiType.display(size, weight: 780, width: 92)).foregroundStyle(color)
            Text("\u{0131}").font(MoiType.display(size, weight: 780, width: 92)).foregroundStyle(color)
                .overlay(alignment: .top) {
                    MoiCharacter(state: .happy, size: size * 0.42, pose: .peek, lively: false, essential: true).offset(x: -size * 0.03, y: size * 0.02)
                }
        }
        .accessibilityElement().accessibilityLabel("moi")
    }
}

#if DEBUG
/// Renders the character sheet used for design review (MOI_EXPORT_CHARACTER=<dir>).
@MainActor
enum MoiCharacterSheet {
    static func export(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sheet = VStack(alignment: .leading, spacing: 28) {
            Text("moi · expression sheet").font(MoiType.display(30, weight: 680)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(170), spacing: 18), count: 5), spacing: 22) {
                ForEach(MoiCharacterState.allCases, id: \.self) { state in
                    VStack(spacing: 10) {
                        MoiCharacter(state: state, size: 130, sticker: true, essential: true)
                        Text(state.label).font(MoiType.ui(13, weight: 560)).foregroundStyle(Color.white.opacity(0.75))
                    }.frame(width: 170, height: 175).background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            HStack(alignment: .bottom, spacing: 26) {
                ForEach([16, 20, 28, 40, 64], id: \.self) { size in MoiCharacter(state: .idle, size: CGFloat(size), pose: .peek) }
                ForEach([MoiCharacterState.attention, .happy, .sleeping], id: \.self) { state in MoiCharacter(state: state, size: 28, pose: .peek) }
                Spacer()
                HStack(spacing: 16) { MoiCharacter(state: .idle, size: 90).background(Color(red: 0.91, green: 0.91, blue: 0.93), in: RoundedRectangle(cornerRadius: 16)); MoiCharacter(state: .happy, size: 90, sticker: true) }
            }
        }
        .padding(36).frame(width: 1010).background(Color(red: 0.06, green: 0.06, blue: 0.067))
        // App icon: the sticker moi on an ink tile, 1024 pt (Scripts/make-icon.sh turns it into AppIcon.icns).
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous).fill(Color(red: 0.09, green: 0.09, blue: 0.1)).frame(width: 824, height: 824)
            MoiCharacter(state: .idle, size: 580, sticker: true).offset(y: 24)
        }.frame(width: 1024, height: 1024).padding(0)
        let iconRenderer = ImageRenderer(content: icon)
        if let image = iconRenderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("moi-icon-1024.png"))
        }
        let logoRenderer = ImageRenderer(content: HStack(spacing: 18) { MoiCharacter(state: .happy, size: 120, sticker: true); MoiLogo(size: 96, color: .white) }.padding(40).background(Color(red: 0.06, green: 0.06, blue: 0.067)))
        logoRenderer.scale = 2
        if let image = logoRenderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("moi-logo.png"))
        }
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("moi-expressions.png"))
        }
    }
}
#endif
