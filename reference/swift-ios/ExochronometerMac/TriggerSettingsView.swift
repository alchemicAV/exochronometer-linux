import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ExochronometerCore

/// Popover UI for the trigger engine. Grouped sections, threshold sliders
/// where applicable, per-rule cooldown editor. Dry-run toggle up top so
/// the user can preview cadence without writing to disk.
struct TriggerSettingsView: View {
    @ObservedObject var evaluator: TriggerEvaluator
    @EnvironmentObject var layout: WidgetLayoutManager
    @StateObject private var calibrator = TriggerCalibrator()
    @State private var calibrationDays: Int = 30
    @State private var calibrationTickMin: Int = 5
    @State private var calibrationSkipChords: Bool = true
    @State private var pinLabel: String = ""
    @State private var showingXConfigure: Bool = false
    @ObservedObject private var xAuth = XAuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(title: "Geometry Peak", kinds: [.yearGeometryPeak, .moonGeometryPeak])
                    section(title: "Periodic", kinds: [.dayBoundary, .halfDayBoundary])
                    section(title: "Threshold (entry only)", kinds: [.dissonanceHigh, .dissonanceLow, .entropyHigh, .entropyLow])
                    section(title: "Extreme (with peak detection)", kinds: [.dissonanceExtremeHigh, .dissonanceExtremeLow, .entropyExtremeHigh, .entropyExtremeLow])
                    section(title: "Chord", kinds: [.chordOnset])
                    section(title: "Phase Closure", kinds: [.phaseClosed, .phaseClosedYear, .phaseClosedMoon, .phaseClosedQuarterMoon, .phaseClosedDay, .phaseClosedHour])
                    Divider().padding(.vertical, 6)
                    exclusionsSection
                    Divider().padding(.vertical, 6)
                    calibrationSection
                    Divider().padding(.vertical, 6)
                    recentSection
                }
                .padding(14)
            }
        }
        .frame(width: 420, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Triggers")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    showingXConfigure = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: xConnectedIcon)
                        Text(xConnectedLabel)
                    }
                }
                .controlSize(.small)
                .help("Configure X (OAuth 2.0). Sign in, test post, manage credentials.")
                .sheet(isPresented: $showingXConfigure) {
                    XConfigureView()
                }
            }
            HStack(spacing: 14) {
                Toggle("Dry run", isOn: $evaluator.dryRun)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("When on, evaluates rules and counts firings but does NOT write to disk or post.")
                Toggle("Post to X", isOn: $evaluator.postToX)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("When on, each trigger fire (a) writes PNG+TXT to ~/Pictures/Exochronometer, AND (b) posts a tweet via X API.")
                    .disabled(!(isXSignedIn))
                Spacer()
            }
            HStack(spacing: 6) {
                Button("Save Profile…") { saveProfileToFile() }
                    .controlSize(.mini)
                    .help("Export rules + suppression settings to a JSON file. Restore later if UserDefaults gets lost.")
                Button("Load Profile…") { loadProfileFromFile() }
                    .controlSize(.mini)
                    .help("Import rules + suppression settings from a previously-exported JSON file.")
                Spacer()
                Text("24h: \(evaluator.firingsLast24h)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var isXSignedIn: Bool {
        if case .signedIn = xAuth.authState { return true }
        return false
    }

    private func saveProfileToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "exo-triggers-\(formatter.string(from: Date())).json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(evaluator.exportProfile())
                try data.write(to: url)
            } catch {
                NSLog("Save profile failed: \(error)")
            }
        }
    }

    private func loadProfileFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let profile = try decoder.decode(TriggerEvaluator.Profile.self, from: data)
                evaluator.importProfile(profile)
            } catch {
                NSLog("Load profile failed: \(error)")
            }
        }
    }

    private var xConnectedIcon: String {
        switch xAuth.authState {
        case .signedIn:    return "checkmark.circle.fill"
        case .authorizing: return "person.crop.circle.badge.clock"
        case .error:       return "exclamationmark.triangle.fill"
        case .signedOut:   return "person.crop.circle.badge.xmark"
        }
    }

    private var xConnectedLabel: String {
        switch xAuth.authState {
        case .signedIn(let u): return "X · @\(u)"
        case .authorizing:     return "X · signing in"
        case .error:           return "X · error"
        case .signedOut:       return "Configure X"
        }
    }

    @ViewBuilder
    private func section(title: String, kinds: [SnapshotTrigger]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            ForEach(kinds, id: \.self) { kind in
                if let binding = evaluator.binding(for: kind) {
                    ruleRow(kind: kind, rule: binding)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(kind: SnapshotTrigger, rule: Binding<TriggerRule>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: rule.enabled) {
                    Text(kind.displayName)
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                cooldownEditor(rule: rule)
            }
            if rule.wrappedValue.enabled, rule.wrappedValue.thresholdPercent != nil {
                thresholdEditor(rule: rule)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(rule.wrappedValue.enabled ? Color.accentColor.opacity(0.06) : Color.clear)
        )
    }

    private func cooldownEditor(rule: Binding<TriggerRule>) -> some View {
        HStack(spacing: 4) {
            Text("⏲")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            TextField("", value: Binding(
                get: { rule.wrappedValue.cooldownSeconds / 60 },
                set: { rule.wrappedValue.cooldownSeconds = max(0, $0 * 60) }
            ), formatter: integerFormatter)
            .textFieldStyle(.plain)
            .frame(width: 30)
            .font(.system(size: 10, design: .monospaced))
            Text("min")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thresholdEditor(rule: Binding<TriggerRule>) -> some View {
        HStack {
            Text("threshold")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { rule.wrappedValue.thresholdPercent ?? 0 },
                    set: { rule.wrappedValue.thresholdPercent = $0 }
                ),
                in: thresholdRange(for: rule.wrappedValue.kind)
            )
            Text("\(Int(rule.wrappedValue.thresholdPercent ?? 0))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.leading, 4)
    }

    private func thresholdRange(for kind: SnapshotTrigger) -> ClosedRange<Double> {
        switch kind {
        case .dissonanceHigh, .entropyHigh:                return 50...100
        case .dissonanceLow, .entropyLow:                  return 0...50
        // Extremes widened so auto-balance can write empirical p99 / p1
        // values for a distribution that doesn't reach spillover.
        case .dissonanceExtremeHigh, .entropyExtremeHigh:  return 70...200
        case .dissonanceExtremeLow, .entropyExtremeLow:    return 0...30
        default: return 0...100
        }
    }

    @ViewBuilder
    private var exclusionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXCLUSIONS")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            Toggle(isOn: $evaluator.suppressNearPriorityEvents) {
                Text("Suppress dissonance/entropy during convergence")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            if evaluator.suppressNearPriorityEvents {
                HStack(spacing: 6) {
                    Text("Priority window:")
                        .font(.system(size: 10))
                    TextField("", value: $evaluator.priorityEventWindowMinutes, formatter: integerFormatter)
                        .frame(width: 40)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    Text("min")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Skips dissonance/entropy when either: (a) all 6 overtones (3-8) are simultaneously active on the hour or day timeframe (full convergence), or (b) a priority trigger fired within the window. Priority = year/moon geometry peak, day/half-day boundary.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $evaluator.pairMeterCooldowns) {
                Text("Pair dissonance/entropy cooldowns")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            if evaluator.pairMeterCooldowns {
                Text("When a meter trigger fires, its dissonance↔entropy twin is also held in cooldown (using the twin's own duration). Pairs: high↔high, low↔low, extremeHigh↔extremeHigh, extremeLow↔extremeLow.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CALIBRATION")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text("Simulate the current rule set over a date window to estimate daily firing volume. Uses the same evaluator as live — does not write any files.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Window:")
                    .font(.system(size: 10))
                TextField("", value: $calibrationDays, formatter: integerFormatter)
                    .frame(width: 40)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Text("days  ·  Tick:")
                    .font(.system(size: 10))
                TextField("", value: $calibrationTickMin, formatter: integerFormatter)
                    .frame(width: 40)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Text("min")
                    .font(.system(size: 10))
                Spacer()
            }
            Toggle("Skip chord computation (faster)", isOn: $calibrationSkipChords)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
                .help("Skips ChordProjector — the slowest part of each tick. Chord-onset firings won't be counted; add a manual estimate.")
            HStack(spacing: 8) {
                if calibrator.isRunning {
                    Button("Cancel") { calibrator.cancel() }
                        .controlSize(.small)
                } else {
                    Button {
                        calibrator.run(
                            rules: evaluator.rules,
                            days: max(1, calibrationDays),
                            tickSeconds: Double(max(1, calibrationTickMin)) * 60,
                            skipChordComputation: calibrationSkipChords,
                            suppressNearPriorityEvents: evaluator.suppressNearPriorityEvents,
                            priorityEventWindowMinutes: evaluator.priorityEventWindowMinutes,
                            pairMeterCooldowns: evaluator.pairMeterCooldowns
                        )
                    } label: {
                        Text("Estimate Daily Volume")
                    }
                    .controlSize(.small)
                    .disabled(!evaluator.rules.contains(where: \.enabled))
                }
                if calibrator.isRunning {
                    ProgressView(value: calibrator.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .frame(width: 120)
                }
                Text(calibrator.status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let result = calibrator.result {
                calibrationResultView(result)
            }
        }
    }

    @ViewBuilder
    private func calibrationResultView(_ r: TriggerCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RESULT  ·  \(Int(r.window.duration / 86400)) days  ·  \(Int(r.tickSeconds / 60)) min ticks")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            // Combined first — the user's primary "how many posts per day" answer.
            HStack {
                Text("TOTAL / day")
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text(formatStats(r.combined))
                    .font(.system(size: 10, design: .monospaced))
            }
            .padding(.bottom, 2)
            HStack {
                Text("EST. COST")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCost(r.combined))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if r.chordsSkipped {
                Text("Chord onset skipped · add ~10-15/day manually")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            Divider()

            distributionBlock(title: "TENNEY METER %", dist: r.tenneyDistribution)
            distributionBlock(title: "ENTROPY METER %", dist: r.entropyDistribution)

            HStack(spacing: 8) {
                Button {
                    autoBalance(using: r)
                } label: {
                    Label("Auto-balance thresholds", systemImage: "arrow.left.and.right")
                }
                .controlSize(.small)
                .help("Set dissonance/entropy peak & trough thresholds to the p95/p5 of the observed meter distribution, so they fire at roughly equal rates.")
            }
            .padding(.top, 4)

            HStack(spacing: 6) {
                TextField("Label (optional)", text: $pinLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                Button {
                    let label = pinLabel.isEmpty ? defaultPinLabel(for: r) : pinLabel
                    layout.addCalibrationResult(r, label: label)
                    pinLabel = ""
                } label: {
                    Label("Pin to widget", systemImage: "pin.fill")
                }
                .controlSize(.small)
                .help("Spawn a CalibrationResult widget with this run frozen in. Pin multiple to compare.")
            }
            .padding(.top, 4)

            Divider()

            // Per-trigger breakdown, sorted by total firings desc.
            let sorted = r.perTrigger
                .filter { $0.value.total > 0 }
                .sorted { $0.value.total > $1.value.total }
            if sorted.isEmpty {
                Text("No firings — try a longer window or check rule thresholds.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sorted, id: \.key) { (kind, stats) in
                    HStack {
                        Text(kind.displayName)
                            .font(.system(size: 9))
                            .lineLimit(1)
                        Spacer()
                        Text(formatStats(stats))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.05))
        )
    }

    @ViewBuilder
    private func distributionBlock(title: String, dist: MeterDistribution) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                distChip("p1",  dist.p1)
                distChip("p5",  dist.p5)
                distChip("p25", dist.p25)
                distChip("p50", dist.p50)
                distChip("p75", dist.p75)
                distChip("p95", dist.p95)
                distChip("p99", dist.p99)
            }
        }
    }

    private func distChip(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 10, design: .monospaced))
        }
    }

    /// Writes balanced thresholds for both the regular peak/trough and
    /// the extreme variants, in matched percentile pairs:
    ///   - regular  = p95 / p5  (≈ 5% of ticks per side)
    ///   - extreme  = p99 / p1  (≈ 1% of ticks per side)
    /// This keeps the regular-vs-extreme hierarchy intact (extreme always
    /// strictly more extreme than regular) even when the meter
    /// distribution's tails differ from the spillover-based defaults.
    private func autoBalance(using r: TriggerCalibrationResult) {
        // Regular peak/trough
        applyThreshold(.dissonanceHigh, value: r.tenneyDistribution.p95)
        applyThreshold(.dissonanceLow,  value: r.tenneyDistribution.p5)
        applyThreshold(.entropyHigh,    value: r.entropyDistribution.p95)
        applyThreshold(.entropyLow,     value: r.entropyDistribution.p5)
        // Extreme variants
        applyThreshold(.dissonanceExtremeHigh, value: r.tenneyDistribution.p99)
        applyThreshold(.dissonanceExtremeLow,  value: r.tenneyDistribution.p1)
        applyThreshold(.entropyExtremeHigh,    value: r.entropyDistribution.p99)
        applyThreshold(.entropyExtremeLow,     value: r.entropyDistribution.p1)
    }

    private func applyThreshold(_ kind: SnapshotTrigger, value: Double) {
        guard let idx = evaluator.rules.firstIndex(where: { $0.kind == kind }) else { return }
        let range = thresholdRange(for: kind)
        // Clamp to the rule's slider range so the UI stays consistent
        // and the value is always achievable via the editor.
        let clamped = min(range.upperBound, max(range.lowerBound, value.rounded()))
        evaluator.rules[idx].thresholdPercent = clamped
    }

    /// Default label encodes the run's main parameters so the pinned
    /// widget reads as self-describing without the user having to type.
    private func defaultPinLabel(for r: TriggerCalibrationResult) -> String {
        let days = Int(r.window.duration / 86400)
        let mins = Int(r.tickSeconds / 60)
        let suffix = r.chordsSkipped ? " · no chords" : ""
        return "\(days)d × \(mins)min\(suffix)"
    }

    private func formatStats(_ s: TriggerVolumeStats) -> String {
        // Format: total · min N · med M · max P · mean A (compact)
        String(
            format: "%d total · min %d · med %.1f · max %d",
            s.total, s.min, s.median, s.max
        )
    }

    /// X charges $0.015 per plain text+image post (and $0.20 if the
    /// caption contains a URL). The calibrator can't predict the URL
    /// case so the estimate is for the plain rate; we mention the URL
    /// premium in the help text on the toggle.
    private func formatCost(_ s: TriggerVolumeStats) -> String {
        let perPost = 0.015
        let perDay = s.mean * perPost
        let perMonth = perDay * 30
        return String(
            format: "$%.2f/day · $%.2f/mo (at $0.015/post)",
            perDay, perMonth
        )
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            if evaluator.firingLog.isEmpty {
                Text("No firings yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(evaluator.firingLog.prefix(15)) { record in
                    recentRow(record: record)
                }
            }
        }
    }

    private func recentRow(record: TriggerEvaluator.FiringRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: record.wroteToDisk ? "photo.fill" : "eye")
                .font(.system(size: 9))
                .foregroundStyle(record.wroteToDisk ? Color.accentColor : Color.secondary)
            xStatusIcon(record: record)
            if record.captionHadURL {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .help("Caption contains a URL — X charges $0.20/post instead of $0.015.")
            }
            Text(record.trigger.displayName)
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer()
            Text(record.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func xStatusIcon(record: TriggerEvaluator.FiringRecord) -> some View {
        switch record.xPostState {
        case .notAttempted:
            EmptyView()
        case .posted(let url):
            Link(destination: url) {
                Image(systemName: "checkmark.bubble.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
            }
            .help("Posted to X — click to open")
        case .rateLimited:
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
                .help("X rate-limited the post")
        case .failed(let msg):
            Image(systemName: "xmark.bubble.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .help("Post failed: \(msg)")
        }
    }

    private var integerFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimum = 0
        return f
    }
}
