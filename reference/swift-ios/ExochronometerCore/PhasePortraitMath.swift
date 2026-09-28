import Foundation

/// Phase-portrait analytics shared by Mac widget and iOS Misc page.
public enum PhasePortraitMath {
    /// Closure tolerance: each tone is considered "closing" if its
    /// cycle count is within `tolerance` of an integer. 0.05 ≈ 18° of
    /// phase error at the window endpoint — barely perceptible visually.
    public static let defaultTolerance: Double = 0.05

    /// A phase portrait curve traces `frequency × window` cycles. The
    /// curve closes (visual loop ending where it started) when every
    /// constituent tone makes an integer number of cycles in the window.
    /// Returns true iff every tone's cycle count is within `tolerance` of
    /// an integer.
    public static func isLoopClosed(
        tones: [HarmonicTone],
        windowSeconds: Double,
        tolerance: Double = defaultTolerance
    ) -> Bool {
        guard !tones.isEmpty, windowSeconds > 0 else { return false }
        for tone in tones {
            let cycles = tone.frequency * windowSeconds
            let off = abs(cycles - cycles.rounded())
            if off > tolerance { return false }
        }
        return true
    }
}
