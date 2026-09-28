import SwiftUI
import ExochronometerCore

struct LiveConvergenceWidget: View {
    let snapshotDate: Date?
    let settings: WidgetSettings

    var body: some View {
        if let date = snapshotDate {
            ConvergenceWidgetView(referenceDate: date, settings: settings, ticking: false)
        } else {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1.0)) { context in
                ConvergenceWidgetView(referenceDate: context.date, settings: settings, ticking: true)
            }
        }
    }
}

/// `referenceDate` is what we're rendering AGAINST (now ticks every
/// second). The expensive forward-search work happens off the main
/// thread on a longer cadence via `.task(id:)`.
struct ConvergenceWidgetView: View {
    let referenceDate: Date
    let settings: WidgetSettings
    let ticking: Bool

    private static let lookahead: TimeInterval = 30 * 86400
    private static let maxResults = 40

    @State private var events: [ChordEvent] = []
    @State private var current: [ChordMatch] = []
    @State private var loading: Bool = true
    @State private var anchorDate: Date = .distantPast

    var body: some View {
        // Static snapshot mode: ImageRenderer renders one frame and
        // doesn't dispatch `.task`, so the live path's @State stays
        // empty and the widget would show "…computing" in captures.
        // Compute synchronously here instead. Slow (~hundreds of ms)
        // but one-shot, which is fine for a frozen render.
        let snapshotCurrent: [ChordMatch]?
        let snapshotEvents: [ChordEvent]?
        if !ticking {
            snapshotCurrent = ChordProjector.current(
                at: referenceDate,
                includeFundamentals: settings.showFundamentals,
                crossTimeframeOnly: true,
                excludeHourly: settings.excludeHourly,
                patterns: ChordCatalog.chords
            )
            snapshotEvents = ChordProjector.upcoming(
                from: referenceDate,
                lookahead: Self.lookahead,
                includeFundamentals: settings.showFundamentals,
                crossTimeframeOnly: true,
                excludeHourly: settings.excludeHourly,
                patterns: ChordCatalog.chords,
                maxResults: Self.maxResults
            )
        } else {
            snapshotCurrent = nil
            snapshotEvents = nil
        }
        let displayedCurrent = snapshotCurrent ?? current
        let displayedEvents  = snapshotEvents  ?? events
        let displayedLoading = ticking ? loading : false

        return CaptureAwareScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("CONVERGENCE  ·  CHORDS")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))

                currentSection(current: displayedCurrent, loading: displayedLoading)
                upcomingSection(events: displayedEvents, loading: displayedLoading)
            }
            .padding(12)
        }
        .task(id: recomputeKey) {
            guard ticking else { return }
            await recompute(at: referenceDate)
        }
    }

    /// Forward search reruns at most every 5 min (or when the snapshot
    /// date changes, or when the fundamentals toggle flips).
    private var recomputeKey: String {
        let bucket = Int(referenceDate.timeIntervalSinceReferenceDate / 300)
        return "\(bucket)|\(settings.showFundamentals ? 1 : 0)|\(settings.excludeHourly ? 1 : 0)|\(ticking ? "L" : "S")"
    }

    @ViewBuilder
    private func currentSection(current: [ChordMatch], loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            if loading {
                Text("…computing")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else if current.isEmpty {
                Text("no recognized chord active")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(current.prefix(5), id: \.id) { match in
                    currentRow(match, at: referenceDate)
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(events: [ChordEvent], loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CROSS-TIMEFRAME CONVERGENCES")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("next 30 days  ·  nearest first")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 4)
            if loading {
                Text("…computing")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else if events.isEmpty {
                Text("none predicted in window")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(events, id: \.id) { event in
                    upcomingRow(event)
                }
            }
        }
    }

    private func currentRow(_ match: ChordMatch, at date: Date) -> some View {
        let remaining = chordRemaining(match, at: date)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(match.pattern.abbreviation)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                Text(signatureText(match.tones.map {
                    ChordEvent.ToneSignature(timeframe: $0.timeframe, divisions: $0.divisions, skip: $0.skip)
                }))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(remaining.map { "ends \(durationText($0))" } ?? "active")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(fitText(match.fitCents))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    /// Seconds until the first overtone in the chord drops out of its
    /// fade window. Fundamentals never expire, so a chord of only
    /// fundamentals returns nil and is rendered as "active".
    private func chordRemaining(_ match: ChordMatch, at date: Date) -> TimeInterval? {
        var best: TimeInterval = .infinity
        for tone in match.tones {
            guard let r = FadeMath.timeUntilOvertoneExit(
                timeframe: tone.timeframe,
                divisions: tone.divisions,
                skip: tone.skip,
                at: date
            ) else { continue }
            if r < best { best = r }
        }
        return best.isFinite ? best : nil
    }

    private func upcomingRow(_ event: ChordEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(event.pattern.abbreviation)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                Text(signatureText(event.toneSignature))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(timeUntilText(event.startTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            HStack(spacing: 10) {
                Text(fitText(event.fitCents))
                Text("dur \(durationText(event.endTime.timeIntervalSince(event.startTime)))")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func signatureText(_ sig: [ChordEvent.ToneSignature]) -> String {
        sig.map { compactTF($0.timeframe) + ":" + $0.divisionLabel }
            .joined(separator: " · ")
    }

    private func compactTF(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YR"
        case .moon:        return "MN"
        case .quarterMoon: return "QM"
        case .day:         return "DY"
        case .hour:        return "HR"
        case .minute:      return "MIN"
        }
    }

    private func fitText(_ cents: Double) -> String {
        "fit \(String(format: "%.1f", cents))¢"
    }

    private func timeUntilText(_ d: Date) -> String {
        durationText(max(0, d.timeIntervalSince(referenceDate)))
    }

    private func durationText(_ s: TimeInterval) -> String {
        if s < 60 { return String(format: "%.0fs", s) }
        if s < 3600 { return String(format: "%.0fm %.0fs", floor(s / 60), s.truncatingRemainder(dividingBy: 60)) }
        if s < 86400 {
            let h = floor(s / 3600)
            let m = floor(s.truncatingRemainder(dividingBy: 3600) / 60)
            return String(format: "%.0fh %.0fm", h, m)
        }
        let d = floor(s / 86400)
        let h = floor(s.truncatingRemainder(dividingBy: 86400) / 3600)
        return String(format: "%.0fd %.0fh", d, h)
    }

    private func recompute(at date: Date) async {
        await MainActor.run { loading = true }
        let includeFundamentals = settings.showFundamentals
        let excludeHourly = settings.excludeHourly
        let upcoming = await Task.detached(priority: .userInitiated) {
            ChordProjector.upcoming(
                from: date,
                lookahead: Self.lookahead,
                includeFundamentals: includeFundamentals,
                crossTimeframeOnly: true,
                excludeHourly: excludeHourly,
                patterns: ChordCatalog.chords,
                maxResults: Self.maxResults
            )
        }.value
        let nowMatches = await Task.detached(priority: .userInitiated) {
            ChordProjector.current(
                at: date,
                includeFundamentals: includeFundamentals,
                crossTimeframeOnly: true,
                excludeHourly: excludeHourly,
                patterns: ChordCatalog.chords
            )
        }.value
        await MainActor.run {
            self.events = upcoming
            self.current = nowMatches
            self.anchorDate = date
            self.loading = false
        }
    }
}
