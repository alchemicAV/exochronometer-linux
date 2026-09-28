import Foundation

/// Time window the cumulative dissonance graph covers. Drives sampling
/// density and X-axis labels.
public enum DissonanceGraphRange: String, Codable, CaseIterable, Sendable {
    case oneDay
    case oneQuarterMoon

    public var seconds: TimeInterval {
        switch self {
        case .oneDay:         return 86400
        case .oneQuarterMoon: return 86400 * 29.530588853 / 4
        }
    }

    public var label: String {
        switch self {
        case .oneDay:         return "1 DAY"
        case .oneQuarterMoon: return "1 QTR MOON"
        }
    }
}

public struct DissonanceGraphSample: Sendable {
    public let date: Date
    public let tenneyNormalized: Double   // perPair / meterMax (>1 means spillover)
    public let entropyNormalized: Double
    public let pairCount: Int

    public init(date: Date, tenneyNormalized: Double, entropyNormalized: Double, pairCount: Int) {
        self.date = date
        self.tenneyNormalized = tenneyNormalized
        self.entropyNormalized = entropyNormalized
        self.pairCount = pairCount
    }
}

/// Pure-function sampler. Caller is responsible for running this on a
/// background priority — 240 buckets × tone-set computation can take
/// ~1 s wall-clock.
public enum DissonanceGraphSampler {
    public static func samples(
        endingAt endDate: Date,
        range: DissonanceGraphRange,
        includeFundamentals: Bool,
        scaling: Int = 23,
        bucketCount: Int = 240
    ) -> [DissonanceGraphSample] {
        let rangeSeconds = range.seconds
        let bucketSeconds = rangeSeconds / Double(bucketCount)
        var out: [DissonanceGraphSample] = []
        out.reserveCapacity(bucketCount)
        for i in 0..<bucketCount {
            let offset = Double(bucketCount - i) * bucketSeconds
            let date = endDate.addingTimeInterval(-offset)
            var tones = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
            if !includeFundamentals {
                tones.removeAll { $0.isFundamental }
            }
            let pairCount = max(1, tones.count * (tones.count - 1) / 2)
            let tenneyPerPair = DissonanceMath.totalTenney(tones) / Double(pairCount)
            let entropyPerPair = DissonanceMath.totalEntropy(tones) / Double(pairCount)
            let tNorm = tenneyPerPair / DissonanceCalibration.tenneyMeterMax
            let eNorm = entropyPerPair / DissonanceCalibration.entropyMeterMax
            out.append(DissonanceGraphSample(
                date: date,
                tenneyNormalized: tNorm,
                entropyNormalized: eNorm,
                pairCount: pairCount
            ))
        }
        return out
    }
}
