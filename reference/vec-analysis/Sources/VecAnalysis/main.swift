import Foundation
import ExochronometerCore

// Reference vector generator for the three harmonic-analysis files.
//
// Dumps the pure-function state of HarmonicAnalysis, DissonanceGraph and
// DissonanceCalibrator as JSON so a port to another language can be diffed
// against the Swift original numerically. Everything emitted here is a pure
// function of the inputs listed in each row, so the output is fully
// reproducible. Run with TZ=UTC.
//
// Every date is constructed from a millisecond-multiple offset so the JSON
// round-trips to the exact same instant in a JS `Date` (which clips to whole
// ms). DissonanceGraphSampler's bucket dates for the .oneQuarterMoon range are
// NOT ms-aligned; that sub-ms clipping is a flagrant, inherent difference
// between Swift's Double-backed Date and JS's ms-clipped Date and is left in
// deliberately so the validator reports it honestly.

struct Bundle: Codable {
    struct ToneRow: Codable {
        let timeframe: String
        let divisions: Int
        let skip: Int
        let scaling: Int
        let frequency: Double
        let amplitude: Double
    }
    struct AssignRow: Codable {
        let timeframe: String
        let scale: Int
    }
    struct ActiveTonesRow: Codable {
        let label: String
        let dateMs: Double
        let scales: [Int]?
        let assignments: [AssignRow]?
        let threshold: Double
        let tones: [ToneRow]
    }
    struct RangeRow: Codable {
        let range: String
        let seconds: Double
        let label: String
    }
    struct GraphSampleRow: Codable {
        let dateMs: Double
        let tenneyNormalized: Double
        let entropyNormalized: Double
        let pairCount: Int
    }
    struct GraphRow: Codable {
        let label: String
        let endDateMs: Double
        let range: String
        let includeFundamentals: Bool
        let scaling: Int
        let bucketCount: Int
        let samples: [GraphSampleRow]
    }
    struct StatsRow: Codable {
        let sampleCount: Int
        let sampleIntervalSeconds: Double
        let duration: Double

        let totalTenneyMax: Double
        let totalTenneyP99: Double
        let totalTenneyP95: Double
        let totalTenneyMedian: Double
        let totalTenneyMin: Double
        let totalTenneyMean: Double

        let totalEntropyMax: Double
        let totalEntropyP99: Double
        let totalEntropyP95: Double
        let totalEntropyMedian: Double
        let totalEntropyMin: Double
        let totalEntropyMean: Double

        let perPairTenneyMax: Double
        let perPairTenneyP99: Double
        let perPairTenneyP95: Double
        let perPairTenneyMedian: Double

        let perPairEntropyMax: Double
        let perPairEntropyP99: Double
        let perPairEntropyP95: Double
        let perPairEntropyMedian: Double

        let activeToneCountMax: Int
        let activeToneCountMean: Double
    }
    struct CalibRow: Codable {
        let label: String
        let startDateMs: Double
        let duration: Double
        let sampleIntervalSeconds: Double
        let scaling: Int
        let includeFundamentals: Bool
        let stats: StatsRow
    }

    let activeTones: [ActiveTonesRow]
    let ranges: [RangeRow]
    let graph: [GraphRow]
    let calibrator: [CalibRow]
}

// --- helpers -----------------------------------------------------------------

func toneRow(_ t: HarmonicTone) -> Bundle.ToneRow {
    Bundle.ToneRow(timeframe: t.timeframe.rawValue, divisions: t.divisions,
                   skip: t.skip, scaling: t.scaling,
                   frequency: t.frequency, amplitude: t.amplitude)
}

func toneRows(_ ts: [HarmonicTone]) -> [Bundle.ToneRow] { ts.map(toneRow) }

func assignRows(_ a: [ToneAssignment]) -> [Bundle.AssignRow] {
    a.map { Bundle.AssignRow(timeframe: $0.timeframe.rawValue, scale: $0.scale) }
}

func statsRow(_ s: DissonanceCalibrator.Stats) -> Bundle.StatsRow {
    Bundle.StatsRow(
        sampleCount: s.sampleCount,
        sampleIntervalSeconds: s.sampleIntervalSeconds,
        duration: s.duration,
        totalTenneyMax: s.totalTenneyMax,
        totalTenneyP99: s.totalTenneyP99,
        totalTenneyP95: s.totalTenneyP95,
        totalTenneyMedian: s.totalTenneyMedian,
        totalTenneyMin: s.totalTenneyMin,
        totalTenneyMean: s.totalTenneyMean,
        totalEntropyMax: s.totalEntropyMax,
        totalEntropyP99: s.totalEntropyP99,
        totalEntropyP95: s.totalEntropyP95,
        totalEntropyMedian: s.totalEntropyMedian,
        totalEntropyMin: s.totalEntropyMin,
        totalEntropyMean: s.totalEntropyMean,
        perPairTenneyMax: s.perPairTenneyMax,
        perPairTenneyP99: s.perPairTenneyP99,
        perPairTenneyP95: s.perPairTenneyP95,
        perPairTenneyMedian: s.perPairTenneyMedian,
        perPairEntropyMax: s.perPairEntropyMax,
        perPairEntropyP99: s.perPairEntropyP99,
        perPairEntropyP95: s.perPairEntropyP95,
        perPairEntropyMedian: s.perPairEntropyMedian,
        activeToneCountMax: s.activeToneCountMax,
        activeToneCountMean: s.activeToneCountMean)
}

// --- dates (all millisecond-multiples => exact in a JS Date) ------------------

let instantMs = PhaseEpoch.instant.timeIntervalSince1970 * 1000
let solsticeMs = PhaseEpoch.decemberSolstice.timeIntervalSince1970 * 1000

var dateMsList: [Double] = [
    0, 1, 1000, 86_400_000, 86_401_000, -86_400_000, -1, 123_456,
    solsticeMs, instantMs, instantMs + 0.5, instantMs + 1000,
    1_768_000_000_000, 1_000_000_000_000, -1_000_000_000_000,
    4_102_444_800_000,   // 2100-01-01
    1_234_567.891,       // arbitrary sub-second instant
]
// de-dup while preserving order
var seen = Set<Double>()
dateMsList = dateMsList.filter { seen.insert($0).inserted }

let scaleSets: [(String, [Int])] = [
    ("empty", []),
    ("zero", [0]),
    ("default23", [23]),
    ("neg", [-3]),
    ("wide", [0, 1, 2, 5]),
    ("audible", [23, 30, -5]),
    ("extreme", [100, -100]),
    ("mid", [15, 17]),
]

// threshold: nil => Swift default argument (0.01) used. We still record the
// effective value in the emitted row so the validator knows what it got.
let thresholds: [(String, Double?)] = [
    ("tdefault", nil),
    ("t0", 0.0),
    ("t01", 0.01),
    ("t05", 0.5),
    ("t0999", 0.999),
    ("tneg", -1.0),
]

var activeRows: [Bundle.ActiveTonesRow] = []

for (tLabel, thrOpt) in thresholds {
    for (sLabel, scales) in scaleSets {
        for ms in dateMsList {
            let date = Date(timeIntervalSince1970: ms / 1000)
            let thr = thrOpt ?? 0.01
            let tones: [HarmonicTone]
            if let t = thrOpt {
                tones = HarmonicAnalysis.activeTones(at: date, scales: scales, threshold: t)
            } else {
                tones = HarmonicAnalysis.activeTones(at: date, scales: scales)
            }
            let label = "\(sLabel)|\(tLabel)|\(ms)"
            activeRows.append(Bundle.ActiveTonesRow(
                label: label, dateMs: ms, scales: scales, assignments: nil,
                threshold: thr, tones: toneRows(tones)))
        }
    }
}

// explicit-assignments form (covers .minute and mixed per-timeframe scales)
let assignmentSets: [(String, [ToneAssignment])] = [
    ("all-tf-mixed", TimeFrame.allCases.enumerated().map {
        ToneAssignment(timeframe: $0.element, scale: 23 + $0.offset % 3 - 1)
    }),
    ("minute-only", [ToneAssignment(timeframe: .minute, scale: 23)]),
    ("dupes", [ToneAssignment(timeframe: .day, scale: 0),
               ToneAssignment(timeframe: .day, scale: 0),
               ToneAssignment(timeframe: .hour, scale: 10)]),
    ("empty-assign", []),
    ("year-high", [ToneAssignment(timeframe: .year, scale: 40)]),
    ("all-tf-single", TimeFrame.allCases.map { ToneAssignment(timeframe: $0, scale: 23) }),
]
let assignThresholds: [(String, Double?)] = [("tdefault", nil), ("t0", 0.0), ("t03", 0.3)]
let assignDates: [Double] = [instantMs, solsticeMs + 3600_000, 1_768_000_000_000 + 12_345]

for (tLabel, thrOpt) in assignThresholds {
    for (sLabel, assigns) in assignmentSets {
        for ms in assignDates {
            let date = Date(timeIntervalSince1970: ms / 1000)
            let thr = thrOpt ?? 0.01
            let tones: [HarmonicTone]
            if let t = thrOpt {
                tones = HarmonicAnalysis.activeTones(at: date, assignments: assigns, threshold: t)
            } else {
                tones = HarmonicAnalysis.activeTones(at: date, assignments: assigns)
            }
            activeRows.append(Bundle.ActiveTonesRow(
                label: "A:\(sLabel)|\(tLabel)|\(ms)", dateMs: ms,
                scales: nil, assignments: assignRows(assigns),
                threshold: thr, tones: toneRows(tones)))
        }
    }
}

// --- range tables ------------------------------------------------------------

let ranges: [Bundle.RangeRow] = DissonanceGraphRange.allCases.map {
    Bundle.RangeRow(range: $0.rawValue, seconds: $0.seconds, label: $0.label)
}

// --- graph sampler -----------------------------------------------------------

let graphEnds: [Double] = [instantMs, 1_768_000_000_000, 0]
let bucketCounts = [240, 12, 1]
var graphRows: [Bundle.GraphRow] = []
for range in DissonanceGraphRange.allCases {
    for endMs in graphEnds {
        for inc in [false, true] {
            for sc in [23, 20] {
                for bc in bucketCounts {
                    let end = Date(timeIntervalSince1970: endMs / 1000)
                    let s = DissonanceGraphSampler.samples(
                        endingAt: end, range: range,
                        includeFundamentals: inc, scaling: sc, bucketCount: bc)
                    let rows = s.map {
                        Bundle.GraphSampleRow(
                            dateMs: $0.date.timeIntervalSince1970 * 1000,
                            tenneyNormalized: $0.tenneyNormalized,
                            entropyNormalized: $0.entropyNormalized,
                            pairCount: $0.pairCount)
                    }
                    let label = "\(range.rawValue)|\(endMs)|inc=\(inc)|sc=\(sc)|bc=\(bc)"
                    graphRows.append(Bundle.GraphRow(
                        label: label, endDateMs: endMs, range: range.rawValue,
                        includeFundamentals: inc, scaling: sc, bucketCount: bc,
                        samples: rows))
                }
            }
        }
    }
}
// default-argument forms (bucketCount 240, scaling 23) with the default label
for range in DissonanceGraphRange.allCases {
    let end = Date(timeIntervalSince1970: 1_768_000_000)
    let s = DissonanceGraphSampler.samples(
        endingAt: end, range: range, includeFundamentals: false)
    let rows = s.map {
        Bundle.GraphSampleRow(
            dateMs: $0.date.timeIntervalSince1970 * 1000,
            tenneyNormalized: $0.tenneyNormalized,
            entropyNormalized: $0.entropyNormalized,
            pairCount: $0.pairCount)
    }
    graphRows.append(Bundle.GraphRow(
        label: "defaults|\(range.rawValue)", endDateMs: 1_768_000_000_000,
        range: range.rawValue, includeFundamentals: false, scaling: 23,
        bucketCount: 240, samples: rows))
}

// --- calibrator --------------------------------------------------------------

struct CalibCase {
    let label: String
    let startMs: Double
    let duration: Double
    let interval: Double
    let scaling: Int
    let includeFundamentals: Bool
    let useDefaults: Bool
}

let calibCases: [CalibCase] = [
    // genuine no-argument default (1 yr / 60 s / scaling 23 / no fundamentals)
    CalibCase(label: "defaults", startMs: 0, duration: 0, interval: 0, scaling: 0,
              includeFundamentals: false, useDefaults: true),
    CalibCase(label: "day60", startMs: instantMs, duration: 86_400, interval: 60, scaling: 23,
              includeFundamentals: false, useDefaults: false),
    CalibCase(label: "year300", startMs: instantMs, duration: 365.25 * 86400, interval: 300,
              scaling: 23, includeFundamentals: false, useDefaults: false),
    CalibCase(label: "month60-fund", startMs: solsticeMs, duration: 86_400 * 30, interval: 60,
              scaling: 23, includeFundamentals: true, useDefaults: false),
    CalibCase(label: "tendays300-sc20", startMs: instantMs, duration: 86_400 * 10, interval: 300,
              scaling: 20, includeFundamentals: false, useDefaults: false),
    CalibCase(label: "tiny", startMs: instantMs, duration: 100, interval: 60, scaling: 23,
              includeFundamentals: false, useDefaults: false),   // nSamples clamps to 1
    CalibCase(label: "zero", startMs: instantMs, duration: 0, interval: 60, scaling: 23,
              includeFundamentals: false, useDefaults: false),   // nSamples clamps to 1
    CalibCase(label: "interval-gt-duration", startMs: 0, duration: 1000, interval: 3600,
              scaling: 23, includeFundamentals: false, useDefaults: false),
    CalibCase(label: "half-second", startMs: instantMs, duration: 100, interval: 0.5, scaling: 23,
              includeFundamentals: false, useDefaults: false),
    CalibCase(label: "scale0-fund", startMs: instantMs, duration: 86_400, interval: 900,
              scaling: 0, includeFundamentals: true, useDefaults: false),
    CalibCase(label: "scale-neg4", startMs: solsticeMs, duration: 86_400, interval: 600,
              scaling: -4, includeFundamentals: false, useDefaults: false),
]

var calibRows: [Bundle.CalibRow] = []
for c in calibCases {
    let stats: DissonanceCalibrator.Stats
    if c.useDefaults {
        stats = DissonanceCalibrator.simulate()
    } else {
        stats = DissonanceCalibrator.simulate(
            startDate: Date(timeIntervalSince1970: c.startMs / 1000),
            duration: c.duration,
            sampleIntervalSeconds: c.interval,
            scaling: c.scaling,
            includeFundamentals: c.includeFundamentals)
    }
    calibRows.append(Bundle.CalibRow(
        label: c.label,
        startDateMs: c.useDefaults ? instantMs : c.startMs,
        duration: c.useDefaults ? 365.25 * 86400 : c.duration,
        sampleIntervalSeconds: c.useDefaults ? 60 : c.interval,
        scaling: c.useDefaults ? 23 : c.scaling,
        includeFundamentals: c.useDefaults ? false : c.includeFundamentals,
        stats: statsRow(stats)))
}

// --- emit --------------------------------------------------------------------

let bundle = Bundle(activeTones: activeRows, ranges: ranges,
                    graph: graphRows, calibrator: calibRows)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(bundle)
FileHandle.standardOutput.write(data)