import SwiftUI
import ExochronometerCore

/// Displays a frozen `TriggerCalibrationResult` stored in the widget's
/// settings. Multiple instances can coexist with different results so
/// the user can compare runs side-by-side. The result is baked into
/// settings at spawn time — running new calibrations doesn't update an
/// existing widget.
struct LiveCalibrationResultWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        CalibrationResultWidgetView(settings: settings)
    }
}

struct CalibrationResultWidgetView: View {
    let settings: WidgetSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let result = settings.pinnedCalibration {
                summary(result: result)
                Divider()
                breakdownList(result: result)
            } else {
                emptyState
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CALIBRATION RESULT")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))
            if let label = settings.pinnedCalibrationLabel, !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func summary(result r: TriggerCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(r.window.duration / 86400))d  ·  \(Int(r.tickSeconds / 60))min ticks")
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", r.combined.mean))
                    .font(.system(size: 28, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Text("avg / day")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            HStack(spacing: 12) {
                stat(label: "MIN", value: "\(r.combined.min)")
                stat(label: "MED", value: String(format: "%.1f", r.combined.median))
                stat(label: "MAX", value: "\(r.combined.max)")
                stat(label: "TOTAL", value: "\(r.combined.total)")
            }
            if r.chordsSkipped {
                Text("+ chord onset (skipped, ~10-15/day)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func breakdownList(result r: TriggerCalibrationResult) -> some View {
        let sorted = r.perTrigger
            .filter { $0.value.total > 0 }
            .sorted { $0.value.total > $1.value.total }
        return VStack(alignment: .leading, spacing: 3) {
            Text("BY TRIGGER")
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
            if sorted.isEmpty {
                Text("no firings — try longer window or different thresholds")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(sorted, id: \.key) { (kind, stats) in
                    HStack {
                        Text(kind.displayName)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        Spacer()
                        Text("\(stats.total)t · μ\(String(format: "%.1f", stats.mean))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No result pinned.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Text("Open Triggers → run a calibration → click \"Pin to widget\" to populate this.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
