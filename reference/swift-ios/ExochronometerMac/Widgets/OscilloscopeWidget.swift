import SwiftUI
import ExochronometerCore

struct LiveOscilloscopeWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            OscilloscopeWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                OscilloscopeWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct OscilloscopeWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    private let windowSeconds: Double = 0.030

    private var assignments: [ToneAssignment] {
        [
            ToneAssignment(timeframe: .hour,        scale: 23),
            ToneAssignment(timeframe: .day,         scale: 26),
            ToneAssignment(timeframe: .quarterMoon, scale: 28),
            ToneAssignment(timeframe: .moon,        scale: 29),
            ToneAssignment(timeframe: .year,        scale: 29),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMPOSITE WAVEFORM")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))

            Canvas { ctx, size in
                let raw = HarmonicAnalysis.activeTones(at: date, assignments: assignments)
                let tones = raw.filter { tone in
                    if !settings.showFundamentals && tone.isFundamental { return false }
                    if settings.excludedTimeframes.contains(tone.timeframe) { return false }
                    return true
                }
                draw(in: &ctx, size: size, tones: tones)
            }
        }
        .padding(12)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        var center = Path()
        center.move(to: CGPoint(x: 0, y: size.height / 2))
        center.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.stroke(center, with: .color(.white.opacity(0.1)), lineWidth: 0.5)

        guard !tones.isEmpty else { return }

        let samples = max(1, Int(size.width))
        var values: [Double] = Array(repeating: 0, count: samples)
        var peak: Double = 0

        for i in 0..<samples {
            let t = Double(i) / Double(samples) * windowSeconds
            var s: Double = 0
            for tone in tones {
                s += sin(2.0 * .pi * tone.frequency * t) * tone.amplitude
            }
            values[i] = s
            if abs(s) > peak { peak = abs(s) }
        }

        guard peak > 0 else { return }
        let scale = (size.height / 2 - 4) / peak

        var wave = Path()
        for i in 0..<samples {
            let x = CGFloat(i)
            let y = size.height / 2 - CGFloat(values[i] * scale)
            if i == 0 { wave.move(to: CGPoint(x: x, y: y)) }
            else      { wave.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(wave, with: .color(.white.opacity(0.85)), lineWidth: 1)
    }
}
