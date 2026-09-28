import Foundation

/// Shared pairwise dissonance and entropy calculations. Both iOS Misc page
/// and Mac dissonance widget call into these so the math is consistent
/// across platforms.
public enum DissonanceMath {
    /// JI ratio set used by every per-pair calculation. 5-limit + harmonic
    /// 7th, anchored at A — same set the cents wheel labels with.
    public static let jiRatios: [(n: Int, d: Int)] = [
        (1, 1), (16, 15), (9, 8), (6, 5), (5, 4), (4, 3),
        (45, 32), (3, 2), (8, 5), (5, 3), (7, 4), (15, 8), (2, 1),
    ]

    /// Per-pair Tenney height — weighted average of JI ratio complexities
    /// using a Gaussian kernel over cents distance.
    public static func pairTenney(cents: Double, sigma: Double = 30) -> Double {
        let octave = octaveCents(cents)
        var weighted: Double = 0
        var weightSum: Double = 0
        for (n, d) in jiRatios {
            let ratioCents = 1200 * log2(Double(n) / Double(d))
            let dist = min(
                abs(octave - ratioCents),
                abs(octave - ratioCents - 1200),
                abs(octave - ratioCents + 1200)
            )
            let w = exp(-dist * dist / (2 * sigma * sigma))
            weighted += log2(Double(n * d)) * w
            weightSum += w
        }
        return weightSum > 0 ? weighted / weightSum : log2(45.0 * 32.0)
    }

    /// Per-pair Shannon entropy — entropy of the JI-ratio identification
    /// distribution. High = ambiguous interval; low = clearly resolves to
    /// one JI ratio.
    public static func pairEntropy(cents: Double, sigma: Double = 30) -> Double {
        let octave = octaveCents(cents)
        var probs: [Double] = []
        probs.reserveCapacity(jiRatios.count)
        for (n, d) in jiRatios {
            let ratioCents = 1200 * log2(Double(n) / Double(d))
            let dist = min(
                abs(octave - ratioCents),
                abs(octave - ratioCents - 1200),
                abs(octave - ratioCents + 1200)
            )
            probs.append(exp(-dist * dist / (2 * sigma * sigma)))
        }
        let sum = probs.reduce(0, +)
        guard sum > 0 else { return log(Double(jiRatios.count)) }
        var h: Double = 0
        for p in probs where p > 1e-10 {
            let pn = p / sum
            h -= pn * log(pn)
        }
        return h
    }

    /// Amplitude-weighted total Tenney across all active pairs.
    public static func totalTenney(_ tones: [HarmonicTone]) -> Double {
        guard tones.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 0..<tones.count {
            for j in (i + 1)..<tones.count {
                let a = tones[i]
                let b = tones[j]
                guard a.frequency > 0, b.frequency > 0 else { continue }
                let lo = min(a.frequency, b.frequency)
                let hi = max(a.frequency, b.frequency)
                let cents = abs(1200 * log2(hi / lo))
                total += pairTenney(cents: cents) * a.amplitude * b.amplitude
            }
        }
        return total
    }

    /// Amplitude-weighted total entropy across all active pairs.
    public static func totalEntropy(_ tones: [HarmonicTone]) -> Double {
        guard tones.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 0..<tones.count {
            for j in (i + 1)..<tones.count {
                let a = tones[i]
                let b = tones[j]
                guard a.frequency > 0, b.frequency > 0 else { continue }
                let cents = abs(1200 * log2(b.frequency / a.frequency))
                total += pairEntropy(cents: cents) * a.amplitude * b.amplitude
            }
        }
        return total
    }

    private static func octaveCents(_ cents: Double) -> Double {
        (cents.truncatingRemainder(dividingBy: 1200) + 1200)
            .truncatingRemainder(dividingBy: 1200)
    }
}

/// Calibration constants for the dissonance and entropy meters.
///
/// `...MeterMax` is the per-pair value at which the meter reads 100%,
/// derived from the 99th percentile of a 1-year simulation (5-min
/// sampling from `PhaseEpoch.instant`, `includeFundamentals = false`).
/// Values above this trigger the spillover overlay. Spillover display
/// is capped at `+spilloverDisplayCap%` to keep the UI bounded.
///
/// NOTE: these values predate the v2 changes (solstice-anchored tropical
/// year, Metonic epoch, {7/3} and {8/3} winding tones). The winding tones
/// add pairs with new pitch classes (7/6, 4/3), which shifts the
/// distribution — re-run the Mac app's Calibration menu and update these.
public enum DissonanceCalibration {
    public static let tenneyMeterMax:  Double = 3.95
    public static let entropyMeterMax: Double = 0.336

    /// Upper bound on the spillover percentage shown in the UI. The
    /// simulation max came in around +225% for Tenney and +180% for
    /// Entropy; 300% gives generous headroom for once-a-year extremes
    /// while preventing pathological cases from producing absurd text.
    public static let spilloverDisplayCap: Int = 300
}
