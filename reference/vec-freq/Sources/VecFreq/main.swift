import Foundation
import ExochronometerCore

// Reference vectors for FrequencyMath (including printfFixed at 2 and 3
// digits), plus `intervalName` and `shapeName` which the iOS app keeps as
// private members inside GeometryHarmonicsPage.swift (a SwiftUI file) and are
// therefore copied here VERBATIM rather than re-derived.
//
// Source: reference/swift-ios/Exochronometer/GeometryHarmonicsPage.swift
//         lines 307-337 (intervalName), 137-151 (shapeName)
//         and reference/swift-core/Sources/ExochronometerCore/FrequencyMath.swift

// MARK: - verbatim from GeometryHarmonicsPage.swift

func intervalName(n: Int, k: Int) -> String {
    let num = n
    var den = k
    while num >= 2 * den { den *= 2 }
    switch (num, den) {
    case (1, 1):   return "Unison"
    case (2, 1):   return "Octave"
    case (3, 2):   return "Perfect Fifth"
    case (4, 3):   return "Perfect Fourth"
    case (5, 3):   return "Major Sixth"
    case (5, 4):   return "Major Third"
    case (6, 5):   return "Minor Third"
    case (7, 4):   return "Harmonic Seventh"
    case (7, 5):   return "Septimal Tritone"
    case (7, 6):   return "Septimal Subminor Third"
    case (8, 5):   return "Minor Sixth"
    case (8, 7):   return "Septimal Major Second"
    case (9, 5):   return "Minor Seventh"
    case (9, 7):   return "Septimal Major Third"
    case (9, 8):   return "Major Second"
    case (15, 8):  return "Major Seventh"
    case (16, 15): return "Minor Second"
    case (45, 32): return "Tritone"
    default:       return "\(num):\(den) ratio"
    }
}

func shapeName(divisions: Int, skip: Int) -> String {
    switch (divisions, skip) {
    case (3, 1): return "TRIANGLE"
    case (4, 1): return "SQUARE"
    case (5, 1): return "PENTAGON"
    case (5, 2): return "PENTAGRAM"
    case (6, 1): return "HEXAGON"
    case (7, 1): return "HEPTAGON"
    case (7, 2): return "HEPTAGRAM {7/2}"
    case (7, 3): return "HEPTAGRAM {7/3}"
    case (8, 1): return "OCTAGON"
    case (8, 3): return "OCTAGRAM"
    default:     return "{\(divisions)/\(skip)}"
    }
}

// MARK: - emission

struct Bundle: Codable {
    struct DurationRow: Codable { let seconds: Double; let text: String }
    struct FormatRow: Codable { let hz: Double; let text: String }
    struct HzRow: Codable { let period: Double; let hz: Double }
    struct ScaleRow: Codable { let hz: Double; let octaves: Int; let out: Double }
    struct IntervalRow: Codable { let n: Int; let k: Int; let name: String }
    struct ShapeNameRow: Codable { let divisions: Int; let skip: Int; let name: String }
    struct PrintfRow: Codable { let value: Double; let digits: Int; let text: String }
    let constants: [Double]
    let durations: [DurationRow]
    let formats: [FormatRow]
    let hz: [HzRow]
    let scaled: [ScaleRow]
    let intervals: [IntervalRow]
    let shapeNames: [ShapeNameRow]
    let printf: [PrintfRow]
}

var secondsSweep: [Double] = [
    0, -1, -1000,
    TimeFrame.tropicalYearSeconds,
    TimeFrame.tropicalYearSeconds - 1,
    TimeFrame.tropicalYearSeconds * 2,
    24 * 60 * 60, 24 * 60 * 60 - 1, 24 * 60 * 60 * 3.5,
    60 * 60, 60 * 60 - 1, 60 * 60 * 12,
    60, 59.999, 61, 90, 123.456,
    1, 0.5, 0.001, 1e-9,
    1e6, 1e7, 31556925, 999999,
]
for i in 1...400 { secondsSweep.append(Double(i) * 0.005) }
for i in 1...200 { secondsSweep.append(Double(i) * 1.0 / 3.0) }
for i in 1...100 { secondsSweep.append(Double(i) * 59.995) }
for i in 1...80  { secondsSweep.append(Double(i) / 8.0) }

var hzSweep: [Double] = [
    0, -1, -0.5, 0.0001, 0.5, 1, 1.0 - 1e-9, 1.0000001, 2, 440, 432,
    999.99, 1000, 1000.01, 999999, 1_000_000, 1_000_001, 1e9, 20000, 20,
]
for i in 1...300 { hzSweep.append(Double(i) * 3.333) }
for i in 1...200 { hzSweep.append(Double(i) * 0.0033) }
for i in 1...80  { hzSweep.append(Double(i) / 8.0) }

// Values shaped like the dissonance meters' per-pair averages (small, 0..5),
// plus deliberate exact ties at both 2 and 3 decimals.
var printfSweep: [Double] = [0, -0.5, 1, 2.5, 3.95, 0.336, 1.0 / 3.0, 2.0 / 3.0, 1e-9]
for i in 1...300 { printfSweep.append(Double(i) * 0.0015) }   // .xx5 ties
for i in 1...200 { printfSweep.append(Double(i) / 8.0) }      // exact binary
for i in 1...200 { printfSweep.append(Double(i) / 3.0) }      // repeating
for i in 1...200 { printfSweep.append(Double(i) * 0.7391) }
for i in 1...100 { printfSweep.append(Double(i) * 1.0 / 16.0) }

var hzRows: [Bundle.HzRow] = []
for p in secondsSweep { hzRows.append(Bundle.HzRow(period: p, hz: FrequencyMath.hz(forPeriod: p))) }

var scaleRows: [Bundle.ScaleRow] = []
for h in [0.5, 1, 2, 27, 432, 1000, 123456.789] {
    for o in [-4, -1, 0, 1, 3, 8, 16, 23, 32] {
        scaleRows.append(Bundle.ScaleRow(hz: h, octaves: o, out: FrequencyMath.scaled(h, octaves: o)))
    }
}

var intervalRows: [Bundle.IntervalRow] = []
for n in 1...16 {
    for k in 1...16 {
        intervalRows.append(Bundle.IntervalRow(n: n, k: k, name: intervalName(n: n, k: k)))
    }
}

var shapeNameRows: [Bundle.ShapeNameRow] = []
for d in 1...10 {
    for s in 1...10 {
        shapeNameRows.append(Bundle.ShapeNameRow(divisions: d, skip: s, name: shapeName(divisions: d, skip: s)))
    }
}

var printfRows: [Bundle.PrintfRow] = []
for digits in [0, 1, 2, 3] {
    for v in printfSweep {
        printfRows.append(Bundle.PrintfRow(
            value: v, digits: digits,
            text: String(format: "%.\(digits)f", v)
        ))
    }
}

let bundle = Bundle(
    constants: [FrequencyMath.audibleMinHz, FrequencyMath.audibleMaxHz],
    durations: secondsSweep.map { Bundle.DurationRow(seconds: $0, text: FrequencyMath.formatDuration($0)) },
    formats: hzSweep.map { Bundle.FormatRow(hz: $0, text: FrequencyMath.format($0)) },
    hz: hzRows,
    scaled: scaleRows,
    intervals: intervalRows,
    shapeNames: shapeNameRows,
    printf: printfRows
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(bundle))