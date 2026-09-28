import Foundation
import ExochronometerCore

// Reference vector generator for the chord layer:
//   ChordDetector  (pitchClassSignature / detect / match)
//   ChordProjector (candidateChords / current / upcoming)
//
// Everything emitted here is a pure function of the inputs recorded in each
// row, so the output is fully reproducible. Run with TZ=UTC:
//
//   export PATH="/usr/lib/swift/bin:$PATH"
//   cd reference/vec-chords && swift build -c release
//   TZ=UTC swift run -c release VecChords > ../vectors-chords.json
//
// NOTE: JSONEncoder OMITS nil optionals rather than emitting null, so a
// MatchCase with no match has no `result` key at all.
//
// NOTE ON RUN-TO-RUN STABILITY: Swift's String hashing is randomly seeded per
// process and `sorted(by:)` is introsort (not stable). The *identity set* of
// every row below is byte-stable across runs (verified over 3 runs), but the
// *order* of `detect`/`current` matches with exactly equal fitCents, and of
// `upcoming` events with exactly equal startTime, can differ between runs.
// test/validate-chords.mjs therefore compares those lists by identity rather
// than by index - see the ORDERING note in that file.

struct Bundle: Codable {
    struct ToneRow: Codable {
        let timeframe: String
        let divisions: Int
        let skip: Int
        let scaling: Int
        let frequency: Double
        let amplitude: Double
    }
    struct MatchRow: Codable {
        let id: String
        let abbr: String
        let fitCents: Double
        let tones: [ToneRow]
    }
    struct SignatureRow: Codable {
        let label: String
        let abbr: String
        let tones: [ToneRow]
        let signature: String
    }
    struct MatchCase: Codable {
        let label: String
        let abbr: String
        let tolerance: Double
        let tones: [ToneRow]
        let result: MatchRow?          // nil -> key omitted by JSONEncoder
    }
    struct DetectCase: Codable {
        let label: String
        let ampThreshold: Double
        let patternAbbrs: [String]
        let tones: [ToneRow]
        let matches: [MatchRow]
    }
    struct CurrentCase: Codable {
        let ms: Double
        let ampThreshold: Double
        let scaling: Int
        let includeFundamentals: Bool
        let crossTimeframeOnly: Bool
        let excludeHourly: Bool
        let patternAbbrs: [String]
        let matches: [MatchRow]
    }
    struct CandidateRow: Codable {
        let abbr: String
        let fitCents: Double
        let tones: [ToneRow]
    }
    struct CandidateCase: Codable {
        let scaling: Int
        let patternAbbrs: [String]
        let tolerance: Double
        let includeFundamentals: Bool
        let crossTimeframeOnly: Bool
        let excludeHourly: Bool
        let candidates: [CandidateRow]
    }
    struct SigEntry: Codable {
        let timeframe: String
        let divisions: Int
        let skip: Int
        let divisionLabel: String
    }
    struct EventRow: Codable {
        let id: String
        let abbr: String
        let toneSignature: [SigEntry]
        let startMs: Double
        let peakMs: Double
        let endMs: Double
        let fitCents: Double
        let peakAmplitudeProduct: Double
    }
    struct UpcomingCase: Codable {
        let fromMs: Double
        let lookahead: Double
        let sampleInterval: Double
        let scaling: Int
        let ampThreshold: Double
        let includeFundamentals: Bool
        let crossTimeframeOnly: Bool
        let excludeHourly: Bool
        let excludeCurrentlyActive: Bool
        let patternAbbrs: [String]
        let maxResults: Int
        let events: [EventRow]
    }

    let signatures: [SignatureRow]
    let matchCases: [MatchCase]
    let detectCases: [DetectCase]
    let currentCases: [CurrentCase]
    let candidateCases: [CandidateCase]
    let upcomingCases: [UpcomingCase]
}

// --- helpers -----------------------------------------------------------------

func ms(_ d: Date) -> Double { d.timeIntervalSince1970 * 1000 }

func tone(_ tf: TimeFrame, _ divisions: Int, _ skip: Int = 1, _ scaling: Int = 0,
          _ frequency: Double, _ amplitude: Double = 1.0) -> HarmonicTone {
    HarmonicTone(timeframe: tf, divisions: divisions, skip: skip, scaling: scaling,
                 frequency: frequency, amplitude: amplitude)
}

func toneRows(_ tones: [HarmonicTone]) -> [Bundle.ToneRow] {
    tones.map {
        Bundle.ToneRow(timeframe: $0.timeframe.rawValue, divisions: $0.divisions,
                       skip: $0.skip, scaling: $0.scaling,
                       frequency: $0.frequency, amplitude: $0.amplitude)
    }
}

func matchRow(_ m: ChordMatch) -> Bundle.MatchRow {
    Bundle.MatchRow(id: m.id, abbr: m.pattern.abbreviation,
                    fitCents: m.fitCents, tones: toneRows(m.tones))
}

func pattern(_ abbr: String) -> ChordPattern {
    guard let p = ChordCatalog.all.first(where: { $0.abbreviation == abbr }) else {
        fatalError("unknown pattern abbreviation \(abbr)")
    }
    return p
}

func patterns(_ abbrs: [String]) -> [ChordPattern] { abbrs.map(pattern) }

let allAbbrs = ChordCatalog.all.map { $0.abbreviation }

func eventRow(_ e: ChordEvent) -> Bundle.EventRow {
    Bundle.EventRow(
        id: e.id,
        abbr: e.pattern.abbreviation,
        toneSignature: e.toneSignature.map {
            Bundle.SigEntry(timeframe: $0.timeframe.rawValue, divisions: $0.divisions,
                            skip: $0.skip, divisionLabel: $0.divisionLabel)
        },
        startMs: ms(e.startTime), peakMs: ms(e.peakTime), endMs: ms(e.endTime),
        fitCents: e.fitCents, peakAmplitudeProduct: e.peakAmplitudeProduct)
}

// --- synthetic tone sets -----------------------------------------------------

let anchor = 220.0

let majorTriad = [tone(.day, 1, 1, 0, anchor),
                  tone(.day, 5, 1, 0, anchor * 5.0 / 4.0),
                  tone(.day, 3, 1, 0, anchor * 3.0 / 2.0)]
let majorTriadHigh = [tone(.day, 2, 1, 0, anchor * 2),
                      tone(.day, 10, 1, 0, anchor * 2 * 5.0 / 4.0),
                      tone(.day, 6, 1, 0, anchor * 2 * 3.0 / 2.0)]
let minorTriad = [tone(.hour, 1, 1, 0, 400),
                  tone(.hour, 5, 1, 0, 400 * 6.0 / 5.0),
                  tone(.hour, 3, 1, 0, 400 * 3.0 / 2.0)]
let maj7Tetrad = [tone(.year, 1, 1, 0, anchor),
                  tone(.year, 5, 1, 0, anchor * 5.0 / 4.0),
                  tone(.year, 3, 1, 0, anchor * 3.0 / 2.0),
                  tone(.year, 7, 1, 0, anchor * 15.0 / 8.0)]
let ambiguous = [tone(.day, 1, 1, 0, anchor),
                 tone(.day, 5, 1, 0, anchor * 1.254),   // just above 5/4
                 tone(.day, 3, 1, 0, anchor * 1.498)]
let winding = [tone(.day, 1, 1, 0, anchor),
               tone(.day, 7, 1, 0, anchor * 7.0),      // integer 7th harmonic
               tone(.day, 7, 3, 0, anchor * 7.0 / 3.0)] // winding 7/3
let belowThreshold = [tone(.day, 1, 1, 0, anchor, 0.2),
                      tone(.day, 5, 1, 0, anchor * 5.0 / 4.0, 0.05),
                      tone(.day, 3, 1, 0, anchor * 3.0 / 2.0, 0.29)]
let degenerate = [tone(.day, 1, 1, 0, 0),
                  tone(.day, 1, 1, 0, -anchor),
                  tone(.day, 1, 1, 0, anchor),
                  tone(.day, 1, 1, 0, anchor, 0.31),
                  tone(.hour, 1, 1, 0, 0.001),
                  tone(.hour, 1, 1, 0, 1e6)]
let pcTie6vs3 = [tone(.day, 3, 1, 0, 330),
                 tone(.day, 6, 1, 0, 660),
                 tone(.day, 5, 1, 0, 550)]
let pcTie3vs6b = [tone(.day, 3, 1, 0, 330),
                  tone(.day, 6, 1, 0, 660),
                  tone(.day, 5, 1, 0, 550),
                  tone(.day, 10, 1, 0, 1100)]
var noise: [HarmonicTone] = []
let noiseFreqs: [Double] = [123.4, 187.7, 251.3, 311.1, 419.9, 500.5, 617.2, 733.9,
                            811.4, 907.7, 1013.2, 1199.8]
for (i, f) in noiseFreqs.enumerated() {
    noise.append(tone(TimeFrame.allCases[i % 5], 1 + (i % 8), 1 + (i % 2), i % 3 - 1, f,
                      0.30 + Double(i % 7) * 0.1))
}
let single = [tone(.day, 1, 1, 0, anchor)]
let twoOctave = [tone(.day, 1, 1, 0, anchor), tone(.day, 2, 1, 0, anchor * 2)]
let emptyTones: [HarmonicTone] = []

let syntheticSets: [(String, [HarmonicTone])] = [
    ("empty", emptyTones),
    ("single", single),
    ("two-octave", twoOctave),
    ("major-triad", majorTriad),
    ("major-triad-high-octave", majorTriadHigh),
    ("major-triad-both-octaves", majorTriad + majorTriadHigh),
    ("minor-triad", minorTriad),
    ("maj7-tetrad", maj7Tetrad),
    ("maj7-tetrad-both-octaves", maj7Tetrad + maj7Tetrad.map {
        tone($0.timeframe, $0.divisions * 2, $0.skip, $0.scaling, $0.frequency * 2, $0.amplitude)
    }),
    ("ambiguous-major-minor", ambiguous),
    ("winding-7-and-7over3", winding),
    ("below-threshold", belowThreshold),
    ("degenerate-freqs", degenerate),
    ("pc-tie-6-vs-3", pcTie6vs3),
    ("pc-tie-3-vs-6b", pcTie3vs6b),
    ("noise-12", noise),
]

// Real, date-derived tone sets for detect.
let realDates: [Double] = [
    1_767_225_600,            // 2026-01-01T00:00:00Z
    1_767_225_600 + 137,      // +137 s
    1_767_225_600 + 3_600,    // +1 h
    1_767_225_600 + 7_200,
    1_767_225_600 + 21_600,
    1_767_225_600 + 43_200,   // +12 h
    1_767_225_600 + 86_399,
    1_767_225_600 + 86_400,   // +1 d
    1_767_225_600 + 3 * 86_400,
    1_767_225_600 + 7 * 86_400,
    1_767_225_600 + 13 * 86_400,
    1_767_225_600 + 29 * 86_400,
    1_767_225_600 + 40 * 86_400,
    1_767_225_600 + 77 * 86_400,
    1_709_164_800,            // 2024-02-29
    1_419_212_160,            // PhaseEpoch.instant
]
let realDateObjs: [Date] = realDates.map { Date(timeIntervalSince1970: $0) }

func realTones(_ d: Date, _ scaling: Int) -> [HarmonicTone] {
    HarmonicAnalysis.activeTones(at: d, scales: [scaling])
}

// --- signatures --------------------------------------------------------------

var signatures: [Bundle.SignatureRow] = []
for (label, tones) in syntheticSets where !tones.isEmpty {
    for abbr in ["8va", "P5", "maj", "min", "maj7"] {
        signatures.append(Bundle.SignatureRow(
            label: label, abbr: abbr, tones: toneRows(tones),
            signature: ChordDetector.pitchClassSignature(of: tones, pattern: pattern(abbr))))
    }
}

// --- match cases -------------------------------------------------------------

var matchCases: [Bundle.MatchCase] = []

@MainActor
func addMatch(_ label: String, _ tones: [HarmonicTone], _ abbr: String,
              _ tol: Double = ChordDetector.tolerance) {
    let r = ChordDetector.match(tones, pattern: pattern(abbr), tolerance: tol)
    matchCases.append(Bundle.MatchCase(
        label: label, abbr: abbr, tolerance: tol, tones: toneRows(tones),
        result: r.map(matchRow)))
}

for (label, tones) in syntheticSets {
    for abbr in ["8va", "P5", "P4", "M3", "m3", "M2", "M6", "M7", "h7", "TT",
                 "maj", "min", "dim", "aug", "sus2", "sus4",
                 "maj7", "min7", "dom7", "maj6", "dim7"] {
        addMatch(label, tones, abbr)
    }
}
// tolerance sweeps on a deliberately detuned triad
let detuned: [HarmonicTone] = [tone(.day, 1, 1, 0, anchor),
                               tone(.day, 5, 1, 0, anchor * 1.254),
                               tone(.day, 3, 1, 0, anchor * 1.498)]
for t in [0.0, 1e-9, 5.0, 10.0, 20.0, 25.0, 25.000001, 30.0, 50.0, 100.0, 600.0] {
    addMatch("detuned-maj", detuned, "maj", t)
    addMatch("detuned-min", detuned, "min", t)
}
// exact triads at zero tolerance
for (label, tones) in [("major-triad", majorTriad), ("major-triad-high", majorTriadHigh),
                       ("minor-triad", minorTriad)] {
    addMatch(label, tones, "maj", 0.0)
    addMatch(label, tones, "min", 0.0)
}
// real tone sets (first few combinations)
for (i, d) in realDateObjs.prefix(6).enumerated() {
    let tones = realTones(d, 23)
    for abbr in ["maj", "min", "maj7", "min7", "dom7", "P5", "8va"] {
        addMatch("real-\(i)", tones, abbr)
    }
    if tones.count >= 3 {
        addMatch("real-\(i)-first3", Array(tones.prefix(3)), "maj")
        addMatch("real-\(i)-first3b", Array(tones.prefix(3)), "min")
    }
}

// --- detect cases ------------------------------------------------------------

var detectCases: [Bundle.DetectCase] = []

@MainActor
func addDetect(_ label: String, _ tones: [HarmonicTone], _ ampThreshold: Double,
               _ abbrs: [String]) {
    let ms_ = ChordDetector.detect(in: tones, amplitudeThreshold: ampThreshold,
                                   patterns: patterns(abbrs))
    detectCases.append(Bundle.DetectCase(
        label: label, ampThreshold: ampThreshold, patternAbbrs: abbrs,
        tones: toneRows(tones), matches: ms_.map(matchRow)))
}

for (label, tones) in syntheticSets {
    addDetect(label, tones, 0.3, allAbbrs)
}
for (label, tones) in syntheticSets where !tones.isEmpty {
    addDetect(label + "-allpatterns-amp0", tones, 0.0, allAbbrs)
    addDetect(label + "-triads", tones, 0.3, ChordCatalog.triads.map { $0.abbreviation })
    addDetect(label + "-chords", tones, 0.3, ChordCatalog.chords.map { $0.abbreviation })
}
for (i, d) in realDateObjs.enumerated() {
    let tones = realTones(d, 23)
    addDetect("real-\(i)", tones, 0.3, allAbbrs)
    addDetect("real-\(i)-triads", tones, 0.3, ChordCatalog.triads.map { $0.abbreviation })
}
// explicit default-argument check (amplitudeThreshold defaults to 0.3)
detectCases.append(Bundle.DetectCase(
    label: "default-args", ampThreshold: 0.3, patternAbbrs: allAbbrs,
    tones: toneRows(majorTriad),
    matches: ChordDetector.detect(in: majorTriad).map(matchRow)))

// --- current cases -----------------------------------------------------------

var currentCases: [Bundle.CurrentCase] = []

@MainActor
func addCurrent(_ d: Date, _ ampThreshold: Double, _ scaling: Int,
                _ includeFundamentals: Bool, _ crossTimeframeOnly: Bool,
                _ excludeHourly: Bool, _ abbrs: [String]) {
    let ms_ = ChordProjector.current(
        at: d, amplitudeThreshold: ampThreshold, scaling: scaling,
        includeFundamentals: includeFundamentals, crossTimeframeOnly: crossTimeframeOnly,
        excludeHourly: excludeHourly, patterns: patterns(abbrs))
    currentCases.append(Bundle.CurrentCase(
        ms: ms(d), ampThreshold: ampThreshold, scaling: scaling,
        includeFundamentals: includeFundamentals, crossTimeframeOnly: crossTimeframeOnly,
        excludeHourly: excludeHourly, patternAbbrs: abbrs, matches: ms_.map(matchRow)))
}

for d in realDateObjs {
    addCurrent(d, 0.3, 23, true, false, false, allAbbrs)
}
for (i, d) in realDateObjs.enumerated() where i % 2 == 0 {
    addCurrent(d, 0.3, 23, true, true, false, allAbbrs)
    addCurrent(d, 0.3, 23, false, false, false, allAbbrs)
    addCurrent(d, 0.15, 23, true, false, false, allAbbrs)
    addCurrent(d, 0.3, 23, true, false, true, allAbbrs)
    addCurrent(d, 0.3, 20, true, false, false, allAbbrs)
    addCurrent(d, 0.3, 26, true, false, false, ChordCatalog.chords.map { $0.abbreviation })
}

// --- candidate cases ---------------------------------------------------------

var candidateCases: [Bundle.CandidateCase] = []

@MainActor
func addCandidates(_ scaling: Int, _ abbrs: [String], _ tol: Double,
                   _ includeFundamentals: Bool, _ crossTimeframeOnly: Bool,
                   _ excludeHourly: Bool) {
    let c = ChordProjector.candidateChords(
        scaling: scaling, patterns: patterns(abbrs), tolerance: tol,
        includeFundamentals: includeFundamentals,
        crossTimeframeOnly: crossTimeframeOnly, excludeHourly: excludeHourly)
    candidateCases.append(Bundle.CandidateCase(
        scaling: scaling, patternAbbrs: abbrs, tolerance: tol,
        includeFundamentals: includeFundamentals, crossTimeframeOnly: crossTimeframeOnly,
        excludeHourly: excludeHourly,
        candidates: c.map { Bundle.CandidateRow(abbr: $0.pattern.abbreviation,
                                                fitCents: $0.fitCents,
                                                tones: toneRows($0.tones)) }))
}

addCandidates(23, allAbbrs, 25, true, false, false)
addCandidates(23, ChordCatalog.chords.map { $0.abbreviation }, 25, true, false, false)
addCandidates(23, ChordCatalog.triads.map { $0.abbreviation }, 25, true, false, false)
addCandidates(23, ChordCatalog.tetrads.map { $0.abbreviation }, 25, true, false, false)
addCandidates(23, ChordCatalog.intervals.map { $0.abbreviation }, 25, true, false, false)
addCandidates(20, allAbbrs, 25, true, false, false)
addCandidates(26, allAbbrs, 25, true, false, false)
addCandidates(23, allAbbrs, 25, false, false, false)
addCandidates(23, allAbbrs, 25, true, true, false)
addCandidates(23, allAbbrs, 25, true, false, true)
addCandidates(23, allAbbrs, 15, true, false, false)
addCandidates(23, allAbbrs, 0, true, false, false)

// --- upcoming cases ----------------------------------------------------------

var upcomingCases: [Bundle.UpcomingCase] = []

@MainActor
func addUpcoming(_ from: Date, _ lookahead: Double, _ sampleInterval: Double,
                 _ scaling: Int, _ ampThreshold: Double, _ includeFundamentals: Bool,
                 _ crossTimeframeOnly: Bool, _ excludeHourly: Bool,
                 _ excludeCurrentlyActive: Bool, _ abbrs: [String], _ maxResults: Int) {
    let ev = ChordProjector.upcoming(
        from: from, lookahead: lookahead, amplitudeThreshold: ampThreshold,
        sampleInterval: sampleInterval, scaling: scaling,
        includeFundamentals: includeFundamentals, crossTimeframeOnly: crossTimeframeOnly,
        excludeHourly: excludeHourly, excludeCurrentlyActive: excludeCurrentlyActive,
        patterns: patterns(abbrs), maxResults: maxResults)
    upcomingCases.append(Bundle.UpcomingCase(
        fromMs: ms(from), lookahead: lookahead, sampleInterval: sampleInterval,
        scaling: scaling, ampThreshold: ampThreshold,
        includeFundamentals: includeFundamentals, crossTimeframeOnly: crossTimeframeOnly,
        excludeHourly: excludeHourly, excludeCurrentlyActive: excludeCurrentlyActive,
        patternAbbrs: abbrs, maxResults: maxResults, events: ev.map(eventRow)))
}

let chordsAbbrs = ChordCatalog.chords.map { $0.abbreviation }
let base = 1_767_225_600.0

addUpcoming(Date(timeIntervalSince1970: base), 6 * 3600, 60, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 137), 6 * 3600, 60, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 3 * 3600), 12 * 3600, 60, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 5 * 3600), 12 * 3600, 300, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 86_400), 24 * 3600, 60, 23, 0.3, true, false, false, false, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 2 * 86_400), 24 * 3600, 300, 23, 0.3, true, false, false, true, chordsAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 3 * 86_400), 24 * 3600, 300, 23, 0.3, true, true, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 4 * 86_400), 24 * 3600, 300, 23, 0.3, false, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 5 * 86_400), 24 * 3600, 300, 23, 0.3, true, false, true, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 6 * 86_400), 24 * 3600, 300, 20, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 7 * 86_400), 24 * 3600, 300, 26, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 8 * 86_400), 7 * 86_400, 600, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 9 * 86_400), 30 * 86_400, 3600, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 10 * 86_400), 24 * 3600, 300, 23, 0.15, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 11 * 86_400), 24 * 3600, 300, 23, 0.3, true, false, false, true, allAbbrs, 3)
addUpcoming(Date(timeIntervalSince1970: base + 12 * 86_400), 24 * 3600, 300, 23, 0.3, true, false, false, true, allAbbrs, 1)
addUpcoming(Date(timeIntervalSince1970: base + 13 * 86_400), 3600, 10, 23, 0.3, true, false, false, true, allAbbrs, 50)
addUpcoming(Date(timeIntervalSince1970: base + 14 * 86_400), 24 * 3600, 300, 23, 0.3, true, false, false, true, [], 50)

// --- emit --------------------------------------------------------------------

let bundle = Bundle(
    signatures: signatures,
    matchCases: matchCases,
    detectCases: detectCases,
    currentCases: currentCases,
    candidateCases: candidateCases,
    upcomingCases: upcomingCases)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(bundle))