import SwiftUI
import ExochronometerCore

struct LiveLissajousWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            LissajousWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { context in
                LissajousWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct LissajousWidgetView: View {
    let date: Date
    let settings: WidgetSettings
    private let scaling: Int = 23
    private let orderedTimeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]

    var body: some View {
        let pairs = pairsByTimeframe()

        CaptureAwareScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LISSAJOUS")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))

                ForEach(orderedTimeframes, id: \.self) { tf in
                    section(for: tf, pairs: pairs[tf] ?? [])
                }
            }
            .padding(12)
        }
    }

    private func section(for tf: TimeFrame, pairs: [Pair]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerLabel(for: tf))
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))

            if pairs.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    .frame(height: 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(pairs) { pair in
                        cell(pair)
                    }
                }
            }
        }
    }

    private func cell(_ pair: Pair) -> some View {
        VStack(spacing: 3) {
            Canvas { ctx, size in drawCurve(in: &ctx, size: size, pair: pair) }
                .aspectRatio(1, contentMode: .fit)
                .background(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.15), lineWidth: 0.5))

            Text(label(for: pair))
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// Frequency ratio in lowest integer terms. A winding tone's frequency
    /// is divisions/skip × fundamental, so the pair ratio is
    /// (aDiv·bSkip):(bDiv·aSkip).
    private func ratio(for pair: Pair) -> (m: Int, n: Int) {
        let a = pair.a.divisions * pair.b.skip
        let b = pair.b.divisions * pair.a.skip
        let g = gcd(a, b)
        return (a / g, b / g)
    }

    private func drawCurve(in ctx: inout GraphicsContext, size: CGSize, pair: Pair) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r = min(size.width, size.height) / 2 - 4
        let (m, n) = ratio(for: pair)
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

    private func label(for pair: Pair) -> String {
        let r = ratio(for: pair)
        return "\(r.m):\(r.n)"
    }

    private func headerLabel(for tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON CYCLE"
        case .quarterMoon: return "1/4 MOON"
        case .day:         return "ONE DAY"
        case .hour:        return "ONE HOUR"
        case .minute:      return "ONE MINUTE"
        }
    }

    private struct Pair: Identifiable {
        let a: HarmonicTone
        let b: HarmonicTone
        var id: String { "\(a.id)-vs-\(b.id)" }
    }

    private func pairsByTimeframe() -> [TimeFrame: [Pair]] {
        let raw = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
        let tones = raw.filter { tone in
            if !settings.showFundamentals && tone.isFundamental { return false }
            if settings.excludedTimeframes.contains(tone.timeframe) { return false }
            return true
        }
        let grouped = Dictionary(grouping: tones, by: { $0.timeframe })
        var result: [TimeFrame: [Pair]] = [:]
        for tf in orderedTimeframes {
            let group = grouped[tf] ?? []
            guard group.count >= 2 else {
                result[tf] = []
                continue
            }
            var pairs: [Pair] = []
            for i in 0..<group.count {
                for j in (i + 1)..<group.count {
                    pairs.append(Pair(a: group[i], b: group[j]))
                }
            }
            result[tf] = pairs
        }
        return result
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }
}
