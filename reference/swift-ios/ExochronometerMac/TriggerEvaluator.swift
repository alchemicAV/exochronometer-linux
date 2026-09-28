import Foundation
import SwiftUI
import ExochronometerCore

// MARK: - Configurable rule

public struct TriggerRule: Codable, Identifiable, Equatable {
    public let kind: SnapshotTrigger
    public var enabled: Bool
    public var cooldownSeconds: TimeInterval
    /// For threshold-based rules: the meter percent at which the rule arms.
    /// Stored as 0…100 (or higher for spillover) for ease of UI binding.
    public var thresholdPercent: Double?

    public var id: String { kind.rawValue }

    public init(kind: SnapshotTrigger, enabled: Bool, cooldownSeconds: TimeInterval, thresholdPercent: Double? = nil) {
        self.kind = kind
        self.enabled = enabled
        self.cooldownSeconds = cooldownSeconds
        self.thresholdPercent = thresholdPercent
    }
}

/// A fired trigger plus the instant its snapshot should depict. For most
/// triggers `captureDate` is the tick that fired. For extreme peak/fallback
/// fires it's the episode's apex — a few ticks in the past — so the
/// reconstructed snapshot shows the actual extreme, not the post-spike frame
/// the fire happened to land on.
public struct FiredTrigger: Equatable {
    public let kind: SnapshotTrigger
    public let captureDate: Date
}

// MARK: - Extreme episode tracking

/// Tracks an in-flight "extreme" episode so we can fire a peak/trough
/// snapshot near the apex rather than only on threshold entry.
/// Strategy: once the rule arms (entry), record the running max/min.
/// As soon as the value backs off the apex by `descentMargin`, fire a
/// "peak" snapshot. If the episode ends (drops below threshold) without
/// a descent fire, emit one anyway as a fallback so we don't miss the
/// only "near-peak" frame.
private struct ExtremeEpisode {
    enum Direction { case high, low }
    let direction: Direction
    var apex: Double               // running max (high) or min (low)
    var apexDate: Date
    var peakFired: Bool = false
    var entryFired: Bool = false
}

// MARK: - Evaluator

@MainActor
public final class TriggerEvaluator: ObservableObject {
    @Published public var rules: [TriggerRule] = TriggerEvaluator.makeDefaultRules() {
        didSet { if isPersisting { saveRules() } }
    }
    /// When true, evaluation continues but the engine skips file writes.
    /// Useful for dry-running rules over a day to count how often they'd
    /// fire before committing to disk.
    @Published public var dryRun: Bool = true {
        didSet {
            if isPersisting {
                UserDefaults.standard.set(dryRun, forKey: Self.dryRunKey)
            }
        }
    }
    /// When true, dissonance/entropy triggers are suppressed at the same
    /// tick as — or within `priorityEventWindowMinutes` after — a
    /// priority trigger (geometry peak / boundary). The rationale: those
    /// meters often crest right around a geometry event, and a separate
    /// post duplicates the moment without adding signal.
    @Published public var suppressNearPriorityEvents: Bool = false {
        didSet {
            if isPersisting {
                UserDefaults.standard.set(suppressNearPriorityEvents, forKey: Self.suppressKey)
            }
        }
    }
    /// Lookback (and same-tick) window for the suppression rule.
    @Published public var priorityEventWindowMinutes: Double = 30 {
        didSet {
            if isPersisting {
                UserDefaults.standard.set(priorityEventWindowMinutes, forKey: Self.windowKey)
            }
        }
    }
    /// When true, a firing of any dissonance/entropy trigger also puts
    /// its paired meter trigger into cooldown for the paired rule's own
    /// duration. Tenney and entropy track each other tightly, so a
    /// dissonance peak almost always coincides with an entropy peak —
    /// firing both is redundant. Pairs: high↔high, low↔low,
    /// extremeHigh↔extremeHigh, extremeLow↔extremeLow.
    @Published public var pairMeterCooldowns: Bool = false {
        didSet {
            if isPersisting {
                UserDefaults.standard.set(pairMeterCooldowns, forKey: Self.pairKey)
            }
        }
    }
    /// When true, the trigger driver calls `XAPIClient.shared.postTweet`
    /// in addition to writing PNG+caption to disk. Requires a successful
    /// X sign-in (see Configure X sheet). Defaults to off so live tweets
    /// don't fire until the user explicitly opts in.
    @Published public var postToX: Bool = false {
        didSet {
            if isPersisting {
                UserDefaults.standard.set(postToX, forKey: Self.postToXKey)
            }
        }
    }
    /// When false, instance is transient — used by the calibrator to run
    /// simulations without overwriting the user's persisted rule config.
    private let isPersisting: Bool

    /// Triggers that take precedence — fire first each tick, and
    /// optionally cause downstream dissonance/entropy fires to be skipped.
    public static let priorityTriggers: Set<SnapshotTrigger> = [
        .yearGeometryPeak, .moonGeometryPeak,
        .dayBoundary, .halfDayBoundary
    ]
    /// Triggers that can be suppressed by recent priority firings.
    public static let suppressibleTriggers: Set<SnapshotTrigger> = [
        .dissonanceHigh, .dissonanceLow,
        .dissonanceExtremeHigh, .dissonanceExtremeLow,
        .entropyHigh, .entropyLow,
        .entropyExtremeHigh, .entropyExtremeLow
    ]

    /// Bidirectional mapping of dissonance ↔ entropy triggers that share
    /// a cooldown when `pairMeterCooldowns` is enabled.
    private static let meterCooldownPairs: [SnapshotTrigger: SnapshotTrigger] = [
        .dissonanceHigh:        .entropyHigh,
        .entropyHigh:           .dissonanceHigh,
        .dissonanceLow:         .entropyLow,
        .entropyLow:            .dissonanceLow,
        .dissonanceExtremeHigh: .entropyExtremeHigh,
        .entropyExtremeHigh:    .dissonanceExtremeHigh,
        .dissonanceExtremeLow:  .entropyExtremeLow,
        .entropyExtremeLow:     .dissonanceExtremeLow,
    ]
    @Published public private(set) var firingLog: [FiringRecord] = []

    private var previousStats: SnapshotStats?
    private var lastFiredAt: [SnapshotTrigger: Date] = [:]
    private var extremes: [SnapshotTrigger: ExtremeEpisode] = [:]
    private var previousChordSet: Set<String> = []
    private var previousClosureByTimeframe: [TimeFrame: Bool] = [:]
    private var previousYearPeaking: Set<String> = []
    private var previousMoonPeaking: Set<String> = []
    /// True once we've completed at least one `evaluate` call. The first
    /// tick after launch only seeds the `previous*` slots — it does not
    /// fire rising-edge triggers, so a peak that started *before* the
    /// app launched isn't re-broadcast on every restart.
    private var hasBaselineState: Bool = false

    private static let rulesKey = "exo.mac.triggers.rules.v2"
    private static let dryRunKey = "exo.mac.triggers.dryRun"
    private static let suppressKey = "exo.mac.triggers.suppressNearPriority"
    private static let windowKey = "exo.mac.triggers.priorityWindowMin"
    private static let pairKey = "exo.mac.triggers.pairMeterCooldowns"
    private static let postToXKey = "exo.mac.triggers.postToX"
    private static let migrationKey = "exo.mac.triggers.migration.v1"
    /// Once an extreme has retreated by this fraction of its apex offset
    /// from the entry threshold, fire the "peak" capture.
    private static let extremeDescentMargin: Double = 0.05

    public init() {
        self.isPersisting = true
        if let data = UserDefaults.standard.data(forKey: Self.rulesKey),
           var decoded = try? JSONDecoder().decode([TriggerRule].self, from: data) {
            // One-time migration: force-disable legacy triggers that were
            // replaced by year/moonGeometryPeak so they stop firing under
            // their old semantics. We don't strip them from the array so
            // older binaries can still decode the saved data.
            let migrationDone = UserDefaults.standard.integer(forKey: Self.migrationKey) >= 1
            if !migrationDone {
                for i in decoded.indices where SnapshotTrigger.legacyReplacedByGeometryPeak.contains(decoded[i].kind) {
                    decoded[i].enabled = false
                }
                UserDefaults.standard.set(1, forKey: Self.migrationKey)
            }
            // Merge with defaults so adding a new rule kind in code shows up.
            let known = Set(decoded.map(\.kind))
            let added = Self.makeDefaultRules().filter { !known.contains($0.kind) }
            self.rules = decoded + added
        }
        self.dryRun = UserDefaults.standard.object(forKey: Self.dryRunKey) as? Bool ?? true
        self.suppressNearPriorityEvents = UserDefaults.standard.object(forKey: Self.suppressKey) as? Bool ?? false
        if let stored = UserDefaults.standard.object(forKey: Self.windowKey) as? Double, stored > 0 {
            self.priorityEventWindowMinutes = stored
        }
        self.pairMeterCooldowns = UserDefaults.standard.object(forKey: Self.pairKey) as? Bool ?? false
        self.postToX = UserDefaults.standard.object(forKey: Self.postToXKey) as? Bool ?? false
    }

    /// Transient init for calibration / simulation. Doesn't touch
    /// UserDefaults on read or write — the user's persisted rule config
    /// stays untouched while the calibrator drives this instance.
    public init(
        simulationRules: [TriggerRule],
        suppressNearPriorityEvents: Bool = false,
        priorityEventWindowMinutes: Double = 30,
        pairMeterCooldowns: Bool = false
    ) {
        self.isPersisting = false
        self.rules = simulationRules
        self.dryRun = true
        self.suppressNearPriorityEvents = suppressNearPriorityEvents
        self.priorityEventWindowMinutes = priorityEventWindowMinutes
        self.pairMeterCooldowns = pairMeterCooldowns
    }

    /// Per-rule defaults. Everything off out of the gate per requirement —
    /// the user wants to opt in once they've tested the cadence.
    public static func makeDefaultRules() -> [TriggerRule] {
        SnapshotTrigger.allCases
            .filter { $0 != .manual }
            .filter { !SnapshotTrigger.legacyReplacedByGeometryPeak.contains($0) }
            .map { TriggerRule(
                kind: $0,
                enabled: false,
                cooldownSeconds: $0.defaultCooldown,
                thresholdPercent: Self.defaultThreshold(for: $0)
            ) }
    }

    private static func defaultThreshold(for kind: SnapshotTrigger) -> Double? {
        switch kind {
        case .dissonanceHigh, .entropyHigh: return 85
        case .dissonanceLow, .entropyLow:   return 15
        case .dissonanceExtremeHigh, .entropyExtremeHigh: return 100  // spillover threshold
        case .dissonanceExtremeLow, .entropyExtremeLow:   return 2
        default: return nil
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.rulesKey)
        }
    }

    public func binding(for kind: SnapshotTrigger) -> Binding<TriggerRule>? {
        guard let idx = rules.firstIndex(where: { $0.kind == kind }) else { return nil }
        return Binding(
            get: { self.rules[idx] },
            set: { self.rules[idx] = $0 }
        )
    }

    /// Evaluate all enabled rules against the current observed state and
    /// return the triggers that fired. State-comparison rules (chord
    /// onset, phase closure) reference `previousStats`; extreme rules
    /// reference per-trigger ExtremeEpisode state.
    public func evaluate(stats current: SnapshotStats) -> [FiredTrigger] {
        defer {
            previousStats = current
            previousChordSet = Set(current.currentChords.map(\.abbreviation))
            previousClosureByTimeframe = current.phaseClosure
            previousYearPeaking = current.yearPeakingShapes
            previousMoonPeaking = current.moonPeakingShapes
            hasBaselineState = true
        }
        // First tick after launch: seed `previous*` and exit. Rising-edge
        // triggers would otherwise compare a populated current state
        // against the default-empty previous state and fire phantom
        // events for everything that was already in progress when the
        // app started.
        if !hasBaselineState { return [] }
        var fired: [FiredTrigger] = []

        // Pass 1 — priority triggers. Run first so their lastFiredAt
        // entry is updated *before* the suppressible rules check it,
        // making same-tick exclusion work for free.
        for rule in rules where rule.enabled && Self.priorityTriggers.contains(rule.kind) {
            if inCooldown(rule.kind, at: current.date) { continue }
            if let captureDate = shouldFire(rule: rule, current: current) {
                fired.append(FiredTrigger(kind: rule.kind, captureDate: captureDate))
                lastFiredAt[rule.kind] = current.date
            }
        }

        // Pass 2 — everything else. Suppressible rules check the
        // priority-event window AND the harmonic-convergence condition
        // first. The convergence check fires much more often than the
        // window (multiple times per day vs. tens per year), so it does
        // most of the work to actually cut dissonance/entropy volume.
        let suppressionWindow = priorityEventWindowMinutes * 60
        for rule in rules where rule.enabled && !Self.priorityTriggers.contains(rule.kind) {
            // Advance the rule's state machine BEFORE the cooldown /
            // suppression gates. Extreme episodes track their apex and
            // band-exit every tick; gating this on cooldown freezes the
            // episode mid-flight, so its band-exit is never processed and
            // the fallback "near-peak" fire is deferred to the instant the
            // cooldown lifts — a stale second post long after the spike is
            // over. So we evaluate first (which lets the episode close
            // cleanly), then decide whether the fire is allowed to post.
            guard let captureDate = shouldFire(rule: rule, current: current) else { continue }
            if inCooldown(rule.kind, at: current.date) { continue }
            if suppressNearPriorityEvents,
               Self.suppressibleTriggers.contains(rule.kind),
               suppressedForDissonance(at: current.date, window: suppressionWindow, current: current) {
                continue
            }
            fired.append(FiredTrigger(kind: rule.kind, captureDate: captureDate))
            lastFiredAt[rule.kind] = current.date
        }
        return fired
    }

    private func suppressedForDissonance(
        at date: Date,
        window: TimeInterval,
        current: SnapshotStats
    ) -> Bool {
        // Lookback: any priority trigger fired in the configured window?
        for kind in Self.priorityTriggers {
            if let last = lastFiredAt[kind], date.timeIntervalSince(last) < window {
                return true
            }
        }
        // Convergence: all 6 overtones simultaneously active on hour or day.
        // When this is true, the dissonance meter is climbing for a clear
        // geometric reason and a separate dissonance post duplicates the
        // moment. Hour and day fire often enough to materially cut volume.
        if current.allOvertonesActiveInHour || current.allOvertonesActiveInDay {
            return true
        }
        return false
    }

    private func inCooldown(_ kind: SnapshotTrigger, at date: Date) -> Bool {
        // Direct cooldown
        if let last = lastFiredAt[kind] {
            let cooldown = rules.first(where: { $0.kind == kind })?.cooldownSeconds ?? kind.defaultCooldown
            if date.timeIntervalSince(last) < cooldown { return true }
        }
        // Paired cooldown (dissonance ↔ entropy). When the toggle is on,
        // the meter's twin fire ALSO counts — using the twin's own
        // configured cooldown so each side respects the user's intent
        // for that rule independently.
        if pairMeterCooldowns, let paired = Self.meterCooldownPairs[kind] {
            if let pairedLast = lastFiredAt[paired] {
                let pairedCooldown = rules.first(where: { $0.kind == paired })?.cooldownSeconds ?? paired.defaultCooldown
                if date.timeIntervalSince(pairedLast) < pairedCooldown { return true }
            }
        }
        return false
    }

    // MARK: rule dispatch

    /// Returns the `Date` the fired snapshot should depict, or `nil` if the
    /// rule didn't fire. Edge/boundary/onset rules fire "now" (`current.date`);
    /// extreme rules return their episode apex (see `updateExtreme`).
    private func shouldFire(rule: TriggerRule, current: SnapshotStats) -> Date? {
        switch rule.kind {
        case .manual:
            return nil

        // Legacy triggers — semantics replaced by year/moonGeometryPeak.
        // Return nil so any saved-and-enabled rule of these kinds is a
        // no-op until the user removes it from the UI.
        case .newMoon, .fullMoon, .firstQuarter, .lastQuarter, .yearBoundary:
            return nil

        case .yearGeometryPeak:
            return current.yearPeakingShapes.subtracting(previousYearPeaking).isEmpty ? nil : current.date
        case .moonGeometryPeak:
            return current.moonPeakingShapes.subtracting(previousMoonPeaking).isEmpty ? nil : current.date
        case .dayBoundary:
            return crossedCalendarBoundary(current: current, component: .day) ? current.date : nil
        case .halfDayBoundary:
            return crossedHalfDay(current: current) ? current.date : nil

        case .dissonanceHigh:
            return crossedRising(current: Double(current.tenneyMeterPercent), threshold: rule.thresholdPercent, key: .dissonanceHigh) ? current.date : nil
        case .dissonanceLow:
            return crossedFalling(current: Double(current.tenneyMeterPercent), threshold: rule.thresholdPercent, key: .dissonanceLow) ? current.date : nil
        case .entropyHigh:
            return crossedRising(current: Double(current.entropyMeterPercent), threshold: rule.thresholdPercent, key: .entropyHigh) ? current.date : nil
        case .entropyLow:
            return crossedFalling(current: Double(current.entropyMeterPercent), threshold: rule.thresholdPercent, key: .entropyLow) ? current.date : nil

        case .dissonanceExtremeHigh:
            return updateExtreme(kind: .dissonanceExtremeHigh, value: Double(current.tenneyMeterPercent), threshold: rule.thresholdPercent ?? 100, direction: .high, at: current.date)
        case .dissonanceExtremeLow:
            return updateExtreme(kind: .dissonanceExtremeLow, value: Double(current.tenneyMeterPercent), threshold: rule.thresholdPercent ?? 2, direction: .low, at: current.date)
        case .entropyExtremeHigh:
            return updateExtreme(kind: .entropyExtremeHigh, value: Double(current.entropyMeterPercent), threshold: rule.thresholdPercent ?? 100, direction: .high, at: current.date)
        case .entropyExtremeLow:
            return updateExtreme(kind: .entropyExtremeLow, value: Double(current.entropyMeterPercent), threshold: rule.thresholdPercent ?? 2, direction: .low, at: current.date)

        case .chordOnset:
            let currentSet = Set(current.currentChords.map(\.abbreviation))
            let added = currentSet.subtracting(previousChordSet)
            return added.isEmpty ? nil : current.date

        case .phaseClosed:
            // Multi-timeframe: ≥2 timeframes closed *simultaneously* and at
            // least one of them transitioned from open to closed since the
            // previous tick (otherwise we'd refire while the state holds).
            let closedNow = current.phaseClosure.filter { $0.value }.keys
            guard closedNow.count >= 2 else { return nil }
            for tf in closedNow {
                if previousClosureByTimeframe[tf] == false || previousClosureByTimeframe[tf] == nil {
                    return current.date
                }
            }
            return nil

        case .phaseClosedYear:        return closedTransition(timeframe: .year, current: current) ? current.date : nil
        case .phaseClosedMoon:        return closedTransition(timeframe: .moon, current: current) ? current.date : nil
        case .phaseClosedQuarterMoon: return closedTransition(timeframe: .quarterMoon, current: current) ? current.date : nil
        case .phaseClosedDay:         return closedTransition(timeframe: .day, current: current) ? current.date : nil
        case .phaseClosedHour:        return closedTransition(timeframe: .hour, current: current) ? current.date : nil
        }
    }

    // MARK: helpers

    private func closedTransition(timeframe tf: TimeFrame, current: SnapshotStats) -> Bool {
        let now = current.phaseClosure[tf] ?? false
        let prior = previousClosureByTimeframe[tf] ?? false
        return now && !prior
    }

    private func crossedRising(current value: Double, threshold: Double?, key: SnapshotTrigger) -> Bool {
        guard let threshold else { return false }
        guard let previous = previousStats else { return false }
        let priorValue: Double
        switch key {
        case .dissonanceHigh: priorValue = Double(previous.tenneyMeterPercent)
        case .entropyHigh:    priorValue = Double(previous.entropyMeterPercent)
        default: return false
        }
        return priorValue < threshold && value >= threshold
    }

    private func crossedFalling(current value: Double, threshold: Double?, key: SnapshotTrigger) -> Bool {
        guard let threshold else { return false }
        guard let previous = previousStats else { return false }
        let priorValue: Double
        switch key {
        case .dissonanceLow: priorValue = Double(previous.tenneyMeterPercent)
        case .entropyLow:    priorValue = Double(previous.entropyMeterPercent)
        default: return false
        }
        return priorValue > threshold && value <= threshold
    }

    /// Updates the running extreme episode for `kind`. Returns the `Date`
    /// the snapshot should depict (or `nil` for no fire) once per episode
    /// when either (a) we first enter the extreme band, or (b) we begin
    /// descent from the apex by `extremeDescentMargin`. The fallback fire
    /// at episode-exit guarantees we don't miss a short-lived spike.
    ///
    /// Entry fires at the entry instant; descent and fallback fires return
    /// the episode's `apexDate` — the actual peak/trough, which by then is
    /// a few ticks in the past. The caller reconstructs that instant (the
    /// render pipeline is a pure function of the date), so the snapshot
    /// shows the extreme itself rather than the frame it fired on — which,
    /// for the fallback path, is already back outside the band.
    private func updateExtreme(
        kind: SnapshotTrigger,
        value: Double,
        threshold: Double,
        direction: ExtremeEpisode.Direction,
        at date: Date
    ) -> Date? {
        let inBand: Bool = direction == .high ? value >= threshold : value <= threshold
        if inBand {
            if extremes[kind] == nil {
                extremes[kind] = ExtremeEpisode(direction: direction, apex: value, apexDate: date, peakFired: false, entryFired: true)
                return date   // entry fire (apex == entry instant)
            } else {
                var episode = extremes[kind]!
                let isNewApex = direction == .high ? value > episode.apex : value < episode.apex
                if isNewApex {
                    episode.apex = value
                    episode.apexDate = date
                    extremes[kind] = episode
                } else if !episode.peakFired {
                    // descent check
                    let offset = direction == .high ? episode.apex - value : value - episode.apex
                    let apexFromThreshold = direction == .high ? episode.apex - threshold : threshold - episode.apex
                    let descentNeeded = max(2.0, apexFromThreshold * Self.extremeDescentMargin * 20)
                    if offset >= descentNeeded {
                        episode.peakFired = true
                        extremes[kind] = episode
                        return episode.apexDate   // descent fire — capture the peak
                    }
                }
            }
            return nil
        } else {
            // Left the band. If we never fired peak inside, fallback fire at
            // the apex we recorded (NOT `date`, which is already out of band).
            if let episode = extremes[kind] {
                extremes[kind] = nil
                if !episode.peakFired && episode.entryFired {
                    return episode.apexDate   // fallback near-peak fire
                }
            }
            return nil
        }
    }

    private func crossedMoonQuadrant(_ kind: SnapshotTrigger, current: SnapshotStats) -> Bool {
        guard let previous = previousStats else { return false }
        let target: Double
        switch kind {
        case .newMoon:      target = 0.0
        case .firstQuarter: target = 0.25
        case .fullMoon:     target = 0.5
        case .lastQuarter:  target = 0.75
        default: return false
        }
        return crossedFraction(previousPhase: previous.moonPhase, currentPhase: current.moonPhase, target: target)
    }

    /// Detects when a circular `target` value falls inside the open
    /// arc (previousPhase, currentPhase) modulo 1, accounting for the
    /// 0→1 wraparound.
    private func crossedFraction(previousPhase: Double, currentPhase: Double, target: Double) -> Bool {
        let p = previousPhase
        let c = currentPhase
        if c >= p {
            return target > p && target <= c
        }
        // Wrap-around.
        return target > p || target <= c
    }

    private func crossedCalendarBoundary(current: SnapshotStats, component: Calendar.Component) -> Bool {
        guard let previous = previousStats else { return false }
        // UTC, matching the rest of the system (TimeFrame degrees,
        // PhaseEpoch, caption timestamps). Local-time boundaries would
        // shift the firing instant by the user's tz offset and were
        // missing 00:00 UTC for any non-UTC user.
        let cal = TimeFrame.utcCalendar
        return cal.component(component, from: previous.date) != cal.component(component, from: current.date)
    }

    private func crossedHalfDay(current: SnapshotStats) -> Bool {
        guard let previous = previousStats else { return false }
        let cal = TimeFrame.utcCalendar
        let priorHalf = cal.component(.hour, from: previous.date) / 12
        let currentHalf = cal.component(.hour, from: current.date) / 12
        return priorHalf != currentHalf || !cal.isDate(previous.date, inSameDayAs: current.date)
    }

    // MARK: log

    public struct FiringRecord: Identifiable, Equatable {
        public let id = UUID()
        public let trigger: SnapshotTrigger
        public let date: Date
        public let imageURL: URL?
        public let wroteToDisk: Bool
        public let xPostState: XPostState
        public let captionHadURL: Bool

        public init(
            trigger: SnapshotTrigger,
            date: Date,
            imageURL: URL?,
            wroteToDisk: Bool,
            xPostState: XPostState = .notAttempted,
            captionHadURL: Bool = false
        ) {
            self.trigger = trigger
            self.date = date
            self.imageURL = imageURL
            self.wroteToDisk = wroteToDisk
            self.xPostState = xPostState
            self.captionHadURL = captionHadURL
        }
    }

    public enum XPostState: Equatable {
        case notAttempted
        case posted(tweetURL: URL)
        case rateLimited(retryAfter: Date?)
        case failed(message: String)
    }

    public func recordFiring(
        _ trigger: SnapshotTrigger,
        at date: Date,
        imageURL: URL?,
        wroteToDisk: Bool,
        xPostState: XPostState = .notAttempted,
        captionHadURL: Bool = false
    ) {
        let record = FiringRecord(
            trigger: trigger,
            date: date,
            imageURL: imageURL,
            wroteToDisk: wroteToDisk,
            xPostState: xPostState,
            captionHadURL: captionHadURL
        )
        firingLog.insert(record, at: 0)
        if firingLog.count > 200 { firingLog.removeLast(firingLog.count - 200) }
    }

    /// Firings in the last 24h. Surfaced in the settings UI so the user
    /// can read the cadence before turning on day/half-day rules.
    public var firingsLast24h: Int {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return firingLog.filter { $0.date >= cutoff }.count
    }

    // MARK: profile import / export

    /// Snapshot of the trigger config that can be written to a JSON file
    /// and restored later. Captures rules + the suppression toggles, but
    /// not transient state (firingLog, lastFiredAt) or X credentials.
    public struct Profile: Codable {
        public let version: Int
        public let savedAt: Date
        public let rules: [TriggerRule]
        public let suppressNearPriorityEvents: Bool
        public let priorityEventWindowMinutes: Double
        public let pairMeterCooldowns: Bool

        @MainActor
        public init(from evaluator: TriggerEvaluator) {
            self.version = 1
            self.savedAt = Date()
            self.rules = evaluator.rules
            self.suppressNearPriorityEvents = evaluator.suppressNearPriorityEvents
            self.priorityEventWindowMinutes = evaluator.priorityEventWindowMinutes
            self.pairMeterCooldowns = evaluator.pairMeterCooldowns
        }
    }

    public func exportProfile() -> Profile {
        Profile(from: self)
    }

    /// Apply a previously-exported profile. Merges so future-added rule
    /// kinds remain at their defaults rather than getting stripped.
    public func importProfile(_ profile: Profile) {
        let imported = Set(profile.rules.map(\.kind))
        let added = Self.makeDefaultRules().filter { !imported.contains($0.kind) }
        self.rules = profile.rules + added
        self.suppressNearPriorityEvents = profile.suppressNearPriorityEvents
        self.priorityEventWindowMinutes = profile.priorityEventWindowMinutes
        self.pairMeterCooldowns = profile.pairMeterCooldowns
    }
}
