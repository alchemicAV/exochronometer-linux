import Foundation

/// One recognized chord shape — its intervals from the root in cents.
/// `intervals[0]` is always 0 (the root itself).
public struct ChordPattern: Sendable, Hashable {
    public let name: String
    public let abbreviation: String
    public let intervals: [Double]

    public var toneCount: Int { intervals.count }

    public init(name: String, abbreviation: String, intervals: [Double]) {
        self.name = name
        self.abbreviation = abbreviation
        self.intervals = intervals
    }
}

/// Recognized chord vocabulary used by the detector and the projector.
/// 5-limit + harmonic 7th; all intervals quoted from JI ratios.
public enum ChordCatalog {
    private static let octave   = 1200.0
    private static let p5       = 1200 * log2(3.0 / 2.0)      // 701.96
    private static let p4       = 1200 * log2(4.0 / 3.0)      // 498.04
    private static let m3       = 1200 * log2(6.0 / 5.0)      // 315.64
    private static let M3       = 1200 * log2(5.0 / 4.0)      // 386.31
    private static let M2       = 1200 * log2(9.0 / 8.0)      // 203.91
    private static let m2       = 1200 * log2(16.0 / 15.0)    // 111.73
    private static let M6       = 1200 * log2(5.0 / 3.0)      // 884.36
    private static let m6       = 1200 * log2(8.0 / 5.0)      // 813.69
    private static let M7       = 1200 * log2(15.0 / 8.0)     // 1088.27
    private static let m7       = 1200 * log2(16.0 / 9.0)     // 996.09
    private static let h7       = 1200 * log2(7.0 / 4.0)      // 968.83
    private static let tt       = 1200 * log2(45.0 / 32.0)    // 590.22

    public static let intervals: [ChordPattern] = [
        ChordPattern(name: "Octave",            abbreviation: "8va", intervals: [0, octave]),
        ChordPattern(name: "Perfect Fifth",     abbreviation: "P5",  intervals: [0, p5]),
        ChordPattern(name: "Perfect Fourth",    abbreviation: "P4",  intervals: [0, p4]),
        ChordPattern(name: "Major Third",       abbreviation: "M3",  intervals: [0, M3]),
        ChordPattern(name: "Minor Third",       abbreviation: "m3",  intervals: [0, m3]),
        ChordPattern(name: "Major Second",      abbreviation: "M2",  intervals: [0, M2]),
        ChordPattern(name: "Major Sixth",       abbreviation: "M6",  intervals: [0, M6]),
        ChordPattern(name: "Minor Sixth",       abbreviation: "m6",  intervals: [0, m6]),
        ChordPattern(name: "Major Seventh",     abbreviation: "M7",  intervals: [0, M7]),
        ChordPattern(name: "Harmonic Seventh",  abbreviation: "h7",  intervals: [0, h7]),
        ChordPattern(name: "Tritone",           abbreviation: "TT",  intervals: [0, tt]),
    ]

    public static let triads: [ChordPattern] = [
        ChordPattern(name: "Major Triad",       abbreviation: "maj", intervals: [0, M3, p5]),
        ChordPattern(name: "Minor Triad",       abbreviation: "min", intervals: [0, m3, p5]),
        ChordPattern(name: "Diminished Triad",  abbreviation: "dim", intervals: [0, m3, tt]),
        ChordPattern(name: "Augmented Triad",   abbreviation: "aug", intervals: [0, M3, m6 + m2]),
        ChordPattern(name: "Suspended 2",       abbreviation: "sus2",intervals: [0, M2, p5]),
        ChordPattern(name: "Suspended 4",       abbreviation: "sus4",intervals: [0, p4, p5]),
        // "Open Fifth + 8va" (0, P5, octave) was removed 2026-06-10: with
        // only two distinct pitch classes it is an interval in chord
        // costume, and the exact MN:7/3 ↔ MN/QM:7 winding fifth left it
        // one drifting day-tone away from firing five times a day.
        // Rule: a chord requires ≥3 distinct pitch classes.
    ]

    public static let tetrads: [ChordPattern] = [
        ChordPattern(name: "Major 7",           abbreviation: "maj7",  intervals: [0, M3, p5, M7]),
        ChordPattern(name: "Minor 7",           abbreviation: "min7",  intervals: [0, m3, p5, m7]),
        ChordPattern(name: "Dominant 7",        abbreviation: "dom7",  intervals: [0, M3, p5, m7]),
        ChordPattern(name: "Harmonic Dom 7",    abbreviation: "h-dom7",intervals: [0, M3, p5, h7]),
        ChordPattern(name: "Half-Diminished 7", abbreviation: "m7♭5",  intervals: [0, m3, tt, m7]),
        ChordPattern(name: "Diminished 7",      abbreviation: "dim7",  intervals: [0, m3, tt, M6]),
        ChordPattern(name: "Major 6",           abbreviation: "maj6",  intervals: [0, M3, p5, M6]),
        ChordPattern(name: "Minor 6",           abbreviation: "min6",  intervals: [0, m3, p5, M6]),
        ChordPattern(name: "Sus2 + 7",          abbreviation: "sus2/7",intervals: [0, M2, p5, m7]),
        ChordPattern(name: "Sus4 + 7",          abbreviation: "sus4/7",intervals: [0, p4, p5, m7]),
    ]

    public static let all: [ChordPattern] = intervals + triads + tetrads

    /// Triads + tetrads only — convergence uses this so the upcoming-
    /// events list isn't flooded by the dozens of cross-timeframe
    /// fundamental intervals that are permanently active.
    public static let chords: [ChordPattern] = triads + tetrads
}
