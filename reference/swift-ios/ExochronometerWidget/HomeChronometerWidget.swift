import SwiftUI
import WidgetKit
import ExochronometerCore

struct HomeChronometerWidget: Widget {
    let kind = "HomeChronometerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TimeframeConfigurationIntent.self,
            provider: ChronometerProvider()
        ) { entry in
            Button(intent: RefreshChronometerIntent()) {
                HomeChronometerView(entry: entry)
            }
            .buttonStyle(.plain)
            .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Exochronometer")
        .description("Geometric time circle. Pick a timeframe; add twice for two views.")
        .supportedFamilies([.systemSmall])
    }
}

struct HomeChronometerView: View {
    let entry: ChronometerEntry

    var body: some View {
        let frame = entry.timeframe.timeFrame
        let degree = frame.degree(at: entry.date)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
                .padding(6)

            GeometryOverlayView(
                date: entry.date,
                timeframe: frame,
                lineWidth: 0.5,
                fadeFraction: 0.04
            )
            .padding(6)

            GeometryReader { proxy in
                let radius = (min(proxy.size.width, proxy.size.height) - 12) / 2
                let radians = (degree - 90) * .pi / 180
                let x = proxy.size.width / 2 + radius * cos(radians)
                let y = proxy.size.height / 2 + radius * sin(radians)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: y)
                    .shadow(color: .white.opacity(0.7), radius: 4)
            }

            VStack(spacing: 2) {
                Text(frame.label)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(frame.traditionalLabel(at: entry.date))
                    .font(.system(size: 14, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 16)
        }
    }
}
