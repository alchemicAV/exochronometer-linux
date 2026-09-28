import Foundation

public struct HarmonicTone: Identifiable, Hashable, Sendable {
    public let timeframe: TimeFrame
    public let divisions: Int       // 1 for the fundamental, 3..8 for overtones
    public let skip: Int            // winding number k of the source shape; 1 for fundamentals, regular polygons, and k=2 aliases
    public let scaling: Int         // octaves of 2 by which the natural frequency is shifted
    public let frequency: Double    // scaled frequency in Hz
    public let amplitude: Double    // 0..1

    public init(
        timeframe: TimeFrame,
        divisions: Int,
        skip: Int = 1,
        scaling: Int,
        frequency: Double,
        amplitude: Double
    ) {
        self.timeframe = timeframe
        self.divisions = divisions
        self.skip = skip
        self.scaling = scaling
        self.frequency = frequency
        self.amplitude = amplitude
    }

    public var id: String { "\(timeframe.rawValue)-\(divisions)/\(skip)-\(scaling)" }
    public var isFundamental: Bool { divisions == 1 }
    /// "7" for integer harmonics, "7/3" for winding tones.
    public var divisionLabel: String { skip == 1 ? "\(divisions)" : "\(divisions)/\(skip)" }
}

public struct ToneAssignment: Hashable, Sendable {
    public let timeframe: TimeFrame
    public let scale: Int

    public init(timeframe: TimeFrame, scale: Int) {
        self.timeframe = timeframe
        self.scale = scale
    }
}

public enum HarmonicAnalysis {
    /// All currently-active tones at one or more octave scalings.
    /// Convenience wrapper that produces an assignment for every
    /// non-minute timeframe at every supplied scale.
    public static func activeTones(
        at date: Date,
        scales: [Int],
        threshold: Double = 0.01
    ) -> [HarmonicTone] {
        let assignments = scales.flatMap { sc in
            TimeFrame.allCases
                .filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: sc) }
        }
        return activeTones(at: date, assignments: assignments, threshold: threshold)
    }

    /// All currently-active tones across an explicit list of
    /// (timeframe, scale) pairs. Lets the harmonic-analysis merged mode
    /// place each timeframe at a different scaling so they all land in
    /// audible range without duplicating each one across multiple scales.
    public static func activeTones(
        at date: Date,
        assignments: [ToneAssignment],
        threshold: Double = 0.01
    ) -> [HarmonicTone] {
        var out: [HarmonicTone] = []
        for entry in assignments {
            let tf = entry.timeframe
            let sc = entry.scale
            let factor = pow(2.0, Double(sc))
            let fundamental = (1.0 / tf.cycleDuration) * factor
            let degree = tf.degree(at: date)

            out.append(HarmonicTone(
                timeframe: tf,
                divisions: 1,
                scaling: sc,
                frequency: fundamental,
                amplitude: 1.0
            ))

            for div in 3...8 {
                let amp = FadeMath.shapeOpacity(currentDegree: degree, divisions: div)
                if amp > threshold {
                    out.append(HarmonicTone(
                        timeframe: tf,
                        divisions: div,
                        scaling: sc,
                        frequency: fundamental * Double(div),
                        amplitude: amp
                    ))
                }
            }

            // Star polygons whose winding number has an odd factor carry
            // pitch classes the integer harmonics lack ({7/3} → 7/6,
            // {8/3} → 4/3) and sound as distinct winding tones at
            // (n/k)·f with winding-aware activation. k=2 stars are exact
            // octaves of their regular polygons and stay aliased to the
            // integer harmonics above. (THEORY.md §1.4)
            let state = FadeMath.TimeframeState(timeframe: tf, date: date)
            for shape in GeometryMath.defaultShapes
            where shape.divisions >= 3 && GeometryMath.oddPart(shape.skip) > 1 {
                var amp = 0.0
                for vertex in 0..<shape.divisions {
                    let a = FadeMath.nodeActivation(shape: shape, vertexIndex: vertex, state: state)
                    if a > amp { amp = a }
                }
                if amp > threshold {
                    out.append(HarmonicTone(
                        timeframe: tf,
                        divisions: shape.divisions,
                        skip: shape.skip,
                        scaling: sc,
                        frequency: fundamental * Double(shape.divisions) / Double(shape.skip),
                        amplitude: amp
                    ))
                }
            }
        }
        return out
    }
}
