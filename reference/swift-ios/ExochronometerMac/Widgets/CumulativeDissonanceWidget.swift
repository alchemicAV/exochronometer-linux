import SwiftUI
import ExochronometerCore

struct LiveCumulativeDissonanceWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            CumulativeDissonanceView(
                endDate: date,
                range: settings.dissonanceGraphRange,
                includeFundamentals: settings.showFundamentals,
                ticking: false
            )
        } else {
            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                CumulativeDissonanceView(
                    endDate: context.date,
                    range: settings.dissonanceGraphRange,
                    includeFundamentals: settings.showFundamentals,
                    ticking: true
                )
            }
        }
    }
}

struct CumulativeDissonanceView: View {
    let endDate: Date
    let range: DissonanceGraphRange
    let includeFundamentals: Bool
    let ticking: Bool

    @State private var samples: [DissonanceGraphSample] = []
    @State private var loading: Bool = true

    var body: some View {
        // Static snapshot mode: compute synchronously so ImageRenderer
        // captures actual data instead of an empty graph. `.task` doesn't
        // run under ImageRenderer, so the @State stays empty otherwise.
        let snapshotSamples: [DissonanceGraphSample]? = ticking ? nil :
            DissonanceGraphSampler.samples(
                endingAt: endDate,
                range: range,
                includeFundamentals: includeFundamentals
            )
        let displayedSamples = snapshotSamples ?? samples
        let displayedLoading = ticking ? loading : false

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DISSONANCE OVER TIME")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(range.label)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(spacing: 6) {
                plot(title: "TENNEY", values: displayedSamples.map(\.tenneyNormalized), loading: displayedLoading, showHourLabels: true)
                plot(title: "ENTROPY", values: displayedSamples.map(\.entropyNormalized), loading: displayedLoading, showHourLabels: false)
            }
        }
        .padding(12)
        .task(id: taskKey) {
            guard ticking else { return }
            await recompute()
        }
    }

    private var taskKey: String {
        // Bucket the end-date so we don't recompute on every minute tick.
        // 1 day @ 240 buckets = 6 min/bucket; 1 qm @ 240 = ~44 min/bucket.
        let bucketSeconds = range.seconds / 240.0
        let bucket = Int(endDate.timeIntervalSinceReferenceDate / bucketSeconds)
        return "\(bucket)|\(range.rawValue)|\(includeFundamentals ? 1 : 0)"
    }

    @ViewBuilder
    private func plot(title: String, values: [Double], loading: Bool, showHourLabels: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
            Canvas { ctx, size in
                drawGraph(in: &ctx, size: size, values: values, loading: loading, showHourLabels: showHourLabels)
            }
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private func drawGraph(in ctx: inout GraphicsContext, size: CGSize, values: [Double], loading: Bool, showHourLabels: Bool) {
        guard size.width > 0 && size.height > 0 else { return }

        // Y axis: 0 at bottom, 100% at 2/3 of height, 150% at top (gives a
        // bit of headroom for spillover before clipping). Anything above
        // 150% gets pinned to the top of the chart.
        let yMaxRatio = 1.5
        func yFor(_ v: Double) -> CGFloat {
            let clamped = max(0, min(yMaxRatio, v))
            return size.height * (1 - CGFloat(clamped / yMaxRatio))
        }

        // Background marks at 50% and 100%
        for (ratio, opacity) in [(0.5, 0.12), (1.0, 0.25)] {
            let y = yFor(ratio)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.white.opacity(opacity)), lineWidth: 0.5)
        }

        // Vertical time demarcations. Drawn here (under the curve) with the
        // local-time hour labelled at the top of the plot, where the curve
        // rarely reaches so the labels rarely collide with it.
        drawTimeDemarcations(in: &ctx, size: size, showLabels: showHourLabels)

        guard !loading, values.count > 1 else {
            let text = Text(loading ? "…computing" : "no data")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        // Spillover region fill (red) where curve exceeds 100%
        var spilloverFill = Path()
        spilloverFill.move(to: CGPoint(x: 0, y: yFor(1.0)))
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            spilloverFill.addLine(to: CGPoint(x: x, y: yFor(max(1.0, v))))
        }
        spilloverFill.addLine(to: CGPoint(x: size.width, y: yFor(1.0)))
        spilloverFill.closeSubpath()
        ctx.fill(spilloverFill, with: .color(.red.opacity(0.18)))

        // Main curve
        var path = Path()
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = yFor(v)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1)

        // Now indicator: small vertical line on the right
        var nowMark = Path()
        nowMark.move(to: CGPoint(x: size.width - 0.5, y: 0))
        nowMark.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
        ctx.stroke(nowMark, with: .color(.white.opacity(0.45)), lineWidth: 0.5)
    }

    /// Vertical gridlines every 2 hours of wall-clock LOCAL time across the
    /// visible window, with the hour labelled at the top of the plot. On the
    /// 1-day range this is the full 2-hour grid; on longer ranges the
    /// interval auto-widens (4/6/12/24h) so the lines never smear together.
    /// Marks align to local midnight, so labels read 00, 02, 04 … .
    private func drawTimeDemarcations(in ctx: inout GraphicsContext, size: CGSize, showLabels: Bool) {
        let rangeSeconds = range.seconds
        guard rangeSeconds > 0 else { return }
        let startDate = endDate.addingTimeInterval(-rangeSeconds)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current

        // Smallest 2-hour-multiple interval that keeps marks ≥ ~16pt apart.
        let candidateHours = [2, 4, 6, 12, 24, 48]
        let pxPerHour = size.width * 3600 / CGFloat(rangeSeconds)
        let intervalHours = candidateHours.first { CGFloat($0) * pxPerHour >= 16 } ?? 48

        let fmt = DateFormatter()
        fmt.dateFormat = "HH"
        fmt.timeZone = .current

        // Walk local-midnight + k·interval forward across the window.
        let dayStart = cal.startOfDay(for: startDate)
        var hours = 0
        while true {
            guard let mark = cal.date(byAdding: .hour, value: hours, to: dayStart) else { break }
            hours += intervalHours
            if mark < startDate { continue }
            if mark > endDate { break }

            let x = size.width * CGFloat(mark.timeIntervalSince(startDate) / rangeSeconds)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.white.opacity(0.10)), lineWidth: 0.5)

            if showLabels {
                let label = Text(fmt.string(from: mark))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                ctx.draw(label, at: CGPoint(x: x, y: 0), anchor: .top)
            }
        }
    }

    private func recompute() async {
        await MainActor.run { loading = true }
        let computed = await Task.detached(priority: .userInitiated) { [endDate, range, includeFundamentals] in
            DissonanceGraphSampler.samples(
                endingAt: endDate,
                range: range,
                includeFundamentals: includeFundamentals
            )
        }.value
        await MainActor.run {
            samples = computed
            loading = false
        }
    }
}
