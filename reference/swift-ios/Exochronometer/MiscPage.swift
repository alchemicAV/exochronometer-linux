import SwiftUI
import ExochronometerCore

enum MiscMode: String, CaseIterable, Identifiable {
    case phasePortrait
    case centsWheel
    case dissonance
    case chladni
    case spectrogram
    case convergence
    case colorMapping
    case lissajous
    case convergenceSelector

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phasePortrait:       return "PHASE"
        case .centsWheel:          return "CENTS"
        case .dissonance:          return "DISSONANCE"
        case .chladni:             return "CHLADNI"
        case .spectrogram:         return "SPECTROGRAM"
        case .convergence:         return "CHORDS"
        case .colorMapping:        return "COLOR"
        case .lissajous:           return "LISSAJOUS"
        case .convergenceSelector: return "SELECTOR"
        }
    }

    var subtitle: String {
        switch self {
        case .phasePortrait:       return "signal vs derivative · closed orbits = periodic"
        case .centsWheel:          return "Just Intonation  ·  A4 = 432 Hz"
        case .dissonance:          return "Tenney height + Shannon entropy of JI guesses"
        case .chladni:             return "2D membrane modes summed by amplitude"
        case .spectrogram:         return "linear · quarter-moon window · refreshes every 10s"
        case .convergence:         return "time until next angular alignment (live)"
        case .colorMapping:        return "pitch class mapped to closed color wheel via magenta"
        case .lissajous:           return "within-timeframe pairs · sectioned fast → slow"
        case .convergenceSelector: return "all timeframes merged on (divisions × degrees)"
        }
    }
}

struct MiscPage: View {
    @State private var mode: MiscMode = .phasePortrait
    @State private var excludedTimeframes: Set<TimeFrame> = []
    @State private var dissonanceShowGraph: Bool = false

    private let orderedTimeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]
    private let selectorTimeframes: [TimeFrame] = [.minute, .hour, .day, .quarterMoon, .moon, .year]

    /// The hour/day/qtr/moon/year filter applies everywhere except Color,
    /// Convergence, and the Dissonance page while its Graph view is up.
    private var showsTimeframeRow: Bool {
        switch mode {
        case .colorMapping, .convergence:
            return false
        case .dissonance:
            return !dissonanceShowGraph
        default:
            return true
        }
    }

    /// The Selector square gets an extra MIN toggle; every other page keeps
    /// the standard five timeframes.
    private var timeframeButtons: [TimeFrame] {
        mode == .convergenceSelector ? selectorTimeframes : orderedTimeframes
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            modePicker
                .padding(.horizontal, 16)

            if showsTimeframeRow {
                timeframeFilterRow
                    .padding(.horizontal, 16)
            }

            Group {
                switch mode {
                case .phasePortrait:       PhasePortraitView(excludedTimeframes: excludedTimeframes)
                case .centsWheel:          CentsWheelView(excludedTimeframes: excludedTimeframes)
                case .dissonance:          DissonancePanel(excludedTimeframes: excludedTimeframes, showGraph: $dissonanceShowGraph)
                case .chladni:             ChladniView(excludedTimeframes: excludedTimeframes)
                case .spectrogram:         SpectrogramView(excludedTimeframes: excludedTimeframes)
                case .convergence:         ConvergenceView()
                case .colorMapping:        ColorMappingView(excludedTimeframes: excludedTimeframes)
                case .lissajous:           LissajousView(excludedTimeframes: excludedTimeframes)
                case .convergenceSelector: ConvergenceSelectorPanel(excludedTimeframes: excludedTimeframes)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISC ANALYSIS")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
            Text(mode.subtitle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MiscMode.allCases) { m in
                    Button {
                        mode = m
                    } label: {
                        Text(m.label)
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(mode == m ? .black : .white.opacity(0.7))
                            .background(
                                Capsule().fill(mode == m ? Color.white : .clear)
                            )
                            .overlay(
                                Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }

    private var timeframeFilterRow: some View {
        HStack(spacing: 6) {
            ForEach(timeframeButtons, id: \.self) { tf in
                let isExcluded = excludedTimeframes.contains(tf)
                Button {
                    if isExcluded {
                        excludedTimeframes.remove(tf)
                    } else {
                        excludedTimeframes.insert(tf)
                    }
                } label: {
                    Text(shortTimeframeLabel(tf))
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white.opacity(isExcluded ? 0.25 : 0.8))
                        .background(Capsule().fill(.clear))
                        .overlay(
                            Capsule().stroke(.white.opacity(isExcluded ? 0.12 : 0.4), lineWidth: 0.5)
                        )
                }
            }
            Spacer()
        }
    }

    private func shortTimeframeLabel(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON"
        case .quarterMoon: return "QTR"
        case .day:         return "DAY"
        case .hour:        return "HOUR"
        case .minute:      return "MIN"
        }
    }
}

/// Shared filter helper for the four Misc analytical modes.
private func filteredTones(
    at date: Date,
    scaling: Int,
    fundamentalsOff: Bool,
    excludedTimeframes: Set<TimeFrame>
) -> [HarmonicTone] {
    HarmonicAnalysis.activeTones(at: date, scales: [scaling]).filter { tone in
        if excludedTimeframes.contains(tone.timeframe) { return false }
        if fundamentalsOff && tone.isFundamental { return false }
        return true
    }
}

private func shortTimeframeName(_ tf: TimeFrame) -> String {
    switch tf {
    case .year:        return "YR"
    case .moon:        return "MN"
    case .quarterMoon: return "QM"
    case .day:         return "DY"
    case .hour:        return "HR"
    case .minute:      return "MIN"
    }
}

private func toneLabel(_ tone: HarmonicTone) -> String {
    let name = shortTimeframeName(tone.timeframe)
    return tone.isFundamental ? name : "\(name)\(tone.divisionLabel)"
}

// MARK: - Phase Portrait

private struct PhasePortraitView: View {
    let excludedTimeframes: Set<TimeFrame>
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    @State private var normalized: Bool = false
    private let scaling: Int = 23
    private let dayWindowSeconds: Double = 0.030
    private let timeframeOrder: [TimeFrame] = [.year, .moon, .quarterMoon, .day, .hour, .minute]

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let tones = filteredTones(
                at: context.date,
                scaling: scaling,
                fundamentalsOff: fundamentalsOff,
                excludedTimeframes: excludedTimeframes
            )

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    if normalized {
                        drawNormalizedPortrait(in: &ctx, size: size, tones: tones)
                    } else {
                        drawPortrait(in: &ctx, size: size, tones: tones)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("plot of  ( s(t),  ds/dt )")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("clean closed loop  →  periodic chord (small-integer ratios)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("dense filled region  →  quasi-periodic (incommensurate ratios)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(fundamentalsOff ? "fundamentals filtered out (global)" : "fundamentals included")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    if normalized {
                        Text("per-timeframe window  ·  30 ms × cycle / 86400 s")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(10)
                .padding(.top, 18)

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            normalized.toggle()
                        } label: {
                            Text(normalized ? "NORMALIZED" : "STANDARD")
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(normalized ? .black : .white.opacity(0.7))
                                .background(Capsule().fill(normalized ? Color.white : .clear))
                                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
                        }
                    }
                    Spacer()
                }
                .padding(10)

                VStack {
                    Spacer()
                    HStack {
                        closureSection(tones: tones)
                        Spacer()
                    }
                }
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func closureSection(tones: [HarmonicTone]) -> some View {
        if normalized {
            let grouped = Dictionary(grouping: tones, by: { $0.timeframe })
            VStack(alignment: .leading, spacing: 2) {
                ForEach(timeframeOrder, id: \.self) { tf in
                    if let group = grouped[tf], !group.isEmpty {
                        let window = normalizedWindowSeconds(for: tf)
                        let closed = PhasePortraitMath.isLoopClosed(tones: group, windowSeconds: window)
                        let color = HarmonicColor.blendedColor(of: group)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color)
                                .frame(width: 7, height: 7)
                            Text("\(compactTF(tf)): \(closed ? "Closed" : "Open")")
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        } else {
            let closed = PhasePortraitMath.isLoopClosed(tones: tones, windowSeconds: dayWindowSeconds)
            Text("Total: \(closed ? "Closed" : "Open")")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white)
        }
    }

    private func compactTF(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YR"
        case .moon:        return "MN"
        case .quarterMoon: return "QM"
        case .day:         return "DY"
        case .hour:        return "HR"
        case .minute:      return "MIN"
        }
    }

    private func drawPortrait(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 8

        drawAxes(in: &ctx, cx: cx, cy: cy, r: r)
        guard !tones.isEmpty else { return }
        drawCurve(in: &ctx, cx: cx, cy: cy, r: r, tones: tones, windowSeconds: dayWindowSeconds, color: .white.opacity(0.85), lineWidth: 1)
    }

    /// Each timeframe gets its own window so its fundamental traces ~2.9
    /// cycles (matching day at 30 ms). All curves are drawn on the same
    /// axes, each individually peak-normalized, so every timeframe gets
    /// equal visual weight. Per-timeframe color matches the ColorMapping
    /// widget so overlaid curves are identifiable by hue.
    private func drawNormalizedPortrait(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 8

        drawAxes(in: &ctx, cx: cx, cy: cy, r: r)
        guard !tones.isEmpty else { return }

        let grouped = Dictionary(grouping: tones, by: { $0.timeframe })
        for tf in timeframeOrder {
            guard let groupTones = grouped[tf], !groupTones.isEmpty else { continue }
            let window = normalizedWindowSeconds(for: tf)
            let color = HarmonicColor.blendedColor(of: groupTones)
            drawCurve(in: &ctx, cx: cx, cy: cy, r: r, tones: groupTones, windowSeconds: window, color: color, lineWidth: 0.9)
        }
    }

    private func normalizedWindowSeconds(for tf: TimeFrame) -> Double {
        // Reference: day (86400 s cycle) at 30 ms. Scaling cancels out
        // because both day's fundamental and the target's fundamental
        // include the same 2^scaling factor.
        dayWindowSeconds * (tf.cycleDuration / 86400.0)
    }

    private func drawAxes(in ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        var axes = Path()
        axes.move(to: CGPoint(x: cx - r, y: cy))
        axes.addLine(to: CGPoint(x: cx + r, y: cy))
        axes.move(to: CGPoint(x: cx, y: cy - r))
        axes.addLine(to: CGPoint(x: cx, y: cy + r))
        ctx.stroke(axes, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
    }

    private func drawCurve(
        in ctx: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        r: CGFloat,
        tones: [HarmonicTone],
        windowSeconds: Double,
        color: Color,
        lineWidth: CGFloat
    ) {
        let samples = 800
        var sigs: [Double] = []
        var deriv: [Double] = []
        var peakSig: Double = 0
        var peakDeriv: Double = 0

        for i in 0..<samples {
            let t = Double(i) / Double(samples) * windowSeconds
            var s: Double = 0
            var d: Double = 0
            for tone in tones {
                let w = 2 * .pi * tone.frequency
                s += sin(w * t) * tone.amplitude
                d += cos(w * t) * tone.amplitude * w
            }
            sigs.append(s)
            deriv.append(d)
            if abs(s) > peakSig   { peakSig = abs(s) }
            if abs(d) > peakDeriv { peakDeriv = abs(d) }
        }

        guard peakSig > 0, peakDeriv > 0 else { return }
        let sScale = r / CGFloat(peakSig)
        let dScale = r / CGFloat(peakDeriv)

        var path = Path()
        for i in 0..<samples {
            let x = cx + CGFloat(sigs[i]) * sScale
            let y = cy - CGFloat(deriv[i]) * dScale
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
}

// MARK: - Cents Wheel

private struct CentsWheelView: View {
    let excludedTimeframes: Set<TimeFrame>
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    private let scaling: Int = 23
    private let reference: Double = 432.0  // A4 = 432 Hz

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { context in
            let tones = filteredTones(
                at: context.date,
                scaling: scaling,
                fundamentalsOff: fundamentalsOff,
                excludedTimeframes: excludedTimeframes
            )
            let positioned = layoutTones(tones, now: context.date)

            Canvas { ctx, size in
                drawWheel(in: &ctx, size: size, positioned: positioned)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private struct PositionedTone {
        let tone: HarmonicTone
        let angle: Double
        let stackLevel: Int
        let remainingLabel: String?
    }

    /// Compute angle on the wheel, assign a non-overlapping radial stack
    /// level, and (for overtones) compute time-until-fade as a short
    /// suffix like "3m" or "12s".
    private func layoutTones(_ tones: [HarmonicTone], now: Date) -> [PositionedTone] {
        struct Raw {
            let tone: HarmonicTone
            let angle: Double
            let remaining: TimeInterval?
        }

        let raws: [Raw] = tones.compactMap { tone in
            guard tone.frequency > 0 else { return nil }
            let cents = 1200 * log2(tone.frequency / reference)
            let pitchClass = (cents.truncatingRemainder(dividingBy: 1200) + 1200).truncatingRemainder(dividingBy: 1200)
            let angle = (pitchClass / 1200) * 2 * .pi - .pi / 2
            return Raw(tone: tone, angle: angle, remaining: timeRemaining(for: tone, at: now))
        }

        let sorted = raws.sorted { $0.angle < $1.angle }

        var occupied: [(angle: Double, level: Int)] = []
        var out: [PositionedTone] = []
        let clusterThreshold: Double = 0.14   // ~8°

        for raw in sorted {
            var level = 0
            while occupied.contains(where: { $0.level == level && angleDistance($0.angle, raw.angle) < clusterThreshold }) {
                level += 1
            }
            occupied.append((raw.angle, level))
            out.append(PositionedTone(
                tone: raw.tone,
                angle: raw.angle,
                stackLevel: level,
                remainingLabel: raw.remaining.map(formatRemaining)
            ))
        }
        return out
    }

    private func angleDistance(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b)
        if d > .pi { d = 2 * .pi - d }
        return d
    }

    /// Compute how long the overtone will remain above the active threshold.
    /// Returns nil for fundamentals (always active) and for overtones that
    /// are not currently inside an active fade window. Winding-aware.
    private func timeRemaining(for tone: HarmonicTone, at date: Date) -> TimeInterval? {
        FadeMath.timeUntilOvertoneExit(
            timeframe: tone.timeframe,
            divisions: tone.divisions,
            skip: tone.skip,
            at: date
        )
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60        { return "\(Int(s.rounded()))s" }
        if s < 3600      { return "\(Int(s / 60))m" }
        if s < 86400     { return "\(Int(s / 3600))h" }
        if s < 31557600  { return "\(Int(s / 86400))d" }
        return "\(Int(s / 31557600))y"
    }

    private func drawWheel(in ctx: inout GraphicsContext, size: CGSize, positioned: [PositionedTone]) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 30

        var outline = Path()
        outline.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        ctx.stroke(outline, with: .color(.white.opacity(0.3)), lineWidth: 0.6)

        for label in JustIntonation.labels {
            let angle = (label.cents / 1200) * 2 * .pi - .pi / 2
            let lx = cx + (r + 14) * CGFloat(cos(angle))
            let ly = cy + (r + 14) * CGFloat(sin(angle))
            let text = Text(label.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            ctx.draw(text, at: CGPoint(x: lx, y: ly), anchor: .center)

            var tick = Path()
            let tickInner = r - 4
            let tickOuter = r + 1
            tick.move(to: CGPoint(x: cx + tickInner * CGFloat(cos(angle)), y: cy + tickInner * CGFloat(sin(angle))))
            tick.addLine(to: CGPoint(x: cx + tickOuter * CGFloat(cos(angle)), y: cy + tickOuter * CGFloat(sin(angle))))
            ctx.stroke(tick, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
        }

        for entry in positioned {
            let tone = entry.tone
            let angle = entry.angle
            let dotR: CGFloat = tone.isFundamental ? 5 : 3 + CGFloat(tone.amplitude * 2)
            let x = cx + r * CGFloat(cos(angle))
            let y = cy + r * CGFloat(sin(angle))
            let alpha = tone.isFundamental ? 0.95 : tone.amplitude * 0.9
            let dot = CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
            ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(alpha)))

            let labelDist = r - 14 - CGFloat(entry.stackLevel) * 12
            guard labelDist > 8 else { continue }
            let labelX = cx + labelDist * CGFloat(cos(angle))
            let labelY = cy + labelDist * CGFloat(sin(angle))

            // Anchor the text on the side closest to the dot so the text
            // body always extends inward (toward center), never outward
            // past the dot. e.g. dot on right → anchor trailing center,
            // dot on top → anchor top center.
            let anchor = UnitPoint(
                x: 0.5 + CGFloat(cos(angle)) * 0.5,
                y: 0.5 + CGFloat(sin(angle)) * 0.5
            )

            var text = toneLabel(tone)
            if let remaining = entry.remainingLabel {
                text += " · \(remaining)"
            }
            let label = Text(text)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(min(0.85, alpha + 0.1)))
            ctx.draw(label, at: CGPoint(x: labelX, y: labelY), anchor: anchor)
        }
    }
}

// MARK: - Dissonance (Tenney height + Harmonic Entropy)

/// Wraps the Dissonance readout and its cumulative-over-time Graph behind a
/// single GRAPH toggle button, so Graph is a mode of Dissonance rather than
/// its own entry in the page's button bar.
private struct DissonancePanel: View {
    let excludedTimeframes: Set<TimeFrame>
    @Binding var showGraph: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button {
                    showGraph.toggle()
                } label: {
                    Text("GRAPH")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(showGraph ? .black : .white.opacity(0.7))
                        .background(Capsule().fill(showGraph ? Color.white : .clear))
                        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
                }
            }

            if showGraph {
                DissonanceGraphView()
            } else {
                DissonanceView(excludedTimeframes: excludedTimeframes)
            }
        }
    }
}

private struct DissonanceView: View {
    let excludedTimeframes: Set<TimeFrame>
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    private let scaling: Int = 23

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 5.0, paused: false)) { context in
            let tones = filteredTones(
                at: context.date,
                scaling: scaling,
                fundamentalsOff: fundamentalsOff,
                excludedTimeframes: excludedTimeframes
            )
            let pairCount = max(1, tones.count * (tones.count - 1) / 2)

            let tenneyTotal = DissonanceMath.totalTenney(tones)
            let entropyTotal = DissonanceMath.totalEntropy(tones)
            let tenneyPerPair = tenneyTotal / Double(pairCount)
            let entropyPerPair = entropyTotal / Double(pairCount)

            // Meter and big number both display the per-pair average so
            // they track together. Total is shown as subtext for the
            // "raw amount of dissonance" context.
            let rawTenneyNorm = tenneyPerPair / DissonanceCalibration.tenneyMeterMax
            let rawEntropyNorm = entropyPerPair / DissonanceCalibration.entropyMeterMax

            ScrollView {
                VStack(spacing: 28) {
                    measureBlock(
                        title: "TENNEY  DISSONANCE",
                        unit: "TH",
                        perPair: tenneyPerPair,
                        total: tenneyTotal,
                        rawNormalized: rawTenneyNorm,
                        leftLabel: "CONSONANT",
                        rightLabel: "DISSONANT",
                        caption: "per-pair avg of log2(n·d), amplitude-weighted"
                    )

                    measureBlock(
                        title: "HARMONIC  ENTROPY",
                        unit: "HE",
                        perPair: entropyPerPair,
                        total: entropyTotal,
                        rawNormalized: rawEntropyNorm,
                        leftLabel: "CLEAR",
                        rightLabel: "AMBIGUOUS",
                        caption: "per-pair Shannon entropy of JI identity"
                    )

                    Text("\(tones.count) active tones · \(pairCount) pairs")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private func measureBlock(
        title: String,
        unit: String,
        perPair: Double,
        total: Double,
        rawNormalized: Double,
        leftLabel: String,
        rightLabel: String,
        caption: String
    ) -> some View {
        let spilling = rawNormalized > 1.0
        let rawSpillover = spilling ? Int(((rawNormalized - 1.0) * 100).rounded()) : 0
        let spilloverPercent = min(DissonanceCalibration.spilloverDisplayCap, rawSpillover)
        let pegged = spilloverPercent >= DissonanceCalibration.spilloverDisplayCap
        let percent = min(100 + DissonanceCalibration.spilloverDisplayCap, Int((rawNormalized * 100).rounded()))
        return VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(spilling ? .red.opacity(0.9) : .white.opacity(0.55))
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(String(format: "%.3f", perPair))
                    .font(.system(size: 30, weight: .ultraLight, design: .monospaced))
                Text(unit)
                    .font(.system(size: 12, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(spilling ? .red.opacity(0.9) : .white.opacity(0.9))

            Text("Σ \(String(format: "%.2f", total)) \(unit)")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white)

            meter(value: min(1.0, rawNormalized), spilling: spilling)
                .frame(height: 8)

            HStack {
                Text(leftLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                if spilling {
                    Text("SPILLOVER  +\(spilloverPercent)%\(pegged ? "+" : "")")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.red.opacity(0.85))
                }
                Spacer()
                Text(rightLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(caption)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
    }

    private func meter(value: Double, spilling: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                Capsule()
                    .fill(spilling ? Color.red.opacity(0.85) : .white.opacity(0.85))
                    .frame(width: proxy.size.width * CGFloat(max(0, min(1, value))))
            }
        }
    }

}

// MARK: - Color Mapping (closed octave wheel via magenta)

private struct ColorMappingView: View {
    let excludedTimeframes: Set<TimeFrame>
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    private let scaling: Int = 23
    private let orderedTimeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { context in
            let tones = filteredTones(
                at: context.date,
                scaling: scaling,
                fundamentalsOff: fundamentalsOff,
                excludedTimeframes: excludedTimeframes
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    swatch(
                        title: "COMPOSITE",
                        color: blendedColor(tones),
                        count: tones.count,
                        height: 90
                    )

                    Text("PER TIMEFRAME")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 8)

                    ForEach(orderedTimeframes, id: \.self) { tf in
                        let group = tones.filter { $0.timeframe == tf }
                        swatch(
                            title: timeframeLabel(tf),
                            color: blendedColor(group),
                            count: group.count,
                            height: 36
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func swatch(title: String, color: Color, count: Int, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                )
        }
    }

    private func timeframeLabel(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON CYCLE"
        case .quarterMoon: return "1/4 MOON"
        case .day:         return "ONE DAY"
        case .hour:        return "ONE HOUR"
        case .minute:      return "ONE MINUTE"
        }
    }

    private func blendedColor(_ tones: [HarmonicTone]) -> Color {
        HarmonicColor.blendedColor(of: tones)
    }
}

// MARK: - Dissonance Graph (cumulative over time)

private struct DissonanceGraphView: View {
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    @State private var range: DissonanceGraphRange = .oneDay
    @State private var samples: [DissonanceGraphSample] = []
    @State private var loading: Bool = true
    @State private var anchorDate: Date = .distantPast

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                rangePicker

                VStack(spacing: 10) {
                    plot(title: "TENNEY", values: samples.map(\.tenneyNormalized))
                    plot(title: "ENTROPY", values: samples.map(\.entropyNormalized))
                }
            }
            .padding(.horizontal, 4)
            .task(id: taskKey(for: context.date)) {
                await recompute(at: context.date)
            }
        }
    }

    private func taskKey(for date: Date) -> String {
        let bucketSeconds = range.seconds / 240.0
        let bucket = Int(date.timeIntervalSinceReferenceDate / bucketSeconds)
        return "\(bucket)|\(range.rawValue)|\(fundamentalsOff ? 1 : 0)"
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach(DissonanceGraphRange.allCases, id: \.self) { r in
                Button {
                    range = r
                } label: {
                    Text(r.label)
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(range == r ? .black : .white.opacity(0.7))
                        .background(Capsule().fill(range == r ? Color.white : .clear))
                        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func plot(title: String, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Canvas { ctx, size in
                drawGraph(in: &ctx, size: size, values: values)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func drawGraph(in ctx: inout GraphicsContext, size: CGSize, values: [Double]) {
        guard size.width > 0 && size.height > 0 else { return }
        let yMaxRatio = 1.5
        func yFor(_ v: Double) -> CGFloat {
            let clamped = max(0, min(yMaxRatio, v))
            return size.height * (1 - CGFloat(clamped / yMaxRatio))
        }

        for (ratio, opacity) in [(0.5, 0.12), (1.0, 0.25)] {
            let y = yFor(ratio)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.white.opacity(opacity)), lineWidth: 0.5)
        }

        guard !loading, values.count > 1 else {
            let text = Text(loading ? "…computing" : "no data")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        var spilloverFill = Path()
        spilloverFill.move(to: CGPoint(x: 0, y: yFor(1.0)))
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            spilloverFill.addLine(to: CGPoint(x: x, y: yFor(max(1.0, v))))
        }
        spilloverFill.addLine(to: CGPoint(x: size.width, y: yFor(1.0)))
        spilloverFill.closeSubpath()
        ctx.fill(spilloverFill, with: .color(.red.opacity(0.18)))

        var path = Path()
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = yFor(v)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1)

        var nowMark = Path()
        nowMark.move(to: CGPoint(x: size.width - 0.5, y: 0))
        nowMark.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
        ctx.stroke(nowMark, with: .color(.white.opacity(0.45)), lineWidth: 0.5)
    }

    private func recompute(at date: Date) async {
        let includeFundamentals = !fundamentalsOff
        let currentRange = range
        await MainActor.run { loading = true }
        let computed = await Task.detached(priority: .userInitiated) {
            DissonanceGraphSampler.samples(
                endingAt: date,
                range: currentRange,
                includeFundamentals: includeFundamentals
            )
        }.value
        await MainActor.run {
            samples = computed
            anchorDate = date
            loading = false
        }
    }
}

// MARK: - Convergence Selector (all timeframes merged)

private struct ConvergenceSelectorPanel: View {
    let excludedTimeframes: Set<TimeFrame>

    var body: some View {
        // 5Hz is plenty for the combined view — the minute timeframe's
        // fade window spans ~1.8s, so even slow refresh catches the
        // visible transitions. Was 15Hz, dropped 3× for CPU.
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 5.0, paused: false)) { context in
            ConvergenceSelectorChart(
                date: context.date,
                selectedTimeframe: nil,
                excludedTimeframes: excludedTimeframes
            )
            .aspectRatio(0.94, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Lissajous (sectioned by timeframe, fast → slow)

private func gcd(_ a: Int, _ b: Int) -> Int {
    var x = abs(a)
    var y = abs(b)
    while y != 0 {
        (x, y) = (y, x % y)
    }
    return x
}

private struct LissajousPair: Identifiable {
    let a: HarmonicTone
    let b: HarmonicTone
    var id: String { "\(a.id)-vs-\(b.id)" }
}

private struct LissajousView: View {
    let excludedTimeframes: Set<TimeFrame>
    private let scaling: Int = 23
    private let orderedTimeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]

    private var visibleTimeframes: [TimeFrame] {
        orderedTimeframes.filter { !excludedTimeframes.contains($0) }
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { context in
            let pairsByTF = pairsByTimeframe(at: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(visibleTimeframes, id: \.self) { tf in
                        LissajousSection(
                            timeframe: tf,
                            pairs: pairsByTF[tf] ?? []
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    private func pairsByTimeframe(at date: Date) -> [TimeFrame: [LissajousPair]] {
        let tones = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
        let grouped = Dictionary(grouping: tones, by: { $0.timeframe })
        var result: [TimeFrame: [LissajousPair]] = [:]
        for tf in visibleTimeframes {
            let group = grouped[tf] ?? []
            guard group.count >= 2 else {
                result[tf] = []
                continue
            }
            var pairs: [LissajousPair] = []
            for i in 0..<group.count {
                for j in (i + 1)..<group.count {
                    pairs.append(LissajousPair(a: group[i], b: group[j]))
                }
            }
            result[tf] = pairs
        }
        return result
    }
}

private struct LissajousSection: View {
    let timeframe: TimeFrame
    let pairs: [LissajousPair]

    private static let placeholderHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerLabel)
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))

            if pairs.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    .frame(height: Self.placeholderHeight)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(pairs) { pair in
                        LissajousCell(pair: pair)
                    }
                }
            }
        }
    }

    private var headerLabel: String {
        switch timeframe {
        case .year:        return "YEAR"
        case .moon:        return "MOON CYCLE"
        case .quarterMoon: return "1/4 MOON"
        case .day:         return "ONE DAY"
        case .hour:        return "ONE HOUR"
        case .minute:      return "ONE MINUTE"
        }
    }
}

private struct LissajousCell: View {
    let pair: LissajousPair

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                drawCurve(in: &ctx, size: size)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )

            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Frequency ratio in lowest integer terms. A winding tone's frequency
    /// is divisions/skip × fundamental, so the pair ratio is
    /// (aDiv·bSkip):(bDiv·aSkip).
    private var ratio: (m: Int, n: Int) {
        let a = pair.a.divisions * pair.b.skip
        let b = pair.b.divisions * pair.a.skip
        let g = gcd(a, b)
        return (a / g, b / g)
    }

    private var label: String {
        let r = ratio
        return "\(r.m):\(r.n)"
    }

    private func drawCurve(in ctx: inout GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 4

        let (m, n) = ratio

        let samples = 800
        var path = Path()
        for i in 0...samples {
            let theta = Double(i) / Double(samples) * 2 * .pi
            let x = cx + CGFloat(sin(Double(m) * theta)) * r
            let y = cy + CGFloat(sin(Double(n) * theta)) * r
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let amp = pair.a.amplitude * pair.b.amplitude
        let opacity = pair.a.isFundamental && pair.b.isFundamental ? 0.85 : (0.4 + 0.5 * amp)
        ctx.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 0.7)
    }
}

// MARK: - Spectrogram (linear, quarter-moon window)

private final class SpectrogramBuffer: ObservableObject {
    @Published private(set) var frames: [Frame] = []
    private(set) var maxAge: TimeInterval = 60

    struct Frame: Identifiable {
        let id: Date
        let tones: [HarmonicTone]
    }

    /// Linearly spaced samples across the full window.
    func prePopulate(now: Date, scales: [Int], maxAge: TimeInterval, samples: Int = 400) {
        self.maxAge = maxAge
        var built: [Frame] = []
        let denom = max(1, samples - 1)
        let step = maxAge / Double(denom)
        for i in 0..<samples {
            let age = Double(i) * step
            let t = now.addingTimeInterval(-age)
            let tones = HarmonicAnalysis.activeTones(at: t, scales: scales)
            built.append(Frame(id: t, tones: tones))
        }
        frames = built.reversed()
    }
}

private struct SpectrogramView: View {
    let excludedTimeframes: Set<TimeFrame>
    @StateObject private var buffer = SpectrogramBuffer()
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true

    private let scaling: Int = 23
    private let minFreqHz: Double = 0.1
    private let maxFreqHz: Double = 50_000
    /// Quarter-moon window (~7.38 days) — short enough for hour-cycle
    /// activity to read but long enough to span multiple day cycles.
    private let windowSeconds: TimeInterval = 637_860

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.5, paused: false)) { context in
            Canvas { ctx, size in
                drawScope(in: &ctx, size: size, now: context.date)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .task(id: "spectrogram-refresh") {
            buffer.prePopulate(now: Date(), scales: [scaling], maxAge: windowSeconds)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                buffer.prePopulate(now: Date(), scales: [scaling], maxAge: windowSeconds)
            }
        }
    }

    private func drawScope(in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let logMinHz = log10(minFreqHz)
        let logMaxHz = log10(maxFreqHz)
        let hzRange = logMaxHz - logMinHz
        guard hzRange > 0 else { return }

        let axisWidth: CGFloat = 30
        let plotX = axisWidth
        let plotWidth = size.width - axisWidth

        for d in [0.1, 1.0, 10.0, 100.0, 1_000.0, 10_000.0] {
            let y = mapY(d, logMin: logMinHz, range: hzRange, height: size.height)
            let text = Text(decadeLabel(d))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            ctx.draw(text, at: CGPoint(x: axisWidth / 2, y: y), anchor: .center)
        }
        var spine = Path()
        spine.move(to: CGPoint(x: plotX, y: 0))
        spine.addLine(to: CGPoint(x: plotX, y: size.height))
        ctx.stroke(spine, with: .color(.white.opacity(0.2)), lineWidth: 0.5)

        for frame in buffer.frames {
            let age = now.timeIntervalSince(frame.id)
            if age < 0 || age > windowSeconds { continue }
            let xFrac = 1.0 - age / windowSeconds
            let x = plotX + CGFloat(xFrac) * plotWidth

            for tone in frame.tones {
                if excludedTimeframes.contains(tone.timeframe) { continue }
                guard tone.frequency >= minFreqHz, tone.frequency <= maxFreqHz else { continue }
                if fundamentalsOff && tone.isFundamental { continue }
                let y = mapY(tone.frequency, logMin: logMinHz, range: hzRange, height: size.height)
                let dotR: CGFloat = tone.isFundamental ? 1.4 : 1.1
                let alpha = tone.isFundamental ? 0.5 : tone.amplitude * 0.85
                let dot = CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
                ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(alpha)))
            }
        }

        var cursor = Path()
        cursor.move(to: CGPoint(x: size.width - 1, y: 0))
        cursor.addLine(to: CGPoint(x: size.width - 1, y: size.height))
        ctx.stroke(cursor, with: .color(.white.opacity(0.4)), lineWidth: 0.5)

        let day: Double = 86_400
        let timeMarkers: [(Double, String)] = [
            (0, "now"),
            (day, "1d"),
            (2 * day, "2d"),
            (3 * day, "3d"),
            (4 * day, "4d"),
            (5 * day, "5d"),
            (6 * day, "6d"),
            (7 * day, "7d"),
        ]
        for (age, label) in timeMarkers {
            if age > windowSeconds + 1 { continue }
            let xFrac = 1.0 - age / windowSeconds
            let x = plotX + CGFloat(xFrac) * plotWidth
            let text = Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            ctx.draw(text, at: CGPoint(x: x, y: size.height - 6), anchor: .center)
        }
    }

    private func mapY(_ freq: Double, logMin: Double, range: Double, height: CGFloat) -> CGFloat {
        let frac = (log10(freq) - logMin) / range
        return height * (1.0 - CGFloat(frac))
    }

    private func decadeLabel(_ value: Double) -> String {
        if value >= 1_000 { return "\(Int(value / 1_000))k" }
        if value >= 1     { return "\(Int(value))" }
        return String(format: "%g", value)
    }
}

// MARK: - Chladni

private struct ChladniView: View {
    let excludedTimeframes: Set<TimeFrame>
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    private let scaling: Int = 23

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
            let all = HarmonicAnalysis.activeTones(at: context.date, scales: [scaling])
                .filter { !excludedTimeframes.contains($0.timeframe) }
            let tones = fundamentalsOff ? all.filter { !$0.isFundamental } : all

            Canvas { ctx, size in
                drawPlate(in: &ctx, size: size, tones: tones)
            }
            .background(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func drawPlate(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let side = min(size.width, size.height)
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        let pixelStep: CGFloat = 4

        let cells = Int(side / pixelStep)
        guard cells > 0 else { return }

        let assignedModes: [(m: Int, n: Int, amp: Double)] = tones.map { tone in
            let m = modeIndex(for: tone.timeframe)
            let n = tone.divisions
            return (m: m, n: n, amp: tone.amplitude)
        }

        var maxAbs: Double = 0
        var grid: [[Double]] = Array(repeating: Array(repeating: 0, count: cells), count: cells)
        for row in 0..<cells {
            let y = Double(row) / Double(cells - 1)
            for col in 0..<cells {
                let x = Double(col) / Double(cells - 1)
                var u: Double = 0
                for mode in assignedModes {
                    if mode.amp < 0.01 { continue }
                    u += mode.amp * sin(Double(mode.m) * .pi * x) * sin(Double(mode.n) * .pi * y)
                }
                grid[row][col] = u
                let a = abs(u)
                if a > maxAbs { maxAbs = a }
            }
        }

        guard maxAbs > 0 else { return }

        for row in 0..<cells {
            for col in 0..<cells {
                let u = grid[row][col]
                let intensity = abs(u) / maxAbs
                let alpha = pow(intensity, 0.6)
                let cellRect = CGRect(
                    x: originX + CGFloat(col) * pixelStep,
                    y: originY + CGFloat(row) * pixelStep,
                    width: pixelStep,
                    height: pixelStep
                )
                ctx.fill(Path(cellRect), with: .color(.white.opacity(alpha * 0.9)))
            }
        }
    }

    private func modeIndex(for tf: TimeFrame) -> Int {
        switch tf {
        case .year:        return 1
        case .moon:        return 2
        case .quarterMoon: return 3
        case .day:         return 4
        case .hour:        return 5
        case .minute:      return 6
        }
    }
}

// MARK: - Convergence

private struct ConvergenceView: View {
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true

    private static let lookahead: TimeInterval = 30 * 86400 // 1 month
    private static let maxResults = 40

    @State private var current: [ChordMatch] = []
    @State private var events: [ChordEvent] = []
    @State private var loading: Bool = true
    @State private var anchorDate: Date = .distantPast

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0)) { context in
            content(at: context.date)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                currentSection(now: date)
                upcomingSection(now: date)
            }
            .padding(.vertical, 8)
        }
        .task(id: recomputeKey(for: date)) {
            await recompute(at: date)
        }
    }

    private func recomputeKey(for date: Date) -> String {
        let bucket = Int(date.timeIntervalSinceReferenceDate / 300)
        return "\(bucket)|\(fundamentalsOff ? 1 : 0)|H"
    }

    @ViewBuilder
    private func currentSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            if loading {
                Text("…computing")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else if current.isEmpty {
                Text("no recognized chord active")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(current.prefix(5), id: \.id) { match in
                    currentRow(match)
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CROSS-TIMEFRAME CONVERGENCES")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("next 30 days  ·  nearest first")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 4)
            if loading {
                Text("…computing")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else if events.isEmpty {
                Text("none predicted in window")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(events, id: \.id) { event in
                    upcomingRow(event, now: now)
                }
            }
        }
    }

    private func currentRow(_ match: ChordMatch) -> some View {
        HStack {
            Text(match.pattern.abbreviation)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
            Text(signatureText(match.tones.map {
                ChordEvent.ToneSignature(timeframe: $0.timeframe, divisions: $0.divisions, skip: $0.skip)
            }))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("fit \(String(format: "%.1f", match.fitCents))¢")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func upcomingRow(_ event: ChordEvent, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(event.pattern.abbreviation)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                Text(signatureText(event.toneSignature))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(timeUntil(event.startTime, from: now))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            HStack(spacing: 10) {
                Text("fit \(String(format: "%.1f", event.fitCents))¢")
                Text("dur \(durationText(event.endTime.timeIntervalSince(event.startTime)))")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func signatureText(_ sig: [ChordEvent.ToneSignature]) -> String {
        sig.map { compactTF($0.timeframe) + ":" + $0.divisionLabel }
            .joined(separator: " · ")
    }

    private func compactTF(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YR"
        case .moon:        return "MN"
        case .quarterMoon: return "QM"
        case .day:         return "DY"
        case .hour:        return "HR"
        case .minute:      return "MIN"
        }
    }

    private func timeUntil(_ d: Date, from now: Date) -> String {
        let s = d.timeIntervalSince(now)
        return durationText(max(0, s))
    }

    private func durationText(_ s: TimeInterval) -> String {
        if s < 60 { return String(format: "%.0fs", s) }
        if s < 3600 {
            return String(format: "%.0fm", floor(s / 60))
        }
        if s < 86400 {
            let h = floor(s / 3600)
            let m = floor(s.truncatingRemainder(dividingBy: 3600) / 60)
            return String(format: "%.0fh%.0fm", h, m)
        }
        let d = floor(s / 86400)
        let h = floor(s.truncatingRemainder(dividingBy: 86400) / 3600)
        return String(format: "%.0fd%.0fh", d, h)
    }

    private func recompute(at date: Date) async {
        await MainActor.run { loading = true }
        let includeFundamentals = !fundamentalsOff
        // iOS doesn't have per-widget settings, so the hour-exclusion
        // default is hardcoded here to match the Mac default.
        let excludeHourly = true
        let upcoming = await Task.detached(priority: .userInitiated) {
            ChordProjector.upcoming(
                from: date,
                lookahead: Self.lookahead,
                includeFundamentals: includeFundamentals,
                crossTimeframeOnly: true,
                excludeHourly: excludeHourly,
                patterns: ChordCatalog.chords,
                maxResults: Self.maxResults
            )
        }.value
        let nowMatches = await Task.detached(priority: .userInitiated) {
            ChordProjector.current(
                at: date,
                includeFundamentals: includeFundamentals,
                excludeHourly: excludeHourly,
                patterns: ChordCatalog.chords
            )
        }.value
        await MainActor.run {
            self.events = upcoming
            self.current = nowMatches
            self.anchorDate = date
            self.loading = false
        }
    }
}
