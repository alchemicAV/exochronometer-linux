import SwiftUI
import ExochronometerCore

struct LivePhasePortraitWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            PhasePortraitWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                PhasePortraitWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct PhasePortraitWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    private let scaling: Int = 23
    private let dayWindowSeconds: Double = 0.030
    private let timeframeOrder: [TimeFrame] = [.year, .moon, .quarterMoon, .day, .hour, .minute]

    var body: some View {
        let raw = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
        let tones = raw.filter { tone in
            if !settings.showFundamentals && tone.isFundamental { return false }
            if settings.excludedTimeframes.contains(tone.timeframe) { return false }
            return true
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(settings.normalized ? "PHASE PORTRAIT  ·  NORMALIZED" : "PHASE PORTRAIT  ·  STANDARD")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))

            Canvas { ctx, size in
                if settings.normalized {
                    drawNormalized(in: &ctx, size: size, tones: tones)
                } else {
                    drawStandard(in: &ctx, size: size, tones: tones)
                }
            }

            closureSection(tones: tones)
        }
        .padding(12)
    }

    @ViewBuilder
    private func closureSection(tones: [HarmonicTone]) -> some View {
        if settings.normalized {
            let grouped = Dictionary(grouping: tones, by: { $0.timeframe })
            let topRow: [TimeFrame] = [.year, .moon].filter { (grouped[$0]?.isEmpty == false) }
            let bottomRow: [TimeFrame] = [.quarterMoon, .day, .hour, .minute].filter { (grouped[$0]?.isEmpty == false) }
            VStack(spacing: 3) {
                if !topRow.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(topRow, id: \.self) { tf in
                            closureLabel(tf: tf, group: grouped[tf] ?? [])
                        }
                    }
                }
                if !bottomRow.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(bottomRow, id: \.self) { tf in
                            closureLabel(tf: tf, group: grouped[tf] ?? [])
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            let closed = PhasePortraitMath.isLoopClosed(tones: tones, windowSeconds: dayWindowSeconds)
            Text("Total: \(closed ? "Closed" : "Open")")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func closureLabel(tf: TimeFrame, group: [HarmonicTone]) -> some View {
        let window = dayWindowSeconds * (tf.cycleDuration / 86400.0)
        let closed = PhasePortraitMath.isLoopClosed(tones: group, windowSeconds: window)
        let color = HarmonicColor.blendedColor(of: group)
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(compactTF(tf)): \(closed ? "Closed" : "Open")")
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

    private func drawStandard(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 8
        drawAxes(in: &ctx, cx: cx, cy: cy, r: r)
        guard !tones.isEmpty else { return }
        drawCurve(in: &ctx, cx: cx, cy: cy, r: r, tones: tones, windowSeconds: dayWindowSeconds, color: .white.opacity(0.85), lineWidth: 1)
    }

    private func drawNormalized(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 8
        drawAxes(in: &ctx, cx: cx, cy: cy, r: r)
        guard !tones.isEmpty else { return }

        let grouped = Dictionary(grouping: tones, by: { $0.timeframe })
        for tf in timeframeOrder {
            guard let group = grouped[tf], !group.isEmpty else { continue }
            let window = dayWindowSeconds * (tf.cycleDuration / 86400.0)
            let color = HarmonicColor.blendedColor(of: group)
            drawCurve(in: &ctx, cx: cx, cy: cy, r: r, tones: group, windowSeconds: window, color: color, lineWidth: 0.9)
        }
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
        cx: CGFloat, cy: CGFloat, r: CGFloat,
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
