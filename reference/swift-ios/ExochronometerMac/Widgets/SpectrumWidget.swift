import SwiftUI
import ExochronometerCore

/// Octave-scaling mode for the harmonic spectrum, mirroring the iOS
/// Harmonic Analysis page. `lo`/`hi` shift every timeframe by a uniform
/// 2^23 / 2^26; `merged` gives each timeframe the smallest scale that
/// lands its fundamental + overtones in the audible band (so the tones
/// from different cycles overlap into one readable spectrum).
enum SpectrumScaleMode: String, Codable, CaseIterable, Sendable {
    case lo
    case hi
    case merged

    var assignments: [ToneAssignment] {
        switch self {
        case .lo:
            return TimeFrame.allCases.filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: 23) }
        case .hi:
            return TimeFrame.allCases.filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: 26) }
        case .merged:
            return [
                ToneAssignment(timeframe: .hour,        scale: 23),
                ToneAssignment(timeframe: .day,         scale: 26),
                ToneAssignment(timeframe: .quarterMoon, scale: 28),
                ToneAssignment(timeframe: .moon,        scale: 29),
                ToneAssignment(timeframe: .year,        scale: 29),
            ]
        }
    }

    /// Short label for the settings segmented control.
    var label: String {
        switch self {
        case .lo:     return "2^23"
        case .hi:     return "2^26"
        case .merged: return "MERGED"
        }
    }

    /// Caption shown in the widget header describing the active scaling.
    var caption: String {
        switch self {
        case .lo:     return "× 2^23"
        case .hi:     return "× 2^26"
        case .merged: return "HR:23 · DY:26 · QM:28 · MN/YR:29"
        }
    }

    /// Only merged mixes scales across timeframes, so only it labels each
    /// tone with its own octave (@23, @26, @28, @29).
    var showScaleSuffix: Bool { self == .merged }

    var minFreqHz: Double {
        switch self {
        case .lo:     return 0.1
        case .hi:     return 1
        case .merged: return 15   // year fundamental ~17 Hz; cut empty sub-15 Hz band
        }
    }

    var maxFreqHz: Double {
        switch self {
        case .lo:     return 50_000
        case .hi:     return 200_000
        case .merged: return 50_000
        }
    }
}

struct LiveSpectrumWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            SpectrumWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: false)) { context in
                SpectrumWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct SpectrumWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    // Frequency window follows the active scale mode (lo/hi shift tones
    // out of the merged band, so each mode widens the window to keep them
    // visible). `useLogScale` only controls log-vs-linear mapping.
    private var minFreqHz: Double { settings.spectrumScaleMode.minFreqHz }
    private var maxFreqHz: Double { settings.spectrumScaleMode.maxFreqHz }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HARMONIC SPECTRUM")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(settings.spectrumScaleMode.caption)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Canvas { ctx, size in
                let assignments = settings.spectrumScaleMode.assignments
                let raw = HarmonicAnalysis.activeTones(at: date, assignments: assignments)
                let filtered = raw.filter { tone in
                    if !settings.showFundamentals && tone.isFundamental { return false }
                    if settings.excludedTimeframes.contains(tone.timeframe) { return false }
                    return true
                }
                draw(in: &ctx, size: size, tones: filtered)
            }
        }
        .padding(12)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let useLog = settings.useLogScale
        // Pre-compute axis params once per draw.
        let logMin = log10(minFreqHz)
        let logRange = log10(maxFreqHz) - logMin
        let linearRange = maxFreqHz - minFreqHz
        guard (useLog ? logRange : linearRange) > 0 else { return }

        let axisWidth: CGFloat = 38
        let baselineX: CGFloat = axisWidth + 6
        let maxBarWidth = max(40, size.width - baselineX - 120)
        let labelX = baselineX + maxBarWidth + 8

        func yFor(_ freq: Double) -> CGFloat {
            if useLog {
                let frac = (log10(freq) - logMin) / logRange
                return size.height * (1.0 - CGFloat(frac))
            } else {
                let frac = (freq - minFreqHz) / linearRange
                return size.height * (1.0 - CGFloat(frac))
            }
        }

        // Audible band
        let yLo = yFor(20)
        let yHi = yFor(20_000)
        let band = CGRect(x: baselineX, y: yHi, width: size.width - baselineX, height: yLo - yHi)
        ctx.fill(Path(band), with: .color(.white.opacity(0.04)))

        // Gridlines + axis labels
        let tickValues = useLog
            ? decadeValues(min: minFreqHz, max: maxFreqHz)
            : linearTickValues(min: minFreqHz, max: maxFreqHz, count: 6)
        for v in tickValues {
            let y = yFor(v)
            var line = Path()
            line.move(to: CGPoint(x: baselineX, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)

            let label = Text(decadeLabel(v))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            ctx.draw(label, at: CGPoint(x: 18, y: y), anchor: .center)
        }
        var spine = Path()
        spine.move(to: CGPoint(x: baselineX, y: 0))
        spine.addLine(to: CGPoint(x: baselineX, y: size.height))
        ctx.stroke(spine, with: .color(.white.opacity(0.3)), lineWidth: 0.5)

        // Tone bars
        for tone in tones {
            guard tone.frequency >= minFreqHz, tone.frequency <= maxFreqHz else { continue }
            let y = yFor(tone.frequency)
            let length = CGFloat(tone.amplitude) * maxBarWidth

            var bar = Path()
            bar.move(to: CGPoint(x: baselineX, y: y))
            bar.addLine(to: CGPoint(x: baselineX + length, y: y))

            let color: Color = tone.isFundamental ? .white : .white.opacity(0.8)
            let lineWidth: CGFloat = tone.isFundamental ? 1.4 : 0.8
            ctx.stroke(bar, with: .color(color), lineWidth: lineWidth)

            let dotR: CGFloat = 1.5 + CGFloat(tone.amplitude) * 2
            let dot = CGRect(
                x: baselineX + length - dotR, y: y - dotR,
                width: dotR * 2, height: dotR * 2
            )
            ctx.fill(Path(ellipseIn: dot), with: .color(color))

            let prefix = compactName(tone.timeframe)
            let base = tone.isFundamental ? prefix : "\(prefix)×\(tone.divisionLabel)"
            let scaleSuffix = settings.spectrumScaleMode.showScaleSuffix ? " @\(tone.scaling)" : ""
            let label = Text("\(base)\(scaleSuffix)  ·  \(FrequencyMath.format(tone.frequency))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(tone.isFundamental ? 0.75 : 0.55))
            ctx.draw(label, at: CGPoint(x: labelX, y: y), anchor: .leading)
        }
    }

    private func decadeValues(min: Double, max: Double) -> [Double] {
        var n = Int(floor(log10(min)))
        var values: [Double] = []
        while pow(10.0, Double(n)) < min - 1e-12 { n += 1 }
        while Double(n) <= log10(max) + 1e-12 {
            values.append(pow(10.0, Double(n)))
            n += 1
        }
        return values
    }

    /// Evenly-spaced ticks across [min, max] for the linear scale.
    /// Includes both endpoints.
    private func linearTickValues(min: Double, max: Double, count: Int) -> [Double] {
        let n = Swift.max(2, count)
        let step = (max - min) / Double(n - 1)
        return (0..<n).map { min + Double($0) * step }
    }

    private func decadeLabel(_ value: Double) -> String {
        if value >= 1_000_000 { return "\(Int(value / 1_000_000))M" }
        if value >= 1_000     { return "\(Int(value / 1_000))k" }
        if value >= 1         { return "\(Int(value))" }
        return String(format: "%g", value)
    }

    private func compactName(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YR"
        case .moon:        return "MN"
        case .quarterMoon: return "QM"
        case .day:         return "DY"
        case .hour:        return "HR"
        case .minute:      return "MIN"
        }
    }
}
