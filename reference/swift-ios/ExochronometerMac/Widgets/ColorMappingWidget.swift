import SwiftUI
import ExochronometerCore

struct LiveColorMappingWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            ColorMappingWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { context in
                ColorMappingWidgetView(date: context.date, settings: settings)
            }
        }
    }
}

struct ColorMappingWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    private let scaling: Int = 23
    private let timeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]

    var body: some View {
        let raw = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
        let tones = raw.filter { tone in
            if !settings.showFundamentals && tone.isFundamental { return false }
            if settings.excludedTimeframes.contains(tone.timeframe) { return false }
            return true
        }

        return CaptureAwareScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("COLOR MAPPING")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))

                swatch(title: "COMPOSITE", color: blendedColor(tones), count: tones.count, height: 70)

                Text("PER TIMEFRAME")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)

                ForEach(timeframes, id: \.self) { tf in
                    let group = tones.filter { $0.timeframe == tf }
                    swatch(title: label(for: tf), color: blendedColor(group), count: group.count, height: 28)
                }
            }
            .padding(12)
        }
    }

    private func swatch(title: String, color: Color, count: Int, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    private func label(for tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON"
        case .quarterMoon: return "1/4 MOON"
        case .day:         return "DAY"
        case .hour:        return "HOUR"
        case .minute:      return "MINUTE"
        }
    }

    private func blendedColor(_ tones: [HarmonicTone]) -> Color {
        HarmonicColor.blendedColor(of: tones)
    }
}
