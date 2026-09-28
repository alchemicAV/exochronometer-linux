import WidgetKit
import ExochronometerCore

struct ChronometerEntry: TimelineEntry {
    let date: Date
    let timeframe: WidgetTimeframe
}

struct ChronometerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChronometerEntry {
        ChronometerEntry(date: .now, timeframe: .day)
    }

    func snapshot(for configuration: TimeframeConfigurationIntent, in context: Context) async -> ChronometerEntry {
        ChronometerEntry(date: .now, timeframe: configuration.timeframe)
    }

    func timeline(for configuration: TimeframeConfigurationIntent, in context: Context) async -> Timeline<ChronometerEntry> {
        let frame = configuration.timeframe.timeFrame
        let step = Self.refreshStep(for: frame)
        let entries = (0..<24).map { i in
            ChronometerEntry(
                date: Date().addingTimeInterval(Double(i) * step),
                timeframe: configuration.timeframe
            )
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// One snapshot per ~1/120 of the cycle, clamped to [5min, 1hr].
    /// iOS will throttle further if it deems necessary.
    private static func refreshStep(for frame: TimeFrame) -> TimeInterval {
        let raw = frame.cycleDuration / 120
        return min(max(raw, 300), 3600)
    }
}
