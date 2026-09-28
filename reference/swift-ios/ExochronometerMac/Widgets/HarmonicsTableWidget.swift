import SwiftUI
import ExochronometerCore

/// Cross-timeframe table of geometry harmonics. Values are pure functions
/// of timeframe (cycleDuration) and shape — no `date` dependency — so
/// there's no Live vs Snapshot distinction; the widget renders the same
/// in both modes.
struct LiveHarmonicsTableWidget: View {
    let snapshotDate: Date?

    var body: some View {
        HarmonicsTableWidgetView()
    }
}

struct HarmonicsTableWidgetView: View {
    private let shapes: [GeometryMath.Shape] = GeometryMath.defaultShapes
    private let timeframeOrder: [TimeFrame] = [.year, .moon, .quarterMoon, .day, .hour, .minute]

    var body: some View {
        CaptureAwareScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("HARMONICS TABLE  ·  A4 = 432 Hz")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                ForEach(timeframeOrder) { tf in
                    section(for: tf)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func section(for tf: TimeFrame) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(tf.label)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(tf.sublabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)

            VStack(spacing: 0) {
                ForEach(shapes) { shape in
                    row(shape: shape, timeframe: tf)
                    Divider().background(Color.white.opacity(0.08))
                }
            }
        }
    }

    private func row(shape: GeometryMath.Shape, timeframe: TimeFrame) -> some View {
        let period = timeframe.cycleDuration * Double(shape.skip) / Double(shape.divisions)
        let frequency = period > 0 ? 1.0 / period : 0
        let match = JustIntonation.closestNote(frequency: frequency)
        let sign = match.centsDelta >= 0 ? "+" : ""

        return HStack(spacing: 10) {
            Text("\(shape.divisions):\(shape.skip)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(FrequencyMath.format(frequency))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Text("p: \(FrequencyMath.formatDuration(period))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(match.noteName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                Text("\(sign)\(String(format: "%.1f", match.centsDelta))¢")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
