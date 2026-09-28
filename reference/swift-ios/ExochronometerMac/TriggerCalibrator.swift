import Foundation
import SwiftUI
import ExochronometerCore

/// Sampled percentiles of a meter value (0–100+) over a sim window.
/// Lets the UI report "where does the dissonance meter actually spend
/// its time" so the user can pick thresholds that align with the real
/// distribution instead of guessing.
public struct MeterDistribution: Sendable, Equatable, Codable {
    public let p1: Double
    public let p5: Double
    public let p10: Double
    public let p25: Double
    public let p50: Double
    public let p75: Double
    public let p90: Double
    public let p95: Double
    public let p99: Double
    public let mean: Double
    public let min: Double
    public let max: Double
}

/// Per-trigger statistics over a multi-day simulation window. Holds the
/// raw daily counts so the UI can show whatever aggregate the user
/// cares about (min/max/median/mean).
public struct TriggerVolumeStats: Sendable, Equatable, Codable {
    public let perDay: [Int]
    public var total: Int { perDay.reduce(0, +) }
    public var min: Int { perDay.min() ?? 0 }
    public var max: Int { perDay.max() ?? 0 }
    public var mean: Double {
        perDay.isEmpty ? 0 : Double(total) / Double(perDay.count)
    }
    public var median: Double {
        let sorted = perDay.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return Double(sorted[mid])
    }
}

/// Full result of a calibration run. Per-trigger stats plus a combined
/// "total firings per day" stat across every enabled rule.
public struct TriggerCalibrationResult: Sendable, Equatable, Codable {
    public let window: DateInterval
    public let tickSeconds: Double
    public let perTrigger: [SnapshotTrigger: TriggerVolumeStats]
    public let combined: TriggerVolumeStats
    public let elapsedSeconds: Double
    /// When true, the calibrator skipped ChordProjector for speed and
    /// chord-onset firings were not counted. The UI surfaces this so
    /// the user knows to add a manual estimate.
    public let chordsSkipped: Bool
    /// Sampled distribution of Tenney meter percent across the sim.
    /// Use it to spot where the meter actually spends its time and
    /// pick thresholds at matching percentiles.
    public let tenneyDistribution: MeterDistribution
    public let entropyDistribution: MeterDistribution
}

/// Runs the trigger engine against a long sequence of computed
/// `SnapshotStats` values to estimate firing volume. Used to answer
/// "how many posts per day would this rule set produce on average?"
/// without writing any files.
@MainActor
public final class TriggerCalibrator: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var progress: Double = 0   // 0…1
    @Published public private(set) var status: String = ""
    @Published public private(set) var result: TriggerCalibrationResult? = nil

    private var task: Task<Void, Never>? = nil

    public init() {}

    /// Run the simulation. `rules` should be the full rule set the user
    /// wants to evaluate; the calibrator runs them as-if all enabled were
    /// active. `days` is the simulation window. `tickSeconds` controls
    /// resolution — shorter catches faster events but takes longer to
    /// run. 300s (5min) is a good default for testing chord onsets +
    /// extreme dissonance.
    public func run(
        rules: [TriggerRule],
        startDate: Date = Date(),
        days: Int = 30,
        tickSeconds: Double = 300,
        skipChordComputation: Bool = false,
        suppressNearPriorityEvents: Bool = false,
        priorityEventWindowMinutes: Double = 30,
        pairMeterCooldowns: Bool = false
    ) {
        cancel()
        isRunning = true
        progress = 0
        status = "starting…"
        result = nil

        let evaluator = TriggerEvaluator(
            simulationRules: rules,
            suppressNearPriorityEvents: suppressNearPriorityEvents,
            priorityEventWindowMinutes: priorityEventWindowMinutes,
            pairMeterCooldowns: pairMeterCooldowns
        )
        let totalSeconds = Double(days) * 86400
        let totalTicks = Int(totalSeconds / tickSeconds)

        task = Task { @MainActor in
            await runLoop(
                evaluator: evaluator,
                startDate: startDate,
                totalSeconds: totalSeconds,
                totalTicks: totalTicks,
                tickSeconds: tickSeconds,
                days: days,
                skipChordComputation: skipChordComputation
            )
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        status = "cancelled"
    }

    /// Empty distribution sentinel for results where one of the sampled
    /// meter streams is unused or empty.
    private static let zeroDistribution = MeterDistribution(
        p1: 0, p5: 0, p10: 0, p25: 0, p50: 0, p75: 0, p90: 0, p95: 0, p99: 0,
        mean: 0, min: 0, max: 0
    )

    private static func distribution(of values: [Double]) -> MeterDistribution {
        guard !values.isEmpty else { return zeroDistribution }
        let sorted = values.sorted()
        func pct(_ p: Double) -> Double {
            let idx = min(sorted.count - 1, max(0, Int(p * Double(sorted.count - 1))))
            return sorted[idx]
        }
        let sum = sorted.reduce(0, +)
        return MeterDistribution(
            p1:  pct(0.01),
            p5:  pct(0.05),
            p10: pct(0.10),
            p25: pct(0.25),
            p50: pct(0.50),
            p75: pct(0.75),
            p90: pct(0.90),
            p95: pct(0.95),
            p99: pct(0.99),
            mean: sum / Double(sorted.count),
            min: sorted.first ?? 0,
            max: sorted.last ?? 0
        )
    }

    private func runLoop(
        evaluator: TriggerEvaluator,
        startDate: Date,
        totalSeconds: Double,
        totalTicks: Int,
        tickSeconds: Double,
        days: Int,
        skipChordComputation: Bool
    ) async {
        var perTriggerCounts: [SnapshotTrigger: [Int]] = [:]
        for kind in SnapshotTrigger.allCases where kind != .manual {
            perTriggerCounts[kind] = Array(repeating: 0, count: days)
        }
        var combinedCounts = Array(repeating: 0, count: days)
        var tenneySamples: [Double] = []
        var entropySamples: [Double] = []
        tenneySamples.reserveCapacity(totalTicks)
        entropySamples.reserveCapacity(totalTicks)

        let startWall = Date()
        var elapsed: TimeInterval = 0
        var tickIdx = 0
        let progressEvery = max(1, totalTicks / 200)

        while elapsed < totalSeconds {
            if Task.isCancelled {
                status = "cancelled"
                isRunning = false
                return
            }
            let tickDate = startDate.addingTimeInterval(elapsed)
            // SnapshotStats is the hot work — moon phase, dissonance,
            // chord matches, phase closure. Build on background actor
            // so we don't pin the main queue while the UI is still alive.
            let stats = await Task.detached(priority: .userInitiated) {
                SnapshotStats(at: tickDate, includeChords: !skipChordComputation)
            }.value
            let fired = evaluator.evaluate(stats: stats)
            let dayIdx = min(days - 1, Int(elapsed / 86400))
            for fire in fired {
                perTriggerCounts[fire.kind]?[dayIdx] += 1
                combinedCounts[dayIdx] += 1
            }
            tenneySamples.append(Double(stats.tenneyMeterPercent))
            entropySamples.append(Double(stats.entropyMeterPercent))
            tickIdx += 1
            elapsed += tickSeconds

            if tickIdx % progressEvery == 0 {
                progress = Double(tickIdx) / Double(totalTicks)
                let pct = Int((progress * 100).rounded())
                status = "simulating · day \(dayIdx + 1) of \(days) · \(pct)%"
            }
        }

        let elapsedWall = Date().timeIntervalSince(startWall)
        let perTrigger: [SnapshotTrigger: TriggerVolumeStats] = perTriggerCounts
            .mapValues { TriggerVolumeStats(perDay: $0) }
        let combined = TriggerVolumeStats(perDay: combinedCounts)
        let window = DateInterval(start: startDate, duration: totalSeconds)
        let tenneyDist = Self.distribution(of: tenneySamples)
        let entropyDist = Self.distribution(of: entropySamples)
        result = TriggerCalibrationResult(
            window: window,
            tickSeconds: tickSeconds,
            perTrigger: perTrigger,
            combined: combined,
            elapsedSeconds: elapsedWall,
            chordsSkipped: skipChordComputation,
            tenneyDistribution: tenneyDist,
            entropyDistribution: entropyDist
        )
        progress = 1
        status = "done · \(Int(elapsedWall))s"
        isRunning = false
    }
}
