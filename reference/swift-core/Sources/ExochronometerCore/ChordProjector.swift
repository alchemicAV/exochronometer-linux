import Foundation

/// One predicted chord event — a future window during which all tones
/// of a recognized chord pattern are simultaneously active above
/// threshold. `startTime` is the first sample where the chord registers;
/// `peakTime` is the sample with the highest combined amplitude.
public struct ChordEvent: Sendable, Hashable, Identifiable {
    public let pattern: ChordPattern
    public let toneSignature: [ToneSignature]
    public let startTime: Date
    public let peakTime: Date
    public let endTime: Date
    public let fitCents: Double
    public let peakAmplitudeProduct: Double

    public var id: String {
        let sig = toneSignature.map { "\($0.timeframe.rawValue).\($0.divisionLabel)" }
            .joined(separator: "+")
        return "\(pattern.abbreviation)|\(sig)|\(Int(startTime.timeIntervalSince1970))"
    }

    public struct ToneSignature: Sendable, Hashable {
        public let timeframe: TimeFrame
        public let divisions: Int
        public let skip: Int

        public init(timeframe: TimeFrame, divisions: Int, skip: Int = 1) {
            self.timeframe = timeframe
            self.divisions = divisions
            self.skip = skip
        }

        /// "7" for integer harmonics, "7/3" for winding tones.
        public var divisionLabel: String { skip == 1 ? "\(divisions)" : "\(divisions)/\(skip)" }
    }
}

public enum ChordProjector {
    /// Forward-search for upcoming chord events.
    ///
    /// - parameter from: Start of the search window.
    /// - parameter lookahead: How far forward to look. 1 month is the
    ///   sweet spot — ~50 ms wall-clock for typical chord catalogs.
    /// - parameter amplitudeThreshold: Each constituent tone must be at
    ///   or above this amplitude for the chord to count as "active."
    /// - parameter sampleInterval: How finely to sample the timeline.
    ///   60 s is enough to catch hourly-cycle events without false
    ///   negatives; 30 s or 10 s if you care about minute-cycle events.
    /// - parameter patterns: Which chord vocabulary to search.
    /// - parameter maxResults: Hard cap on returned events.
    public static func upcoming(
        from: Date,
        lookahead: TimeInterval,
        amplitudeThreshold: Double = 0.3,
        sampleInterval: TimeInterval = 60,
        scaling: Int = 23,
        includeFundamentals: Bool = true,
        crossTimeframeOnly: Bool = false,
        excludeHourly: Bool = false,
        excludeCurrentlyActive: Bool = true,
        patterns: [ChordPattern] = ChordCatalog.all,
        maxResults: Int = 50
    ) -> [ChordEvent] {
        let candidates = candidateChords(
            scaling: scaling,
            patterns: patterns,
            includeFundamentals: includeFundamentals,
            crossTimeframeOnly: crossTimeframeOnly,
            excludeHourly: excludeHourly
        )
        guard !candidates.isEmpty else { return [] }

        var openEvents: [ObjectIdentifier: OpenEvent] = [:]
        var events: [ChordEvent] = []

        let candidatesRef = candidates.map { Candidate(inner: $0) }

        // Seed pass at t = from: any candidate already active at t=0
        // is "in progress" — we don't generate an upcoming event for it
        // until it deactivates and reactivates. (Those chords are shown
        // by the convergence widget's NOW section instead.)
        var stillRunningFromStart: Set<ObjectIdentifier> = []
        if excludeCurrentlyActive {
            let initialAmps = ToneAmplitudeTable(at: from, scaling: scaling)
            for cand in candidatesRef {
                let allActive = cand.inner.tones.allSatisfy { tone in
                    initialAmps.amplitude(of: tone) >= amplitudeThreshold
                }
                if allActive { stillRunningFromStart.insert(ObjectIdentifier(cand)) }
            }
        }

        let nSamples = Int(lookahead / sampleInterval)
        guard nSamples > 0 else { return [] }

        for i in 0...nSamples {
            let t = from.addingTimeInterval(Double(i) * sampleInterval)
            let amps = ToneAmplitudeTable(at: t, scaling: scaling)
            for cand in candidatesRef {
                let ampProduct = cand.inner.tones.reduce(1.0) { acc, tone in
                    acc * amps.amplitude(of: tone)
                }
                let allActive = cand.inner.tones.allSatisfy { tone in
                    amps.amplitude(of: tone) >= amplitudeThreshold
                }
                let key = ObjectIdentifier(cand)

                if allActive {
                    // If this candidate was active at t=0 and has never
                    // gone inactive since, skip — it's not a *new* event.
                    if stillRunningFromStart.contains(key) {
                        continue
                    }

                    if var open = openEvents[key] {
                        open.endTime = t
                        if ampProduct > open.peakAmplitudeProduct {
                            open.peakAmplitudeProduct = ampProduct
                            open.peakTime = t
                        }
                        openEvents[key] = open
                    } else {
                        openEvents[key] = OpenEvent(
                            startTime: t,
                            peakTime: t,
                            endTime: t,
                            peakAmplitudeProduct: ampProduct
                        )
                    }
                } else {
                    // First time this candidate goes inactive — it's now
                    // eligible for future activations to count as new events.
                    if stillRunningFromStart.remove(key) != nil {
                        continue
                    }
                    if let open = openEvents.removeValue(forKey: key) {
                        events.append(ChordEvent(
                            pattern: cand.inner.pattern,
                            toneSignature: cand.inner.tones.map {
                                ChordEvent.ToneSignature(timeframe: $0.timeframe, divisions: $0.divisions, skip: $0.skip)
                            },
                            startTime: open.startTime,
                            peakTime: open.peakTime,
                            endTime: open.endTime,
                            fitCents: cand.inner.fitCents,
                            peakAmplitudeProduct: open.peakAmplitudeProduct
                        ))
                    }
                }
            }
            if events.count >= maxResults * 2 { break }
        }

        return events
            .sorted { $0.startTime < $1.startTime }
            .prefix(maxResults)
            .map { $0 }
    }

    /// Detect chord patterns currently active at `date`.
    public static func current(
        at date: Date,
        amplitudeThreshold: Double = 0.3,
        scaling: Int = 23,
        includeFundamentals: Bool = true,
        crossTimeframeOnly: Bool = false,
        excludeHourly: Bool = false,
        patterns: [ChordPattern] = ChordCatalog.all
    ) -> [ChordMatch] {
        var tones = HarmonicAnalysis.activeTones(at: date, scales: [scaling])
        if !includeFundamentals {
            tones.removeAll { $0.isFundamental }
        }
        if excludeHourly {
            tones.removeAll { $0.timeframe == .hour }
        }
        // Restrict to canonical-highest-per-PC divisions so we don't
        // detect HR:4 and HR:8 as two separate chord events. The higher
        // overtone is a strict superset of the lower's firing windows,
        // so this loses no events. Winding tones ({7/3}, {8/3}) are
        // unique pitch classes and always pass.
        let pc1Canonical = includeFundamentals ? 1 : 8
        let canonicalDivisions: Set<Int> = [pc1Canonical, 6, 5, 7]
        tones.removeAll { $0.skip == 1 && !canonicalDivisions.contains($0.divisions) }
        let matches = ChordDetector.detect(
            in: tones,
            amplitudeThreshold: amplitudeThreshold,
            patterns: patterns
        )
        if crossTimeframeOnly {
            // Drop matches whose tones all share one timeframe — those
            // fire constantly when a single cycle has dense overtones
            // and dilute the meaningful cross-timeframe convergences.
            return matches.filter { match in
                Set(match.tones.map(\.timeframe)).count > 1
            }
        }
        return matches
    }

    // MARK: - Candidate enumeration

    /// Enumerate every (toneSubset, chordPattern) combination from the
    /// finite universe (5 timeframes × canonical integer divisions plus
    /// the {7/3} and {8/3} winding tones) that matches a pattern within
    /// tolerance. Computed once per (scaling, patterns) combo and cached.
    public static func candidateChords(
        scaling: Int = 23,
        patterns: [ChordPattern] = ChordCatalog.all,
        tolerance: Double = ChordDetector.tolerance,
        includeFundamentals: Bool = true,
        crossTimeframeOnly: Bool = false,
        excludeHourly: Bool = false
    ) -> [CandidateChord] {
        let key = CandidateKey(
            scaling: scaling,
            patternIDs: patterns.map { $0.abbreviation },
            tolerance: tolerance,
            includeFundamentals: includeFundamentals,
            crossTimeframeOnly: crossTimeframeOnly,
            excludeHourly: excludeHourly
        )
        if let cached = candidateCache.value(for: key) { return cached }

        let universe = makeUniverse(
            scaling: scaling,
            includeFundamentals: includeFundamentals,
            excludeHourly: excludeHourly
        )
        var found: [CandidateChord] = []
        var seenSignatures: Set<String> = []

        for pattern in patterns {
            let n = pattern.toneCount
            guard universe.count >= n else { continue }
            forEachCombination(universe, choose: n) { combo in
                if crossTimeframeOnly {
                    var seenTFs: Set<TimeFrame> = []
                    for tone in combo { seenTFs.insert(tone.timeframe) }
                    if seenTFs.count < 2 { return }
                }
                if let match = ChordDetector.match(combo, pattern: pattern, tolerance: tolerance) {
                    let signature = ChordDetector.pitchClassSignature(
                        of: match.tones, pattern: pattern
                    )
                    if seenSignatures.contains(signature) { return }
                    seenSignatures.insert(signature)
                    found.append(CandidateChord(
                        pattern: pattern,
                        tones: match.tones,
                        fitCents: match.fitCents
                    ))
                }
            }
        }
        candidateCache.set(found, for: key)
        return found
    }

    public struct CandidateChord: Sendable, Hashable {
        public let pattern: ChordPattern
        public let tones: [HarmonicTone]
        public let fitCents: Double
    }

    private static func makeUniverse(
        scaling: Int,
        includeFundamentals: Bool = true,
        excludeHourly: Bool = false
    ) -> [HarmonicTone] {
        var tones: [HarmonicTone] = []
        // One canonical representative per (timeframe, pitch class), using
        // the *highest* division available. The higher-octave overtones fire
        // at every moment their lower-octave equivalents do (since their
        // vertex sets are supersets), so they catch every chord event a
        // lower-octave canonical would, plus additional ones.
        //
        // PC1 special case: if fundamentals are included we use div=1
        // (always at amp=1.0) because it's even more permissive than div=8.
        // Otherwise we fall back to div=8.
        let pc1Canonical = includeFundamentals ? 1 : 8
        let baseDivisions = [pc1Canonical, 6, 5, 7]

        for tf in TimeFrame.allCases where tf != .minute {
            if excludeHourly && tf == .hour { continue }
            let fundamental = (1.0 / tf.cycleDuration) * pow(2.0, Double(scaling))
            for div in baseDivisions {
                tones.append(HarmonicTone(
                    timeframe: tf,
                    divisions: div,
                    scaling: scaling,
                    frequency: fundamental * Double(div),
                    amplitude: 1.0
                ))
            }
            // Winding tones — distinct pitch classes (7/6 and 4/3) with
            // no integer-harmonic equivalent.
            for shape in GeometryMath.defaultShapes where GeometryMath.oddPart(shape.skip) > 1 {
                tones.append(HarmonicTone(
                    timeframe: tf,
                    divisions: shape.divisions,
                    skip: shape.skip,
                    scaling: scaling,
                    frequency: fundamental * Double(shape.divisions) / Double(shape.skip),
                    amplitude: 1.0
                ))
            }
        }
        return tones
    }

    private static func forEachCombination<T>(_ items: [T], choose k: Int, body: ([T]) -> Void) {
        guard k > 0, k <= items.count else { return }
        var indices = Array(0..<k)
        let n = items.count
        while true {
            body(indices.map { items[$0] })
            var i = k - 1
            while i >= 0 && indices[i] == i + n - k { i -= 1 }
            if i < 0 { return }
            indices[i] += 1
            for j in (i + 1)..<k { indices[j] = indices[j - 1] + 1 }
        }
    }

    // MARK: - Caches & helpers

    private struct OpenEvent {
        var startTime: Date
        var peakTime: Date
        var endTime: Date
        var peakAmplitudeProduct: Double
    }

    private final class Candidate {
        let inner: CandidateChord
        init(inner: CandidateChord) { self.inner = inner }
    }

    private struct CandidateKey: Hashable {
        let scaling: Int
        let patternIDs: [String]
        let tolerance: Double
        let includeFundamentals: Bool
        let crossTimeframeOnly: Bool
        let excludeHourly: Bool
    }

    private static let candidateCache = ThreadSafeCache<CandidateKey, [CandidateChord]>()
}

/// Pre-computes amplitude for every (timeframe, divisions/skip) at one
/// instant so the projector can do constant-time lookups instead of
/// recomputing shapeOpacity per candidate-tone per sample.
struct ToneAmplitudeTable {
    private var amps: [String: Double] = [:]

    init(at date: Date, scaling: Int) {
        for tf in TimeFrame.allCases where tf != .minute {
            let degree = tf.degree(at: date)
            amps["\(tf.rawValue)|1/1"] = 1.0
            for div in 3...8 {
                amps["\(tf.rawValue)|\(div)/1"] = FadeMath.shapeOpacity(currentDegree: degree, divisions: div)
            }
            let state = FadeMath.TimeframeState(timeframe: tf, date: date)
            for shape in GeometryMath.defaultShapes where GeometryMath.oddPart(shape.skip) > 1 {
                var amp = 0.0
                for vertex in 0..<shape.divisions {
                    let a = FadeMath.nodeActivation(shape: shape, vertexIndex: vertex, state: state)
                    if a > amp { amp = a }
                }
                amps["\(tf.rawValue)|\(shape.divisions)/\(shape.skip)"] = amp
            }
        }
    }

    func amplitude(of tone: HarmonicTone) -> Double {
        amps["\(tone.timeframe.rawValue)|\(tone.divisions)/\(tone.skip)"] ?? 0
    }
}

/// Minimal locked cache so the candidate enumeration is computed once per
/// distinct (scaling, patterns, tolerance) combination.
private final class ThreadSafeCache<K: Hashable, V>: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [K: V] = [:]

    func value(for key: K) -> V? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }
    func set(_ value: V, for key: K) {
        lock.lock(); defer { lock.unlock() }
        store[key] = value
    }
}
