import SwiftUI
import ExochronometerCore

/// History view of harmonic activity over the past quarter-moon window.
/// In Snapshot mode, "now" is the pinned snapshot's timestamp and the
/// window extends back from there.
struct LiveSpectrogramWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        SpectrogramWidgetView(referenceDate: snapshotDate, settings: settings)
    }
}

private final class SpectrogramBuffer: ObservableObject {
    @Published private(set) var frames: [Frame] = []
    private(set) var maxAge: TimeInterval = 60
    private(set) var referenceDate: Date = .now

    struct Frame: Identifiable {
        let id: Date
        let tones: [HarmonicTone]
    }

    func prePopulate(now: Date, scales: [Int], maxAge: TimeInterval, samples: Int = 400) {
        self.maxAge = maxAge
        self.referenceDate = now
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

struct SpectrogramWidgetView: View {
    let referenceDate: Date?
    let settings: WidgetSettings

    @StateObject private var buffer = SpectrogramBuffer()
    @Environment(\.exoCaptureMode) private var isCapturing
    private let scaling: Int = 23
    private let minFreqHz: Double = 0.1
    private let maxFreqHz: Double = 50_000
    private let windowSeconds: TimeInterval = 637_860 // ~quarter moon

    var body: some View {
        // ImageRenderer doesn't drive `.task`, so the buffer stays empty
        // during a capture and the canvas renders axes-only. Build a
        // synchronous frame list when in capture mode and pass it
        // through to the drawing routine.
        let captureFrames: [SpectrogramBuffer.Frame]? = isCapturing
            ? SpectrogramWidgetView.buildFrames(
                now: referenceDate ?? Date(),
                scales: [scaling],
                maxAge: windowSeconds
            )
            : nil

        return VStack(alignment: .leading, spacing: 6) {
            Text("SPECTROGRAM  ·  QUARTER-MOON WINDOW")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))

            if referenceDate == nil {
                SwiftUI.TimelineView(.animation(minimumInterval: 0.5, paused: false)) { ctx in
                    canvas(now: ctx.date, frames: captureFrames ?? buffer.frames)
                }
            } else {
                canvas(now: referenceDate ?? .now, frames: captureFrames ?? buffer.frames)
            }
        }
        .padding(12)
        .task(id: refreshTaskID) {
            guard !isCapturing else { return }
            await refreshBuffer()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                await refreshBuffer()
            }
        }
    }

    private var refreshTaskID: String {
        if let d = referenceDate { return "snap-\(d.timeIntervalSince1970)" }
        return "live"
    }

    private func refreshBuffer() async {
        let now = referenceDate ?? Date()
        buffer.prePopulate(now: now, scales: [scaling], maxAge: windowSeconds)
    }

    /// Pure-function variant of `SpectrogramBuffer.prePopulate` — returns
    /// frames inline so callers without the live ObservableObject can
    /// compute the same data synchronously (e.g. ImageRenderer captures).
    fileprivate static func buildFrames(
        now: Date,
        scales: [Int],
        maxAge: TimeInterval,
        samples: Int = 400
    ) -> [SpectrogramBuffer.Frame] {
        var built: [SpectrogramBuffer.Frame] = []
        let denom = max(1, samples - 1)
        let step = maxAge / Double(denom)
        for i in 0..<samples {
            let age = Double(i) * step
            let t = now.addingTimeInterval(-age)
            let tones = HarmonicAnalysis.activeTones(at: t, scales: scales)
            built.append(SpectrogramBuffer.Frame(id: t, tones: tones))
        }
        return built.reversed()
    }

    private func canvas(now: Date, frames: [SpectrogramBuffer.Frame]) -> some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size, now: now, frames: frames)
        }
        .background(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, now: Date, frames: [SpectrogramBuffer.Frame]) {
        let logMin = log10(minFreqHz)
        let logMax = log10(maxFreqHz)
        let range = logMax - logMin
        guard range > 0 else { return }

        let axisWidth: CGFloat = 30
        let plotX = axisWidth
        let plotWidth = size.width - axisWidth

        for d in [0.1, 1.0, 10.0, 100.0, 1_000.0, 10_000.0] {
            let y = mapY(d, logMin: logMin, range: range, height: size.height)
            let text = Text(decadeLabel(d))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            ctx.draw(text, at: CGPoint(x: axisWidth / 2, y: y), anchor: .center)
        }
        var spine = Path()
        spine.move(to: CGPoint(x: plotX, y: 0))
        spine.addLine(to: CGPoint(x: plotX, y: size.height))
        ctx.stroke(spine, with: .color(.white.opacity(0.2)), lineWidth: 0.5)

        for frame in frames {
            let age = now.timeIntervalSince(frame.id)
            if age < 0 || age > windowSeconds { continue }
            let xFrac = 1.0 - age / windowSeconds
            let x = plotX + CGFloat(xFrac) * plotWidth
            for tone in frame.tones {
                guard tone.frequency >= minFreqHz, tone.frequency <= maxFreqHz else { continue }
                if !settings.showFundamentals && tone.isFundamental { continue }
                let y = mapY(tone.frequency, logMin: logMin, range: range, height: size.height)
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
        let markers: [(Double, String)] = [
            (0, "now"), (day, "1d"), (2 * day, "2d"), (3 * day, "3d"),
            (4 * day, "4d"), (5 * day, "5d"), (6 * day, "6d"), (7 * day, "7d"),
        ]
        for (age, label) in markers where age <= windowSeconds + 1 {
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
