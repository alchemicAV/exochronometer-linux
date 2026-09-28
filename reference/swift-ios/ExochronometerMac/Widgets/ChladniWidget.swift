import SwiftUI
import ExochronometerCore

struct LiveChladniWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            ChladniWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
                ChladniWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct ChladniWidgetView: View {
    let date: Date
    let settings: WidgetSettings
    private let scaling: Int = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHLADNI")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))

            Canvas { ctx, size in
                let raw = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
                let tones = raw.filter { tone in
                    if !settings.showFundamentals && tone.isFundamental { return false }
                    if settings.excludedTimeframes.contains(tone.timeframe) { return false }
                    return true
                }
                draw(in: &ctx, size: size, tones: tones)
            }
            .background(Color.black)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .padding(12)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, tones: [HarmonicTone]) {
        let side = min(size.width, size.height)
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        let pixelStep: CGFloat = 4
        let cells = Int(side / pixelStep)
        guard cells > 0 else { return }

        let modes: [(m: Int, n: Int, amp: Double)] = tones.map {
            (m: modeIndex(for: $0.timeframe), n: $0.divisions, amp: $0.amplitude)
        }

        var maxAbs: Double = 0
        var grid: [[Double]] = Array(repeating: Array(repeating: 0, count: cells), count: cells)
        for row in 0..<cells {
            let y = Double(row) / Double(cells - 1)
            for col in 0..<cells {
                let x = Double(col) / Double(cells - 1)
                var u: Double = 0
                for mode in modes where mode.amp >= 0.01 {
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
                let intensity = abs(grid[row][col]) / maxAbs
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
