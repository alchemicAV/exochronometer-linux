import Foundation
import ExochronometerCore

// Reference vector generator.
//
// Dumps the pure-function state of ExochronometerCore as JSON so a port to
// another language can be diffed against the Swift original numerically.
// Everything emitted here is a pure function of the timestamp plus the epoch
// constants, so the output is fully reproducible.

struct Bundle: Codable {
    struct Meta: Codable {
        let timezone: String
        let epochInstantMs: Int64
        let decemberSolsticeMs: Int64
        let synodicMonthSeconds: Double
        let quarterMoonSeconds: Double
        let tropicalYearSeconds: Double
    }
    struct ShapeRow: Codable {
        let divisions: Int
        let skip: Int
        let isRegular: Bool
        let pathCount: Int
        let nodeSpacing: Double
    }
    struct JIRow: Codable {
        let name: String
        let ratio: Double
        let cents: Double
    }
    struct Sample: Codable {
        let ms: Int64
        let tf: [Double]      // degree per TimeFrame, in TimeFrame.allCases order
        let cd: [Double]      // cycleDuration per TimeFrame
        let lbl: [String]     // traditionalLabel per TimeFrame (local calendar)
        let moon: [Double]    // [phase, moonDegree, quarterMoonDegree]
        let moonName: String
    }
    struct HarmRow: Codable {
        let d: Int            // divisions
        let k: Int            // skip
        let p: Double         // periodSeconds
        let f: Double         // frequencyHz
        let n: String         // ji note name
        let c: Double         // cents delta from A432
    }
    struct Harmonics: Codable {
        let ms: Int64
        let rows: [HarmRow]
    }
    struct FadeRow: Codable {
        let ms: Int64
        let tf: String
        let d: Int
        let k: Int
        let v: Int
        let a: Double          // nodeActivation
    }
    struct ShapeOpRow: Codable {
        let ms: Int64
        let tf: String
        let d: Int
        let o: Double          // shapeOpacity
    }
    struct ExitRow: Codable {
        let ms: Int64
        let tf: String
        let d: Int
        let k: Int
        let e: Double?         // timeUntilOvertoneExit, nil when not in a window
    }

    let meta: Meta
    let shapes: [ShapeRow]
    let ji: [JIRow]
    let samples: [Sample]
    let harmonics: [Harmonics]
    let fade: [FadeRow]
    let shapeOps: [ShapeOpRow]
    let exits: [ExitRow]
}

func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

// --- build the timestamp set -------------------------------------------------

var dates: [Date] = []

// 2026-01-01T00:00:00Z
let baseEpoch: TimeInterval = 1_767_225_600
let dayCount = 366                     // a full year, leap-adjacent coverage
let perDay = 4                         // every 6 hours
for i in 0..<(dayCount * perDay) {
    dates.append(Date(timeIntervalSince1970: baseEpoch + Double(i) * 6 * 3600))
}

// Edge cases: epochs, solstices, leap day, second/minute boundaries, sub-second.
let edgeEpochs: [TimeInterval] = [
    -2_208_988_800,                    // 1900-01-01
    0,                                 // 1970-01-01 unix epoch
    1_419_212_160,                     // PhaseEpoch.instant   (2014-12-22T01:36Z)
    1_419_202_980,                     // PhaseEpoch.solstice  (2014-12-21T23:03Z)
    1_767_225_600 - 1,                 // instant before 2026
    1_783_641_600,                     // 2026-07-04T00:00Z
    1_801_382_400,                     // 2027-02-01T00:00Z
    baseEpoch + 59.0,                  // minute boundary
    baseEpoch + 60.0,
    baseEpoch + 3599.0,                // hour boundary
    baseEpoch + 3600.0,
    baseEpoch + 86_399.0,              // day boundary
    baseEpoch + 86_400.0,
    baseEpoch + 1234.567,              // sub-second
    baseEpoch + 0.001,
    baseEpoch + 31_536_000,            // +1 tropical-ish year
    1_740_787_200,                     // 2025-03-01 (post leap day 2024)
    1_709_164_800,                     // 2024-02-29T00:00Z leap day
    1_709_251_200,                     // 2024-03-01
    2_145_916_800,                     // 2038-01-19 (32-bit rollover)
]
for e in edgeEpochs { dates.append(Date(timeIntervalSince1970: e)) }

// --- static tables -----------------------------------------------------------

let shapes = GeometryMath.buildShapeList(minDivisions: 3, maxDivisions: 8, includeStars: true)
let shapeRows = shapes.map {
    Bundle.ShapeRow(divisions: $0.divisions, skip: $0.skip,
                    isRegular: $0.isRegular, pathCount: $0.path.count,
                    nodeSpacing: $0.nodeSpacing)
}
let jiRows = JustIntonation.ratios.map {
    Bundle.JIRow(name: $0.name, ratio: $0.ratio, cents: 1200 * log2($0.ratio))
}
let jiLabels = JustIntonation.labels   // presence checked below

// --- samples -----------------------------------------------------------------

var samples: [Bundle.Sample] = []
samples.reserveCapacity(dates.count)

for d in dates {
    let tf = TimeFrame.allCases.map { $0.degree(at: d) }
    let cd = TimeFrame.allCases.map { $0.cycleDuration }
    let lbl = TimeFrame.allCases.map { $0.traditionalLabel(at: d) }
    let phase = MoonPhase.phase(at: d)
    let moon = [phase, MoonPhase.moonDegree(at: d), MoonPhase.quarterMoonDegree(at: d)]
    samples.append(Bundle.Sample(
        ms: ms(d), tf: tf, cd: cd, lbl: lbl,
        moon: moon, moonName: MoonPhase.phaseName(forPhase: phase)
    ))
}

// --- harmonics (strided: the 60-row table per sample is large) ---------------

var harmonics: [Bundle.Harmonics] = []
var idx = 0
while idx < dates.count {
    let d = dates[idx]
    var rows: [Bundle.HarmRow] = []
    for tf in TimeFrame.allCases {
        for shape in shapes {
            let period = tf.cycleDuration * Double(shape.skip) / Double(shape.divisions)
            let freq = period > 0 ? 1.0 / period : 0
            let ji = JustIntonation.closestNote(frequency: freq)
            rows.append(Bundle.HarmRow(d: shape.divisions, k: shape.skip,
                                       p: period, f: freq, n: ji.noteName, c: ji.centsDelta))
        }
    }
    harmonics.append(Bundle.Harmonics(ms: ms(d), rows: rows))
    idx += 10
}

// --- fade math (strided: nodeActivation runs per vertex per shape) -----------

var fadeRows: [Bundle.FadeRow] = []
var shapeOpRows: [Bundle.ShapeOpRow] = []
var exitRows: [Bundle.ExitRow] = []
var fIdx = 0
while fIdx < dates.count {
    let d = dates[fIdx]
    for tf in TimeFrame.allCases {
        let state = FadeMath.TimeframeState(timeframe: tf, date: d)
        for shape in shapes {
            shapeOpRows.append(Bundle.ShapeOpRow(
                ms: ms(d), tf: tf.rawValue, d: shape.divisions,
                o: FadeMath.shapeOpacity(currentDegree: state.currentDegree,
                                         divisions: shape.divisions)
            ))
            for v in 0..<shape.divisions {
                fadeRows.append(Bundle.FadeRow(
                    ms: ms(d), tf: tf.rawValue, d: shape.divisions, k: shape.skip, v: v,
                    a: FadeMath.nodeActivation(shape: shape, vertexIndex: v, state: state)
                ))
            }
            exitRows.append(Bundle.ExitRow(
                ms: ms(d), tf: tf.rawValue, d: shape.divisions, k: shape.skip,
                e: FadeMath.timeUntilOvertoneExit(
                    timeframe: tf, divisions: shape.divisions, skip: shape.skip, at: d)
            ))
        }
    }
    fIdx += 37      // prime stride so it does not alias the harmonics stride
}

let bundle = Bundle(
    meta: Bundle.Meta(
        timezone: TimeZone.current.identifier,
        epochInstantMs: ms(PhaseEpoch.instant),
        decemberSolsticeMs: ms(PhaseEpoch.decemberSolstice),
        synodicMonthSeconds: MoonPhase.synodicMonthSeconds,
        quarterMoonSeconds: MoonPhase.quarterMoonSeconds,
        tropicalYearSeconds: TimeFrame.tropicalYearSeconds
    ),
    shapes: shapeRows,
    ji: jiRows,
    samples: samples,
    harmonics: harmonics,
    fade: fadeRows,
    shapeOps: shapeOpRows,
    exits: exitRows
)

_ = jiLabels

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(bundle)
FileHandle.standardOutput.write(data)
