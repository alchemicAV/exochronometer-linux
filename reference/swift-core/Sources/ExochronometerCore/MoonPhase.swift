import Foundation

/// Universal phase anchor used by every timeframe and every star-polygon
/// winding cycle. Pinned to the "meeting of sun and moon": the new moon
/// of 2014-12-22 01:36 UTC, ~2.5 h after the December solstice
/// (2014-12-21 23:03 UTC). At this instant moon phase 0° and the
/// solstice-anchored year phase 0° coincide to within 2.5 hours — the
/// grand zero. The alignment recurs on the 19-year Metonic cycle
/// (235 synodic months ≈ 19 tropical years; previous 1995, next 2033).
/// Times are press-grade UTC values; refine the minute/second figures
/// against a precise ephemeris if one is at hand.
public enum PhaseEpoch {
    /// New moon at approximately 2014-12-22 01:36 UTC.
    public static let instant: Date = {
        var comps = DateComponents()
        comps.year = 2014
        comps.month = 12
        comps.day = 22
        comps.hour = 1
        comps.minute = 36
        comps.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 1_419_212_160)
    }()

    /// December solstice at approximately 2014-12-21 23:03 UTC — year
    /// phase 0°. The year advances from here by the mean tropical year
    /// (`TimeFrame.tropicalYearSeconds`), keeping phase 0 within minutes
    /// of every true December solstice.
    public static let decemberSolstice: Date = {
        var comps = DateComponents()
        comps.year = 2014
        comps.month = 12
        comps.day = 21
        comps.hour = 23
        comps.minute = 3
        comps.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 1_419_202_980)
    }()
}

public enum MoonPhase {
    /// Reference new moon. Same instant as `PhaseEpoch.instant` so that
    /// moon-cycle math and star-polygon winding share one anchor.
    public static let referenceNewMoon: Date = PhaseEpoch.instant

    public static let synodicMonthDays: Double = 29.530588853
    public static var synodicMonthSeconds: Double { synodicMonthDays * 24 * 60 * 60 }
    public static var quarterMoonSeconds: Double { synodicMonthSeconds / 4 }

    public static func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(referenceNewMoon)
        let m = elapsed / synodicMonthSeconds
        return m - floor(m)
    }

    public static func moonDegree(at date: Date) -> Double {
        phase(at: date) * 360
    }

    public static func quarterMoonDegree(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(referenceNewMoon)
        let m = elapsed / quarterMoonSeconds
        return (m - floor(m)) * 360
    }

    public static func phaseName(forPhase phase: Double) -> String {
        switch phase {
        case ..<0.0625: return "New Moon"
        case ..<0.1875: return "Waxing Crescent"
        case ..<0.3125: return "First Quarter"
        case ..<0.4375: return "Waxing Gibbous"
        case ..<0.5625: return "Full Moon"
        case ..<0.6875: return "Waning Gibbous"
        case ..<0.8125: return "Last Quarter"
        case ..<0.9375: return "Waning Crescent"
        default:        return "New Moon"
        }
    }
}
