import SwiftUI
import ExochronometerCore

struct LiveConvergenceSelectorWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            ConvergenceSelectorWidgetView(date: date, settings: settings)
        } else {
            SwiftUI.TimelineView(
                .animation(minimumInterval: refreshInterval, paused: false)
            ) { context in
                ConvergenceSelectorWidgetView(date: context.date, settings: settings)
            }
        }
    }

    /// Match each timeframe's natural change-rate. Year shifts visibly
    /// every ~30s; minute every frame. A combined-view widget driven by
    /// the fastest contributing rate (minute) overspends — clamp to
    /// 5Hz, plenty for visualizing the minute's slow fade window.
    private var refreshInterval: Double {
        guard let tf = settings.selectorTimeframe else { return 1.0 / 5.0 }
        switch tf {
        case .minute:      return 1.0 / 15.0
        case .hour:        return 1.0 / 2.0
        case .day:         return 2.0
        case .quarterMoon: return 5.0
        case .moon:        return 10.0
        case .year:        return 30.0
        }
    }
}

struct ConvergenceSelectorWidgetView: View {
    let date: Date
    let settings: WidgetSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerText)
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))

            ConvergenceSelectorChart(
                date: date,
                selectedTimeframe: settings.selectorTimeframe,
                excludedTimeframes: settings.excludedTimeframes
            )
        }
        .padding(12)
    }

    private var headerText: String {
        if let tf = settings.selectorTimeframe {
            return "CONVERGENCE SQUARE  ·  \(longName(tf))"
        }
        return "CONVERGENCE SQUARE  ·  ALL"
    }

    private func longName(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON"
        case .quarterMoon: return "QTR MOON"
        case .day:         return "DAY"
        case .hour:        return "HOUR"
        case .minute:      return "MINUTE"
        }
    }
}
