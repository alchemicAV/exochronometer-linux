import SwiftUI
import ExochronometerCore

struct LiveCentsWheelWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            CentsWheelWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { context in
                CentsWheelWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct CentsWheelWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    private let scaling: Int = 23
    private let reference: Double = 432.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CENTS WHEEL  ·  JUST INTONATION")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                Text("A4 = 432 Hz")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Canvas { ctx, size in
                let raw = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
                let tones = raw.filter { tone in
                    if !settings.showFundamentals && tone.isFundamental { return false }
                    if settings.excludedTimeframes.contains(tone.timeframe) { return false }
                    return true
                }
                let positioned = layoutTones(tones, at: date)
                draw(in: &ctx, size: size, positioned: positioned)
            }
        }
        .padding(12)
    }

    private struct PositionedTone {
        let tone: HarmonicTone
        let angle: Double
        let stackLevel: Int
        let remainingLabel: String?
    }

    /// Compute angle / non-overlapping stack level / fade-remaining suffix
    /// for each tone. Mirrors the iOS cents-wheel layout so labels never
    /// pile up at the same radial position.
    private func layoutTones(_ tones: [HarmonicTone], at date: Date) -> [PositionedTone] {
        struct Raw {
            let tone: HarmonicTone
            let angle: Double
            let remaining: TimeInterval?
        }

        let raws: [Raw] = tones.compactMap { tone in
            guard tone.frequency > 0 else { return nil }
            let cents = 1200 * log2(tone.frequency / reference)
            let pitchClass = (cents.truncatingRemainder(dividingBy: 1200) + 1200)
                .truncatingRemainder(dividingBy: 1200)
            let angle = (pitchClass / 1200) * 2 * .pi - .pi / 2
            let remaining = FadeMath.timeUntilOvertoneExit(
                timeframe: tone.timeframe,
                divisions: tone.divisions,
                skip: tone.skip,
                at: date
            )
            return Raw(tone: tone, angle: angle, remaining: remaining)
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

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60        { return "\(Int(s.rounded()))s" }
        if s < 3600      { return "\(Int(s / 60))m" }
        if s < 86400     { return "\(Int(s / 3600))h" }
        if s < 31557600  { return "\(Int(s / 86400))d" }
        return "\(Int(s / 31557600))y"
    }

    private func toneLabel(_ tone: HarmonicTone) -> String {
        let name = compactTF(tone.timeframe)
        return tone.isFundamental ? name : "\(name)\(tone.divisionLabel)"
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

    private func draw(in ctx: inout GraphicsContext, size: CGSize, positioned: [PositionedTone]) {
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
            tick.move(to: CGPoint(x: cx + (r - 4) * CGFloat(cos(angle)), y: cy + (r - 4) * CGFloat(sin(angle))))
            tick.addLine(to: CGPoint(x: cx + (r + 1) * CGFloat(cos(angle)), y: cy + (r + 1) * CGFloat(sin(angle))))
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

            // Anchor on dot side so text extends inward (toward center),
            // never pushing outward past the dot.
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
