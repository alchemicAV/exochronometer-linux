import Foundation

/// One detected chord — which tones form it, which pattern they match,
/// and how close the match is.
public struct ChordMatch: Sendable, Hashable {
    public let pattern: ChordPattern
    public let tones: [HarmonicTone]
    public let fitCents: Double

    public var id: String {
        "\(pattern.abbreviation)|" + tones.map(\.id).joined(separator: ",")
    }
}

public enum ChordDetector {
    /// Per-interval tolerance — a chord "matches" if every required
    /// interval lies within ±tolerance of its ideal cents value. ±25¢ is
    /// the perceptual "noticeably stretched but still recognisable as
    /// that chord" threshold.
    public static let tolerance: Double = 25

    /// Octave-equivalence-aware identity for a chord match. HR:4 and HR:8
    /// share the same odd-part (1), so any chord pattern matched twice with
    /// just these swapped collapses to a single signature. A winding tone's
    /// pitch class is oddPart(divisions)/oddPart(skip), so {7/3} ("7:3")
    /// stays distinct from the integer 7th harmonic ("7:1").
    public static func pitchClassSignature(of tones: [HarmonicTone], pattern: ChordPattern) -> String {
        let parts = tones
            .map { "\($0.timeframe.rawValue).\(oddPart($0.divisions)):\(oddPart($0.skip))" }
            .sorted()
        return "\(pattern.abbreviation)|\(parts.joined(separator: "+"))"
    }

    static func oddPart(_ n: Int) -> Int { GeometryMath.oddPart(n) }

    /// Find all chord patterns whose constituent tones are currently
    /// active above `amplitudeThreshold`. Sorted by fit (lowest cents
    /// error first). When the same tone subset matches multiple
    /// patterns (e.g. the same triad sitting between major and minor),
    /// only the closest fit is kept.
    public static func detect(
        in tones: [HarmonicTone],
        amplitudeThreshold: Double = 0.3,
        patterns: [ChordPattern] = ChordCatalog.all,
        tolerance: Double = ChordDetector.tolerance
    ) -> [ChordMatch] {
        let active = tones.filter { $0.amplitude >= amplitudeThreshold && $0.frequency > 0 }
        guard active.count >= 2 else { return [] }

        var bestPerSubset: [String: ChordMatch] = [:]

        for pattern in patterns {
            let n = pattern.toneCount
            guard active.count >= n else { continue }
            forEachCombination(active, choose: n) { combo in
                guard let match = match(combo, pattern: pattern, tolerance: tolerance) else { return }
                let key = combo.sorted(by: { $0.frequency < $1.frequency }).map(\.id).joined(separator: ",")
                if let existing = bestPerSubset[key], existing.fitCents <= match.fitCents { return }
                bestPerSubset[key] = match
            }
        }

        // Second pass: dedupe by pitch-class signature so HR:4-vs-HR:8
        // duplicates collapse. Prefer the match with the *higher* total
        // division (more high-octave tones — these have superset firing
        // windows, so they catch every event a lower-octave equivalent
        // would). Tie-break by fit.
        var bestPerSignature: [String: ChordMatch] = [:]
        for match in bestPerSubset.values {
            let sig = pitchClassSignature(of: match.tones, pattern: match.pattern)
            if let existing = bestPerSignature[sig] {
                let existingDivSum = existing.tones.reduce(0) { $0 + $1.divisions }
                let matchDivSum = match.tones.reduce(0) { $0 + $1.divisions }
                if existingDivSum > matchDivSum { continue }
                if existingDivSum == matchDivSum && existing.fitCents <= match.fitCents { continue }
            }
            bestPerSignature[sig] = match
        }
        return bestPerSignature.values.sorted { $0.fitCents < $1.fitCents }
    }

    /// Match a specific tone subset against a specific pattern.
    /// Treats the lowest-frequency tone (in pitch-class) as the root and
    /// computes intervals from it to each higher tone.
    public static func match(
        _ tones: [HarmonicTone],
        pattern: ChordPattern,
        tolerance: Double = ChordDetector.tolerance
    ) -> ChordMatch? {
        guard tones.count == pattern.toneCount else { return nil }
        let sorted = tones.sorted { $0.frequency < $1.frequency }
        let root = sorted[0].frequency

        let actualIntervals: [Double] = sorted.map { tone in
            tone.frequency == root ? 0 : 1200 * log2(tone.frequency / root)
        }
        // Sort both interval lists so we don't depend on input ordering.
        let actualSorted = actualIntervals.sorted()
        let patternSorted = pattern.intervals.sorted()

        var totalError: Double = 0
        for i in 0..<patternSorted.count {
            let actual = octaveReduce(actualSorted[i])
            let expected = octaveReduce(patternSorted[i])
            let dist = circularCentsDistance(actual, expected)
            if dist > tolerance { return nil }
            totalError += dist
        }
        return ChordMatch(pattern: pattern, tones: sorted, fitCents: totalError)
    }

    private static func octaveReduce(_ cents: Double) -> Double {
        let m = cents.truncatingRemainder(dividingBy: 1200)
        return m < 0 ? m + 1200 : m
    }

    private static func circularCentsDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b)
        return min(raw, 1200 - raw)
    }

    private static func forEachCombination<T>(
        _ items: [T],
        choose k: Int,
        body: ([T]) -> Void
    ) {
        guard k > 0, k <= items.count else { return }
        var indices = Array(0..<k)
        let n = items.count
        while true {
            body(indices.map { items[$0] })
            // Advance indices to next combination.
            var i = k - 1
            while i >= 0 && indices[i] == i + n - k { i -= 1 }
            if i < 0 { return }
            indices[i] += 1
            for j in (i + 1)..<k { indices[j] = indices[j - 1] + 1 }
        }
    }
}
