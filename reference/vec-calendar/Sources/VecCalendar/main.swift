import Foundation
import ExochronometerCore

// Reference vector generator for PeakCalendar + NoteSnap.
//
// Dumps the pure-function state of the ORIGINAL Swift implementation as JSON
// so the TypeScript port can be diffed against it numerically. Everything
// emitted here is a pure function of the input instants plus the epoch
// constants, so the output is fully reproducible.
//
// Two things needed care:
//
//  * Swift's `Date` is a Double of SECONDS since 2001-01-01 and
//    `timeIntervalSince` subtracts two ~4.5e8-magnitude values, so a Date
//    built from a millisecond value carries an uncertainty of up to ~1.2e-7 s.
//    The port's input is an exact integer millisecond count. For WHOLE-SECOND
//    instants the two always agree bit-for-bit (both sides then do exact
//    integer second arithmetic); for sub-second instants they can diverge by
//    up to ~3.7e-15 of a year fraction - see the `aligned` flag. All inputs
//    are whole-second except the deliberate `subsecondProbes`.
//
//  * Node arrays are sorted by `id` because Swift's Dictionary ordering is not
//    stable across runs; the validator compares them as sets keyed by `id`, so
//    sorting changes nothing about the values.

struct Bundle: Codable {
    struct Meta: Codable {
        let timezone: String
        let epochInstantMs: Int64
        let decemberSolsticeMs: Int64
        let synodicMonthSeconds: Double
        let quarterMoonSeconds: Double
        let tropicalYearSeconds: Double
    }
    struct MonthRow: Codable {
        let number: Int
        let name: String
        let shorthand: String
        let numerator: Int
        let harmonic: Int
        let openingDegree: Double
        let lengthDays: Double
        let coincidingHarmonics: [Int]
        let id: Int
        let dayCount: Int
        let fractionLabel: String
    }
    struct PositionRow: Codable {
        let ms: Int64
        let mi: Int
        let dom: Int
        let frac: Double           // fractionThroughMonth
        let yf: Double             // Swift yearFraction
        let aligned: Bool          // ms is a whole second
    }
    struct BoundaryRow: Codable {
        let beforeMs: Int64
        let after: Double          // nextDayBoundary -> timeIntervalSince1970 (raw Double)
        let yf: Double             // Swift yearFraction of beforeMs
        let mi: Int
        let dom: Int
        let aligned: Bool
    }
    struct SnapNodeRow: Codable {
        let id: Int
        let degree: Double
        let noteIDs: [String]
    }
    struct SnapCase: Codable {
        let label: String
        let circle: String
        let nowMs: Int64
        let lookbackCycles: Int
        let shapesKey: String
        let nodes: [SnapNodeRow]
    }
    struct NodeOpRow: Codable {
        let shapesKey: String
        let nodeDegree: Double
        let currentDegree: Double
        let fadeFraction: Double
        let o: Double              // NoteSnap.nodeOpacity
    }

    let meta: Meta
    let months: [MonthRow]
    let positions: [PositionRow]
    let boundaries: [BoundaryRow]
    let snaps: [SnapCase]
    let nodeOps: [NodeOpRow]
}

func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

/// Quantize an instant to the whole millisecond the JSON boundary can carry.
/// JS `Date` (TimeClip) only represents whole milliseconds, so the port can
/// only ever see the rounded value; quantizing here means both implementations
/// are exercised on the *same* instant rather than on two instants one
/// sub-millisecond apart.
func quantize(_ d: Date) -> Date { Date(timeIntervalSince1970: Double(ms(d)) / 1000) }

/// Snap to the nearest whole second. Swift and millisecond-arithmetic JS agree
/// bit-for-bit on such instants, which lets the validator demand exact
/// equality on every discrete field.
func snapSecond(_ d: Date) -> Date { Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded()) }

func isWholeSecond(_ d: Date) -> Bool { ms(d) % 1000 == 0 }

/// Mirrors `PeakCalendar.yearFraction` (private in the original). Emitted with
/// each row so the validator can tell whether an instant even sits close enough
/// to a threshold for the representation gap to matter.
func yearFraction(_ at: Date) -> Double {
    var frac = TimeFrame.year.degree(at: at) / 360.0
    frac = frac.truncatingRemainder(dividingBy: 1)
    if frac < 0 { frac += 1 }
    return frac
}

let solstice = PhaseEpoch.decemberSolstice
let tropicalSeconds = TimeFrame.tropicalYearSeconds

// --- 1. the month table ------------------------------------------------------

let monthRows: [Bundle.MonthRow] = PeakCalendar.months.map {
    Bundle.MonthRow(
        number: $0.number,
        name: $0.name,
        shorthand: $0.shorthand,
        numerator: $0.numerator,
        harmonic: $0.harmonic,
        openingDegree: $0.openingDegree,
        lengthDays: $0.lengthDays,
        coincidingHarmonics: $0.coincidingHarmonics,
        id: $0.id,
        dayCount: $0.dayCount,
        fractionLabel: $0.fractionLabel
    )
}

// --- 2. positions over a wide spread of instants -----------------------------

var inputs: [Date] = []

// (a) dense sweep: every 6 hours across 2019-01-01 … 2029-12-31. Every instant
//     is whole-second, and the span covers the 2020/2024/2028 leap days and
//     several solstices.
var t: TimeInterval = 1_546_300_800          // 2019-01-01T00:00:00Z
let sweepEnd: TimeInterval = 1_893_456_000    // 2030-01-01T00:00:00Z
while t < sweepEnd {
    inputs.append(Date(timeIntervalSince1970: t))
    t += 6 * 3600
}

// (b) every month opening (the Farey_8 reduced fractions placed by simple
//     proportion from the solstice), at whole-second offsets around it. This is
//     the `openingFraction(months[i]) <= frac` branch: ±1 s and ±1 h on either
//     side, plus the nearest whole second, plus a whole day either way.
for q in 1...8 {
    for p in 0..<q {
        guard GeometryMath.gcd(p, q) == 1 else { continue }
        let f = Double(p) / Double(q)
        let anchor = solstice.addingTimeInterval(f * tropicalSeconds)
        let base = snapSecond(anchor)
        for off: TimeInterval in [0.0, 1.0, -1.0, 3600.0, -3600.0, 86400.0, -86400.0] {
            inputs.append(base.addingTimeInterval(off))
        }
    }
}

// (c) deliberate sub-second probes: the regime where Swift's seconds-since-2001
//     Double and the port's integer milliseconds cannot be made bit-identical.
for q in 1...8 {
    for p in 0..<q {
        guard GeometryMath.gcd(p, q) == 1 else { continue }
        let f = Double(p) / Double(q)
        let anchor = solstice.addingTimeInterval(f * tropicalSeconds)
        for off: TimeInterval in [0.0, 0.001, -0.001, 0.000001, -0.000001] {
            inputs.append(anchor.addingTimeInterval(off))
        }
    }
}

// (d) edge epochs: unix epoch, both PhaseEpoch constants, leap days, and
//     second/minute/hour/day boundaries (all whole-second), plus two sub-second
//     values and far past/future points.
let edgeEpochs: [TimeInterval] = [
    -2_208_988_800,                    // 1900-01-01
    0,                                 // 1970-01-01 unix epoch
    1_419_212_160,                     // PhaseEpoch.instant   (2014-12-22T01:36:00Z)
    1_419_202_980,                     // PhaseEpoch.solstice  (2014-12-21T23:03:00Z)
    1_419_212_160 - 1,
    1_419_202_980 - 1,
    1_709_164_800,                     // 2024-02-29T00:00Z leap day
    1_709_164_799,
    1_709_251_200,                     // 2024-03-01
    1_767_225_600 - 1,
    1_767_225_600,                     // 2026-01-01T00:00Z
    1_767_225_600 + 59.0,              // minute boundary
    1_767_225_600 + 60.0,
    1_767_225_600 + 3599.0,            // hour boundary
    1_767_225_600 + 3600.0,
    1_767_225_600 + 86_399.0,          // day boundary
    1_767_225_600 + 86_400.0,
    1_783_641_600,                     // 2026-07-04T00:00Z
    1_801_382_400,                     // 2027-02-01T00:00Z
    2_145_916_800,                     // 2038-01-19 (32-bit rollover)
    4_102_444_800,                     // 2100-01-01
    -1,
    // sub-second
    1_767_225_600 + 1234.567,
    1_767_225_600 + 0.001,
]
for e in edgeEpochs { inputs.append(Date(timeIntervalSince1970: e)) }

inputs = inputs.map(quantize)

let positionRows: [Bundle.PositionRow] = inputs.map {
    let pos = PeakCalendar.position(at: $0)
    return Bundle.PositionRow(
        ms: ms($0), mi: pos.monthIndex, dom: pos.dayOfMonth,
        frac: pos.fractionThroughMonth, yf: yearFraction($0),
        aligned: isWholeSecond($0)
    )
}

// --- 3. nextDayBoundary ------------------------------------------------------

var boundaryInputs: [Date] = []

// (a) every day boundary inside every month, at whole-second offsets around it.
//     The last day of each month is the partial one, so `min(nextDay, monthEnd)`
//     bites here.
for m in PeakCalendar.months {
    let start = m.openingDegree / 360.0
    for k in 1...max(1, m.dayCount) {
        let f = start + Double(k) / TimeFrame.tropicalYearDays
        let base = snapSecond(solstice.addingTimeInterval(f * tropicalSeconds))
        for off: TimeInterval in [0.0, 1.0, -1.0, 60.0, -60.0] {
            boundaryInputs.append(base.addingTimeInterval(off))
        }
    }
}

// (b) the month opening itself, at whole seconds either side.
for m in PeakCalendar.months {
    let base = snapSecond(solstice.addingTimeInterval((m.openingDegree / 360.0) * tropicalSeconds))
    for off: TimeInterval in [0.0, 1.0, -1.0, 3600.0, -3600.0] {
        boundaryInputs.append(base.addingTimeInterval(off))
    }
}

// (c) a stride through the position sweep, plus the two sub-second probes.
var bIdx = 0
while bIdx < inputs.count {
    boundaryInputs.append(inputs[bIdx])
    bIdx += 53
}

boundaryInputs = boundaryInputs.map(quantize)

let boundaryRows: [Bundle.BoundaryRow] = boundaryInputs.map {
    let next = PeakCalendar.nextDayBoundary(after: $0)
    let pos = PeakCalendar.position(at: $0)
    return Bundle.BoundaryRow(
        beforeMs: ms($0),
        after: next.timeIntervalSince1970,
        yf: yearFraction($0),
        mi: pos.monthIndex,
        dom: pos.dayOfMonth,
        aligned: isWholeSecond($0)
    )
}

// --- 4. NoteSnap.snap + NoteSnap.nodeOpacity ---------------------------------

func shapesFor(_ key: String) -> [GeometryMath.Shape] {
    switch key {
    case "default":  return GeometryMath.defaultShapes
    case "regulars": return GeometryMath.buildShapeList(minDivisions: 3, maxDivisions: 8, includeStars: false)
    case "narrow":   return GeometryMath.buildShapeList(minDivisions: 4, maxDivisions: 6, includeStars: true)
    case "empty":    return []
    default:         return GeometryMath.defaultShapes
    }
}

func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

// Degree sets: on-node, between-node, wraparound, sparse (missing keys).
let degA: [String: Double] = [
    "year": 0.0, "moon": 30.0, "quarterMoon": 60.0,
    "day": 90.0, "hour": 53.0, "minute": 359.0,
]
let degB: [String: Double] = [
    "year": 120.0, "moon": 121.0, "day": 44.9, "hour": 45.0,
]
let degC: [String: Double] = [
    "year": 359.9, "moon": 180.0, "quarterMoon": 179.999,
    "day": 0.0, "hour": 0.0, "minute": 0.0,
]
let degD: [String: Double] = ["year": 7.0]
let degE: [String: Double] = [
    "year": 200.0, "moon": 200.5, "quarterMoon": 201.0,
    "day": 202.0, "hour": 203.0, "minute": 204.0,
]
let degF: [String: Double] = [
    "year": 51.42857142857143, "moon": 51.42857142857143, "quarterMoon": 51.42857142857143,
    "day": 51.42857142857143, "hour": 51.42857142857143, "minute": 51.42857142857143,
]

// template: (idNumber, offsetFromNow in seconds, degrees)
let noteTemplates: [(String, [(Int, Double, [String: Double])])] = [
    ("empty", []),
    ("singleRecent", [(1, -3600.0, degA)]),
    ("threeRecent", [(1, -3600.0, degA), (2, -7200.0, degB), (3, -10800.0, degC)]),
    ("stale", [(1, -10 * 86400.0, degD), (2, -100 * 86400.0, degE)]),
    ("futureAndNow", [(1, 86400.0, degC), (2, -1.0, degB), (3, 0.0, degE)]),
    ("colliding", [(1, -1.0, degF), (2, -2.0, degF), (3, -3.0, degF)]),
]

let nowInstants: [Date] = [
    Date(timeIntervalSince1970: 1_767_225_600),   // 2026-01-01T00:00Z
    Date(timeIntervalSince1970: 1_709_164_800),   // 2024-02-29T00:00Z
    Date(timeIntervalSince1970: 1_419_212_160),   // PhaseEpoch.instant
    Date(timeIntervalSince1970: 1_751_328_000),   // 2025-07-01T00:00Z
]

var snapCases: [Bundle.SnapCase] = []

for circle in TimeFrame.allCases {
    for now in nowInstants {
        for (label, tmpl) in noteTemplates {
            for lookback in [0, 1, 6, 12] {
                let notes = tmpl.map { (n, off, degs) in
                    NoteSnapshot(id: uuid(n), timestamp: now.addingTimeInterval(off), degrees: degs)
                }
                let nodes = NoteSnap.snap(notes: notes, circle: circle, lookbackCycles: lookback, now: now)
                    .sorted { $0.id < $1.id }
                    .map { Bundle.SnapNodeRow(id: $0.id, degree: $0.degree, noteIDs: $0.noteIDs.map(\.uuidString)) }
                snapCases.append(Bundle.SnapCase(
                    label: label,
                    circle: circle.rawValue,
                    nowMs: ms(now),
                    lookbackCycles: lookback,
                    shapesKey: "default",
                    nodes: nodes
                ))
            }
            // Alternative shape sets at the default lookback.
            for key in ["regulars", "narrow", "empty"] {
                let notes = tmpl.map { (n, off, degs) in
                    NoteSnapshot(id: uuid(n), timestamp: now.addingTimeInterval(off), degrees: degs)
                }
                let nodes = NoteSnap.snap(notes: notes, circle: circle, shapes: shapesFor(key), now: now)
                    .sorted { $0.id < $1.id }
                    .map { Bundle.SnapNodeRow(id: $0.id, degree: $0.degree, noteIDs: $0.noteIDs.map(\.uuidString)) }
                snapCases.append(Bundle.SnapCase(
                    label: label,
                    circle: circle.rawValue,
                    nowMs: ms(now),
                    lookbackCycles: 6,
                    shapesKey: key,
                    nodes: nodes
                ))
            }
        }
    }
}

var nodeOpRows: [Bundle.NodeOpRow] = []

let nodeDegreeGrid: [Double] = [
    0.0, 1.0, 0.999, 180.0, 179.9, 359.999,
    30.0, 45.0, 51.42857142857143, 60.0,
    72.0, 90.0, 120.0, 240.0, 300.0,
]
let currentDegreeGrid: [Double] = [
    0.0, 5.0, 12.0, 30.0, 44.9, 45.0, 51.42857142857143,
    60.0, 90.0, 120.0, 179.999, 180.0, 270.0, 300.0, 359.9,
]
let fadeFractions: [Double] = [0.03, 0.01, 0.1, 0.0]

for key in ["default", "regulars", "narrow", "empty"] {
    let shapes = shapesFor(key)
    for nd in nodeDegreeGrid {
        for cd in currentDegreeGrid {
            for ff in fadeFractions {
                nodeOpRows.append(Bundle.NodeOpRow(
                    shapesKey: key,
                    nodeDegree: nd,
                    currentDegree: cd,
                    fadeFraction: ff,
                    o: NoteSnap.nodeOpacity(
                        nodeDegree: nd, currentDegree: cd, shapes: shapes, fadeFraction: ff)
                ))
            }
        }
    }
}

// --- emit --------------------------------------------------------------------

let bundle = Bundle(
    meta: Bundle.Meta(
        timezone: TimeZone.current.identifier,
        epochInstantMs: ms(PhaseEpoch.instant),
        decemberSolsticeMs: ms(PhaseEpoch.decemberSolstice),
        synodicMonthSeconds: MoonPhase.synodicMonthSeconds,
        quarterMoonSeconds: MoonPhase.quarterMoonSeconds,
        tropicalYearSeconds: TimeFrame.tropicalYearSeconds
    ),
    months: monthRows,
    positions: positionRows,
    boundaries: boundaryRows,
    snaps: snapCases,
    nodeOps: nodeOpRows
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(bundle)
FileHandle.standardOutput.write(data)
