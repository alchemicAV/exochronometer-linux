import Foundation
import ExochronometerCore

/// Frozen snapshot of the values shown by the live widgets at a single
/// instant. The trigger engine compares previous vs. current values to
/// detect events; the capture pipeline uses it to write the post caption.
public struct SnapshotStats: Sendable {
    public let date: Date
    public let activeToneCount: Int
    public let pairCount: Int
    public let tenneyPerPair: Double
    public let tenneyTotal: Double
    public let entropyPerPair: Double
    public let entropyTotal: Double
    public let tenneyMeterPercent: Int
    public let entropyMeterPercent: Int
    public let currentChords: [ActiveChord]      // pattern + per-tone (timeframe, divisions)
    public let phaseClosure: [TimeFrame: Bool]   // per-timeframe normalized closure
    public let moonPhase: Double                 // 0..1
    public let moonPhaseName: String
    /// Shape IDs (e.g. "3-1", "5-2") whose fade opacity in the YEAR
    /// timeframe is currently above `peakOpacityThreshold`. Used by the
    /// yearGeometryPeak trigger — rising-edge transitions are firings.
    public let yearPeakingShapes: Set<String>
    public let moonPeakingShapes: Set<String>
    public let quarterMoonPeakingShapes: Set<String>
    public let dayPeakingShapes: Set<String>
    /// True when divisions 3, 4, 5, 6, 7, AND 8 all have at least one
    /// shape currently in its fade window in the hour timeframe. Used
    /// by the trigger evaluator to suppress dissonance/entropy fires
    /// that are mechanically explained by the simultaneous overtone
    /// convergence (so we don't post twice for one geometric event).
    public let allOvertonesActiveInHour: Bool
    public let allOvertonesActiveInDay: Bool

    /// Above this opacity, a shape is considered to be "at peak". Set to
    /// 0.85 — roughly the top 35% of the fade window around each node.
    public static let peakOpacityThreshold: Double = 0.85

    /// One detected chord match, captured with enough detail that the
    /// caption can show *which* harmonics produced it (e.g.
    /// "maj7 (YR3 MN5 DY7)") rather than just the pattern name.
    public struct ActiveChord: Codable, Sendable, Equatable, Hashable {
        public let abbreviation: String
        public let name: String               // full pattern name, e.g. "Major 7"
        public let toneSignatures: [String]   // e.g. ["YR3", "MN5", "DY7"]
        public let rootNote: String           // closest JI note to the chord root, e.g. "E"
        public let rootCentsDelta: Double      // signed cents of the root from that note
        public let fitCents: Double            // chord match error (lower = tighter)
    }

    public init(
        at date: Date,
        includeChords: Bool = true,
        chordExcludeHourly: Bool = true,
        chordIncludeFundamentals: Bool = false
    ) {
        self.date = date
        let assignments: [ToneAssignment] = [
            ToneAssignment(timeframe: .hour,        scale: 23),
            ToneAssignment(timeframe: .day,         scale: 26),
            ToneAssignment(timeframe: .quarterMoon, scale: 28),
            ToneAssignment(timeframe: .moon,        scale: 29),
            ToneAssignment(timeframe: .year,        scale: 29),
        ]
        let rawAll = HarmonicAnalysis.activeTones(at: date, assignments: assignments)
        let tones = rawAll.filter { !$0.isFundamental }   // overtones drive dissonance

        self.activeToneCount = tones.count
        let pairs = max(1, tones.count * (tones.count - 1) / 2)
        self.pairCount = pairs

        let tTotal = DissonanceMath.totalTenney(tones)
        let eTotal = DissonanceMath.totalEntropy(tones)
        self.tenneyTotal = tTotal
        self.entropyTotal = eTotal
        let tPer = tTotal / Double(pairs)
        let ePer = eTotal / Double(pairs)
        self.tenneyPerPair = tPer
        self.entropyPerPair = ePer
        self.tenneyMeterPercent = Int(min(100 + Double(DissonanceCalibration.spilloverDisplayCap),
                                          (tPer / DissonanceCalibration.tenneyMeterMax * 100).rounded()))
        self.entropyMeterPercent = Int(min(100 + Double(DissonanceCalibration.spilloverDisplayCap),
                                           (ePer / DissonanceCalibration.entropyMeterMax * 100).rounded()))

        // Current chord matches at this date (cross-timeframe-only, excludes hourly).
        // The ChordProjector sweep is the most expensive part of stats
        // construction (~50-200ms vs ~1ms for everything else). The
        // calibrator opts out via `includeChords: false` for fast sims.
        if includeChords {
            // Mirror the convergence widget's chord-filter settings (passed
            // in by the caller) so the posted/saved chord list matches what
            // that widget's NOW section shows. crossTimeframeOnly and the
            // triads+tetrads `chords` vocabulary are always on, same as
            // convergence — no intervals, no same-timeframe chords.
            let matches = ChordProjector.current(
                at: date,
                includeFundamentals: chordIncludeFundamentals,
                crossTimeframeOnly: true,
                excludeHourly: chordExcludeHourly,
                patterns: ChordCatalog.chords
            )
            self.currentChords = matches.map { match in
                let sigs = match.tones.map { tone in
                    "\(Self.shortName(tone.timeframe))\(tone.divisionLabel)"
                }
                // Root is the lowest-frequency tone of the match; snap it
                // to the nearest A=432 JI note for a readable label.
                let rootFreq = match.tones.min(by: { $0.frequency < $1.frequency })?.frequency ?? 0
                let root = JustIntonation.closestNote(frequency: rootFreq)
                return ActiveChord(
                    abbreviation: match.pattern.abbreviation,
                    name: match.pattern.name,
                    toneSignatures: sigs,
                    rootNote: root.noteName,
                    rootCentsDelta: root.centsDelta,
                    fitCents: match.fitCents
                )
            }
        } else {
            self.currentChords = []
        }

        // Phase closure per timeframe — uses the same scale=23 / 30ms window
        // the Mac phase portrait widget uses, so the caption matches what
        // the widget displays.
        let phaseSourceTones = HarmonicAnalysis.activeTones(at: date, scales: [23])
            .filter { !$0.isFundamental }
        let grouped = Dictionary(grouping: phaseSourceTones, by: { $0.timeframe })
        var closure: [TimeFrame: Bool] = [:]
        let baseWindow: Double = 0.030
        for tf in TimeFrame.allCases {
            guard let group = grouped[tf], !group.isEmpty else { continue }
            let window = baseWindow * (tf.cycleDuration / 86400.0)
            closure[tf] = PhasePortraitMath.isLoopClosed(tones: group, windowSeconds: window)
        }
        self.phaseClosure = closure

        let phase = MoonPhase.phase(at: date)
        self.moonPhase = phase
        self.moonPhaseName = MoonPhase.phaseName(forPhase: phase)

        // Peaking-shape sets for year and moon. Cheap relative to the
        // chord projector — ~9 shapes × ~constant-time opacity lookups
        // per timeframe, with the per-timeframe Calendar state hoisted.
        self.yearPeakingShapes        = Self.peakingShapes(timeframe: .year,        at: date)
        self.moonPeakingShapes        = Self.peakingShapes(timeframe: .moon,        at: date)
        self.quarterMoonPeakingShapes = Self.peakingShapes(timeframe: .quarterMoon, at: date)
        self.dayPeakingShapes         = Self.peakingShapes(timeframe: .day,         at: date)

        // Reuse rawAll (already populated above) to figure out which
        // divisions are currently above the amplitude threshold per
        // timeframe. `activeTones` filters at amplitude > 0.01, so the
        // unique divisions in the result IS the active set.
        let hourDivs = Set(rawAll.filter { $0.timeframe == .hour && !$0.isFundamental }.map { $0.divisions })
        let dayDivs  = Set(rawAll.filter { $0.timeframe == .day  && !$0.isFundamental }.map { $0.divisions })
        let allOvertones: Set<Int> = [3, 4, 5, 6, 7, 8]
        self.allOvertonesActiveInHour = allOvertones.isSubset(of: hourDivs)
        self.allOvertonesActiveInDay  = allOvertones.isSubset(of: dayDivs)
    }

    private static func peakingShapes(timeframe: TimeFrame, at date: Date) -> Set<String> {
        let state = FadeMath.TimeframeState(timeframe: timeframe, date: date)
        var out: Set<String> = []
        for shape in GeometryMath.defaultShapes {
            let op: Double
            if shape.skip == 1 {
                op = FadeMath.shapeOpacity(
                    currentDegree: state.currentDegree,
                    divisions: shape.divisions
                )
            } else {
                var best: Double = 0
                for v in 0..<shape.divisions {
                    let a = FadeMath.nodeActivation(
                        shape: shape, vertexIndex: v, state: state
                    )
                    if a > best { best = a }
                }
                op = best
            }
            if op >= peakOpacityThreshold {
                out.insert(shape.id)
            }
        }
        return out
    }

    /// Compact, X-friendly caption (~280 chars). No headline — the X
    /// account name identifies the source; the filename slug captures
    /// the specific trigger; the dots indicate which timeframe(s)
    /// triggered the snapshot; the meter readings + chord list give
    /// the harmonic state at that instant.
    public func formatCaption(trigger: SnapshotTrigger) -> String {
        var lines: [String] = []
        lines.append("Trigger: \(triggerLabel(for: trigger))")
        lines.append("Tenney   \(tenneyMeterPercent)%   \(String(format: "%.2f", tenneyPerPair)) TH")
        lines.append("Entropy  \(entropyMeterPercent)%   \(String(format: "%.3f", entropyPerPair)) HE")

        let triggerTfs = Self.triggerTimeframes(for: trigger, phaseClosure: phaseClosure)
        // A timeframe's dot fills if EITHER the trigger originated there
        // OR any of its shapes is currently in its peak window. So you
        // see overlapping cycles light up regardless of which one
        // produced the post.
        var filled = triggerTfs
        if !yearPeakingShapes.isEmpty        { filled.insert(.year) }
        if !moonPeakingShapes.isEmpty        { filled.insert(.moon) }
        if !quarterMoonPeakingShapes.isEmpty { filled.insert(.quarterMoon) }
        if !dayPeakingShapes.isEmpty         { filled.insert(.day) }
        // YR · MN · QM · DY are always shown. HR only appears if it's in
        // the trigger source (phase-closure events involving the hour
        // cycle) — its peaks are too short-lived to be meaningful in
        // a static post.
        var displayOrder: [TimeFrame] = [.year, .moon, .quarterMoon, .day]
        if triggerTfs.contains(.hour) {
            displayOrder.append(.hour)
        }
        let dotsLine = displayOrder.map { tf -> String in
            "\(short(tf)) \(filled.contains(tf) ? "●" : "○")"
        }.joined(separator: "  ")
        lines.append("Current Peaks: \(dotsLine)")

        // When chords are active they move to a threaded detail reply
        // (see `formatChordDetail`) so the main post has room to breathe.
        // Only the "None Active" case stays inline — a lone reply saying
        // "no chords active" isn't worth a second post.
        if currentChords.isEmpty {
            lines.append("Chords:  None Active")
        }

        lines.append(timestampLine())
        return lines.joined(separator: "\n")
    }

    /// Text-only body for the threaded chord-detail reply. Only meaningful
    /// when `currentChords` is non-empty — the caller gates on that and
    /// posts this as a reply to the main tweet. One line per chord:
    /// full name · closest JI root + signed cents · fit cents · tones.
    /// Lines are appended only while the whole post stays within X's
    /// 280-char limit, so a busy moment can't silently drop the post.
    public func formatChordDetail() -> String {
        var lines: [String] = ["Active Chords:"]
        for chord in currentChords {
            let delta = String(format: "%+.0f", chord.rootCentsDelta)
            let fit = String(format: "%.0f", chord.fitCents)
            let tones = chord.toneSignatures.joined(separator: " ")
            let line = "\(chord.name)  ·  root \(chord.rootNote) \(delta)¢  ·  fit \(fit)¢  ·  \(tones)"
            if (lines + [line]).joined(separator: "\n").count > 280 { break }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Human label for the trigger at this instant. Geometry-peak triggers
    /// that land on a cardinal phase get the astronomical name instead of
    /// the generic "… Geometry Peak": the year peak at 0°/180° is the
    /// winter/summer solstice, the moon peak at new/full is named as such.
    public func triggerLabel(for trigger: SnapshotTrigger) -> String {
        switch trigger {
        case .yearGeometryPeak:
            let deg = TimeFrame.year.degree(at: date)
            if nearAngle(deg, 0)   { return "Winter Solstice" }
            if nearAngle(deg, 180) { return "Summer Solstice" }
            return trigger.displayName
        case .moonGeometryPeak:
            if nearPhase(moonPhase, 0)   { return "New Moon" }
            if nearPhase(moonPhase, 0.5) { return "Full Moon" }
            return trigger.displayName
        default:
            return trigger.displayName
        }
    }

    /// Within `tol`° of a target angle, shortest way around the circle. The
    /// peak-opacity gate keeps a firing within ~3.4° of the exact node, so a
    /// small tolerance cleanly separates 0°/180° from every neighbouring
    /// Farey node (nearest is ~25° away).
    private func nearAngle(_ a: Double, _ b: Double, tol: Double = 6) -> Bool {
        FadeMath.circularDistance(a, b) <= tol
    }

    /// Within `tol` (cycle fraction) of a target moon phase, wrapping at 1.
    private func nearPhase(_ p: Double, _ target: Double, tol: Double = 0.02) -> Bool {
        var d = abs(p - target)
        if d > 0.5 { d = 1 - d }
        return d <= tol
    }

    /// Which timeframe(s) "own" each trigger kind. The filled dots in the
    /// caption mark the source of the firing, so readers can see at a
    /// glance which cycle's geometry / boundary produced the post.
    private static func triggerTimeframes(
        for trigger: SnapshotTrigger,
        phaseClosure: [TimeFrame: Bool]
    ) -> Set<TimeFrame> {
        switch trigger {
        case .yearGeometryPeak, .phaseClosedYear, .yearBoundary:
            return [.year]
        case .moonGeometryPeak, .phaseClosedMoon,
             .newMoon, .fullMoon, .firstQuarter, .lastQuarter:
            return [.moon]
        case .phaseClosedQuarterMoon:
            return [.quarterMoon]
        case .dayBoundary, .halfDayBoundary, .phaseClosedDay:
            return [.day]
        case .phaseClosedHour:
            return [.hour]
        case .phaseClosed:
            // multi-closure: light up every timeframe whose phase
            // closed at this instant
            return Set(phaseClosure.filter { $0.value }.keys)
        default:
            // manual, dissonance, entropy, chord — no timeframe owner
            return []
        }
    }

    private func headline(for trigger: SnapshotTrigger) -> String {
        switch trigger {
        case .manual:                  return "Exochronometer · snapshot"
        case .yearGeometryPeak:        return "△ Year geometry peak" + peakingSuffix(yearPeakingShapes)
        case .moonGeometryPeak:        return "△ Moon geometry peak" + peakingSuffix(moonPeakingShapes)
        case .newMoon:                 return "🌑 New Moon"
        case .fullMoon:                return "🌕 Full Moon"
        case .firstQuarter:            return "🌓 First Quarter"
        case .lastQuarter:             return "🌗 Last Quarter"
        case .yearBoundary:            return "Year boundary"
        case .dayBoundary:             return "Day boundary"
        case .halfDayBoundary:         return "Half-day boundary"
        case .dissonanceHigh:          return "Dissonance peak"
        case .dissonanceLow:           return "Dissonance trough"
        case .dissonanceExtremeHigh:   return "⚡ Extreme dissonance"
        case .dissonanceExtremeLow:    return "⚡ Extreme consonance"
        case .entropyHigh:             return "Entropy peak"
        case .entropyLow:              return "Entropy trough"
        case .entropyExtremeHigh:      return "⚡ Extreme entropy"
        case .entropyExtremeLow:       return "⚡ Extreme clarity"
        case .chordOnset:              return "New chord active"
        case .phaseClosed:             return "Phase portrait closed"
        case .phaseClosedYear:         return "Year phase closed"
        case .phaseClosedMoon:         return "Moon phase closed"
        case .phaseClosedQuarterMoon:  return "Quarter-moon phase closed"
        case .phaseClosedDay:          return "Day phase closed"
        case .phaseClosedHour:         return "Hour phase closed"
        }
    }

    private func peakingSuffix(_ shapes: Set<String>) -> String {
        guard !shapes.isEmpty else { return "" }
        return " · " + shapes.sorted().joined(separator: " · ")
    }

    private func timestampLine() -> String {
        // UTC. Keep the simple "YYYY-MM-DD HH:mm UTC" shape (per user
        // preference — `Z` was unclear, plain "UTC" reads better).
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func short(_ tf: TimeFrame) -> String { Self.shortName(tf) }

    static func shortName(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YR"
        case .moon:        return "MN"
        case .quarterMoon: return "QM"
        case .day:         return "DY"
        case .hour:        return "HR"
        case .minute:      return "MIN"
        }
    }
}
