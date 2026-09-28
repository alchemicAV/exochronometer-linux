import Foundation
import ExochronometerCore

// Reference vectors for the node date labels drawn OUTSIDE each circle.
//
// In the iOS original this logic lives in Exochronometer/TimeCircleView.swift
// (a SwiftUI file) as `drawNodeLabels` / `dateForNode` / `cycleStartDate` /
// `formatter`. Only the drawing is platform-bound: the date math and the label
// formats are pure Foundation. Those parts are copied here VERBATIM from that
// file so the TypeScript port can be diffed against the real implementation
// rather than a re-derivation.
//
// Source: reference/swift-ios/Exochronometer/TimeCircleView.swift lines 150-202

// MARK: - verbatim from TimeCircleView.swift

func formatter(for timeFrame: TimeFrame) -> DateFormatter {
    let f = DateFormatter()
    switch timeFrame {
    case .year:        f.dateFormat = "M/d"
    case .moon:        f.dateFormat = "M/d"
    case .quarterMoon: f.dateFormat = "M/d HH:mm"
    case .day:         f.dateFormat = "HH:mm"
    case .hour:        f.dateFormat = "HH:mm"
    case .minute:      f.dateFormat = "mm:ss"
    }
    return f
}

func dateForNode(degree: Double, timeFrame: TimeFrame, now: Date) -> Date {
    let cycleStart = cycleStartDate(for: timeFrame, now: now)
    let offset = (degree / 360.0) * timeFrame.cycleDuration
    return cycleStart.addingTimeInterval(offset)
}

func cycleStartDate(for timeFrame: TimeFrame, now: Date) -> Date {
    // UTC: must match the indicator's anchor (TimeFrame.degree uses
    // utcCalendar). The label DateFormatter is local-timezone by
    // default, so the rendered string at the indicator's position
    // is the local time of that UTC instant - exactly what the user
    // sees on their wall clock when the indicator is there.
    let cal = TimeFrame.utcCalendar
    switch timeFrame {
    case .year:
        let elapsed = now.timeIntervalSince(PhaseEpoch.decemberSolstice)
        let completed = floor(elapsed / TimeFrame.tropicalYearSeconds)
        return PhaseEpoch.decemberSolstice.addingTimeInterval(completed * TimeFrame.tropicalYearSeconds)
    case .day:
        return cal.startOfDay(for: now)
    case .hour:
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        return cal.date(from: comps) ?? now
    case .minute:
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        return cal.date(from: comps) ?? now
    case .moon:
        let elapsed = now.timeIntervalSince(MoonPhase.referenceNewMoon)
        let cyclesElapsed = elapsed / MoonPhase.synodicMonthSeconds
        let completed = floor(cyclesElapsed)
        return MoonPhase.referenceNewMoon.addingTimeInterval(completed * MoonPhase.synodicMonthSeconds)
    case .quarterMoon:
        let elapsed = now.timeIntervalSince(MoonPhase.referenceNewMoon)
        let cyclesElapsed = elapsed / MoonPhase.quarterMoonSeconds
        let completed = floor(cyclesElapsed)
        return MoonPhase.referenceNewMoon.addingTimeInterval(completed * MoonPhase.quarterMoonSeconds)
    }
}

// MARK: - emission

struct Bundle: Codable {
    struct FormatRow: Codable {
        let tf: String
        let pattern: String
        let format: String
    }
    struct Row: Codable {
        let ms: Int64
        let tf: String
        let cycleStartMs: Int64
        let deg: Double
        let nodeMs: Int64
        let label: String
    }
    let timezone: String
    let formats: [FormatRow]
    let rows: [Row]
}

let patterns: [(TimeFrame, String, String)] = [
    (.year, "M/d", "M/d"),
    (.moon, "M/d", "M/d"),
    (.quarterMoon, "M/d HH:mm", "M/d HH:mm"),
    (.day, "HH:mm", "HH:mm"),
    (.hour, "HH:mm", "HH:mm"),
    (.minute, "mm:ss", "mm:ss"),
]

func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

// Dates: a spread across years plus boundary cases. Node labels only depend on
// the cycle start for a (timeframe, instant) pair, so a modest sample covers it.
let baseEpoch: TimeInterval = 1_767_225_600          // 2026-01-01T00:00:00Z
var dates: [Date] = []
for i in 0..<24 { dates.append(Date(timeIntervalSince1970: baseEpoch + Double(i) * 8 * 86400)) }
for e in [1_419_212_160.0,          // PhaseEpoch.instant
          1_419_202_980.0,          // PhaseEpoch.decemberSolstice
          1_709_164_800.0,          // 2024-02-29 leap day
          1_709_251_200.0,          // 2024-03-01
          1_767_225_600.0 - 1,      // instant before 2026
          baseEpoch + 59.0, baseEpoch + 60.0,
          baseEpoch + 3599.0, baseEpoch + 3600.0,
          baseEpoch + 86_399.0, baseEpoch + 86_400.0,
          2_145_916_800.0,          // 2038 rollover
          -2_208_988_800.0] {       // 1900
    dates.append(Date(timeIntervalSince1970: e))
}

let degrees: [Double] = [0, 1, 45, 90, 135, 180, 225, 270, 315, 359]

var rows: [Bundle.Row] = []
for d in dates {
    for (tf, _, _) in patterns {
        let start = cycleStartDate(for: tf, now: d)
        let f = formatter(for: tf)
        for deg in degrees {
            let nodeDate = dateForNode(degree: deg, timeFrame: tf, now: d)
            rows.append(Bundle.Row(
                ms: ms(d), tf: tf.rawValue, cycleStartMs: ms(start),
                deg: deg, nodeMs: ms(nodeDate),
                label: f.string(from: nodeDate)
            ))
        }
    }
}

let bundle = Bundle(
    timezone: TimeZone.current.identifier,
    formats: patterns.map { Bundle.FormatRow(tf: $0.0.rawValue, pattern: $0.1, format: $0.2) },
    rows: rows
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(bundle))
