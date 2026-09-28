import Foundation

/// One-year (or any-duration) headless simulation of the dissonance and
/// entropy meters so we can see the *practical* range — the theoretical
/// per-pair max overshoots reality by a lot, and the empirical-per-pair
/// max we compute from the static tone set still doesn't account for
/// realistic amplitude-weighted maxes (since overtones don't all peak at
/// once). Use the simulation output to:
///   1. Pick the cap for the dissonance/entropy meter normalization
///   2. Decide where to draw the spillover (red) threshold
///   3. Sanity-check changes to the underlying math
public enum DissonanceCalibrator {
    public struct Stats: Sendable, CustomStringConvertible {
        public let sampleCount: Int
        public let sampleIntervalSeconds: Double
        public let duration: TimeInterval

        public let totalTenneyMax:    Double
        public let totalTenneyP99:    Double
        public let totalTenneyP95:    Double
        public let totalTenneyMedian: Double
        public let totalTenneyMin:    Double
        public let totalTenneyMean:   Double

        public let totalEntropyMax:    Double
        public let totalEntropyP99:    Double
        public let totalEntropyP95:    Double
        public let totalEntropyMedian: Double
        public let totalEntropyMin:    Double
        public let totalEntropyMean:   Double

        public let perPairTenneyMax:    Double
        public let perPairTenneyP99:    Double
        public let perPairTenneyP95:    Double
        public let perPairTenneyMedian: Double

        public let perPairEntropyMax:    Double
        public let perPairEntropyP99:    Double
        public let perPairEntropyP95:    Double
        public let perPairEntropyMedian: Double

        public let activeToneCountMax: Int
        public let activeToneCountMean: Double

        public var description: String {
            let dayCount = duration / 86400.0
            return """
            === DissonanceCalibrator stats ===
              duration:        \(String(format: "%.1f", dayCount)) days
              sample interval: \(Int(sampleIntervalSeconds)) s
              samples:         \(sampleCount)

              active tones:    max \(activeToneCountMax), mean \(String(format: "%.2f", activeToneCountMean))

              -- TENNEY total --
                max     \(String(format: "%9.3f", totalTenneyMax))
                p99     \(String(format: "%9.3f", totalTenneyP99))
                p95     \(String(format: "%9.3f", totalTenneyP95))
                median  \(String(format: "%9.3f", totalTenneyMedian))
                min     \(String(format: "%9.3f", totalTenneyMin))
                mean    \(String(format: "%9.3f", totalTenneyMean))

              -- ENTROPY total --
                max     \(String(format: "%9.3f", totalEntropyMax))
                p99     \(String(format: "%9.3f", totalEntropyP99))
                p95     \(String(format: "%9.3f", totalEntropyP95))
                median  \(String(format: "%9.3f", totalEntropyMedian))
                min     \(String(format: "%9.3f", totalEntropyMin))
                mean    \(String(format: "%9.3f", totalEntropyMean))

              -- TENNEY per-pair --
                max     \(String(format: "%9.3f", perPairTenneyMax))
                p99     \(String(format: "%9.3f", perPairTenneyP99))
                p95     \(String(format: "%9.3f", perPairTenneyP95))
                median  \(String(format: "%9.3f", perPairTenneyMedian))
                (current meter cap: \(String(format: "%.3f", DissonanceCalibration.tenneyMeterMax)))

              -- ENTROPY per-pair --
                max     \(String(format: "%9.3f", perPairEntropyMax))
                p99     \(String(format: "%9.3f", perPairEntropyP99))
                p95     \(String(format: "%9.3f", perPairEntropyP95))
                median  \(String(format: "%9.3f", perPairEntropyMedian))
                (current meter cap: \(String(format: "%.3f", DissonanceCalibration.entropyMeterMax)))
            """
        }
    }

    /// Run a synchronous simulation. For 1 year at 60s sampling this is
    /// ~525K samples and takes a few seconds on Apple silicon. Use a
    /// coarser `sampleIntervalSeconds` (e.g. 300 s = 5 min) for a first
    /// pass; the percentile values converge fast.
    public static func simulate(
        startDate: Date = PhaseEpoch.instant,
        duration: TimeInterval = 365.25 * 86400,
        sampleIntervalSeconds: Double = 60,
        scaling: Int = 23,
        includeFundamentals: Bool = false
    ) -> Stats {
        let nSamples = max(1, Int(duration / sampleIntervalSeconds))

        var totalTenneys: [Double] = []
        totalTenneys.reserveCapacity(nSamples)
        var totalEntropies: [Double] = []
        totalEntropies.reserveCapacity(nSamples)

        var perPairTenneys: [Double] = []
        perPairTenneys.reserveCapacity(nSamples)
        var perPairEntropies: [Double] = []
        perPairEntropies.reserveCapacity(nSamples)

        var toneCountSum: Int = 0
        var toneCountMax: Int = 0

        for i in 0..<nSamples {
            let t = startDate.addingTimeInterval(Double(i) * sampleIntervalSeconds)
            let raw = HarmonicAnalysis.activeTones(at: t, scales: [scaling])
            let tones = includeFundamentals ? raw : raw.filter { !$0.isFundamental }
            toneCountSum += tones.count
            if tones.count > toneCountMax { toneCountMax = tones.count }

            let pairCount = max(1, tones.count * (tones.count - 1) / 2)
            let totalT = DissonanceMath.totalTenney(tones)
            let totalE = DissonanceMath.totalEntropy(tones)
            let perPairT = totalT / Double(pairCount)
            let perPairE = totalE / Double(pairCount)

            totalTenneys.append(totalT)
            totalEntropies.append(totalE)
            perPairTenneys.append(perPairT)
            perPairEntropies.append(perPairE)
        }

        totalTenneys.sort()
        totalEntropies.sort()
        perPairTenneys.sort()
        perPairEntropies.sort()

        func percentile(_ arr: [Double], _ p: Double) -> Double {
            guard !arr.isEmpty else { return 0 }
            let idx = min(arr.count - 1, max(0, Int(p * Double(arr.count - 1))))
            return arr[idx]
        }
        func mean(_ arr: [Double]) -> Double {
            guard !arr.isEmpty else { return 0 }
            return arr.reduce(0, +) / Double(arr.count)
        }

        return Stats(
            sampleCount: nSamples,
            sampleIntervalSeconds: sampleIntervalSeconds,
            duration: duration,

            totalTenneyMax:    totalTenneys.last ?? 0,
            totalTenneyP99:    percentile(totalTenneys, 0.99),
            totalTenneyP95:    percentile(totalTenneys, 0.95),
            totalTenneyMedian: percentile(totalTenneys, 0.50),
            totalTenneyMin:    totalTenneys.first ?? 0,
            totalTenneyMean:   mean(totalTenneys),

            totalEntropyMax:    totalEntropies.last ?? 0,
            totalEntropyP99:    percentile(totalEntropies, 0.99),
            totalEntropyP95:    percentile(totalEntropies, 0.95),
            totalEntropyMedian: percentile(totalEntropies, 0.50),
            totalEntropyMin:    totalEntropies.first ?? 0,
            totalEntropyMean:   mean(totalEntropies),

            perPairTenneyMax:    perPairTenneys.last ?? 0,
            perPairTenneyP99:    percentile(perPairTenneys, 0.99),
            perPairTenneyP95:    percentile(perPairTenneys, 0.95),
            perPairTenneyMedian: percentile(perPairTenneys, 0.50),

            perPairEntropyMax:    perPairEntropies.last ?? 0,
            perPairEntropyP99:    percentile(perPairEntropies, 0.99),
            perPairEntropyP95:    percentile(perPairEntropies, 0.95),
            perPairEntropyMedian: percentile(perPairEntropies, 0.50),

            activeToneCountMax: toneCountMax,
            activeToneCountMean: Double(toneCountSum) / Double(nSamples)
        )
    }
}
