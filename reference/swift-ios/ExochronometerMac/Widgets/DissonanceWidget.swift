import SwiftUI
import ExochronometerCore

struct LiveDissonanceWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            DissonanceWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 5.0, paused: false)) { context in
                DissonanceWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct DissonanceWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    private let scaling: Int = 23

    var body: some View {
        let raw = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
        let tones = raw.filter { tone in
            if !settings.showFundamentals && tone.isFundamental { return false }
            if settings.excludedTimeframes.contains(tone.timeframe) { return false }
            return true
        }
        let pairCount = max(1, tones.count * (tones.count - 1) / 2)
        let tenneyTotal = DissonanceMath.totalTenney(tones)
        let entropyTotal = DissonanceMath.totalEntropy(tones)
        let tenneyPerPair = tenneyTotal / Double(pairCount)
        let entropyPerPair = entropyTotal / Double(pairCount)
        let rawTenneyNorm = tenneyPerPair / DissonanceCalibration.tenneyMeterMax
        let rawEntropyNorm = entropyPerPair / DissonanceCalibration.entropyMeterMax

        return VStack(alignment: .leading, spacing: 16) {
            Text("DISSONANCE")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))

            block(title: "TENNEY", unit: "TH", perPair: tenneyPerPair, total: tenneyTotal, rawNormalized: rawTenneyNorm,
                  left: "CONSONANT", right: "DISSONANT")
            block(title: "ENTROPY", unit: "HE", perPair: entropyPerPair, total: entropyTotal, rawNormalized: rawEntropyNorm,
                  left: "CLEAR", right: "AMBIGUOUS")

            Text("\(tones.count) active tones  ·  \(pairCount) pairs")
                .font(.system(size: 8, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
    }

    private func block(title: String, unit: String, perPair: Double, total: Double, rawNormalized: Double, left: String, right: String) -> some View {
        let spilling = rawNormalized > 1.0
        let rawSpillover = spilling ? Int(((rawNormalized - 1.0) * 100).rounded()) : 0
        let spilloverPercent = min(DissonanceCalibration.spilloverDisplayCap, rawSpillover)
        let pegged = spilloverPercent >= DissonanceCalibration.spilloverDisplayCap
        let percent = min(100 + DissonanceCalibration.spilloverDisplayCap, Int((rawNormalized * 100).rounded()))
        return VStack(spacing: 4) {
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
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.3f", perPair))
                    .font(.system(size: 22, weight: .ultraLight, design: .monospaced))
                Text(unit)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(spilling ? .red.opacity(0.9) : .white.opacity(0.9))
            Text("Σ \(String(format: "%.2f", total)) \(unit)")
                .font(.system(size: 8, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white)
            meter(value: min(1.0, rawNormalized), spilling: spilling).frame(height: 6)
            HStack {
                Text(left)
                    .font(.system(size: 7, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                if spilling {
                    Text("SPILLOVER  +\(spilloverPercent)%\(pegged ? "+" : "")")
                        .font(.system(size: 7, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.red.opacity(0.85))
                }
                Spacer()
                Text(right)
                    .font(.system(size: 7, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func meter(value: Double, spilling: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(spilling ? Color.red.opacity(0.85) : .white.opacity(0.85))
                    .frame(width: proxy.size.width * CGFloat(max(0, min(1, value))))
            }
        }
    }
}
