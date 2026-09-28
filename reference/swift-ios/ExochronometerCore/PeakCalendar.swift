import Foundation

/// The year circle's geometric-peak calendar.
///
/// Every inscribed polygon {n} on the year circle (divisions 3…8) reaches
/// an absolute peak — amplitude 1.0 — when the year indicator crosses one
/// of its vertices. Collecting every distinct vertex angle across all
/// shapes gives the Farey sequence of order 8: 22 fractions of the circle.
/// The gaps between consecutive peaks are the "months" — 22 variable-length
/// spans, palindromic about the December↔June solstice axis, summing to one
/// mean tropical year.
///
/// A peak at p/q (lowest terms) belongs to harmonic q — the simplest
/// polygon with a vertex there (2/8 is really 1/4, a Quart peak, not an
/// Oct one). Each month is named `root(q) + suffix(p)`: the root is the
/// harmonic/interval (Tert, Quart, Quint, Hex, Sept, Oct), the suffix is
/// the vertex numerator (‑one …‑oz). The two fixed points of the mirror —
/// 0/1 and 1/2 — get their own names, `Initia` and `Meridia`.
public struct PeakMonth: Identifiable, Sendable, Equatable {
    /// 1-based position in the year (1…22).
    public let number: Int
    public let name: String
    /// Two/three-letter code: root letter + suffix letter. Quint and Quart
    /// both claim Q, so where their numerators collide (1 and 3) they take
    /// their distinguishing consonant — quiNt / quaRt. N and R belong to
    /// neither the root nor the suffix alphabet, so a three-letter code
    /// always parses unambiguously as Q + family + peak.
    public let shorthand: String
    /// Opening peak as a reduced fraction of the circle, p/q.
    public let numerator: Int
    public let harmonic: Int
    /// Opening angle in degrees, [0, 360).
    public let openingDegree: Double
    /// Span until the next peak, in days (mean tropical year).
    public let lengthDays: Double
    /// Polygons (divisions 3…8) that peak at the opening vertex.
    public let coincidingHarmonics: [Int]

    public var id: Int { number }

    /// Whole day-cells to draw. `lengthDays` is fractional, so the final
    /// cell is a partial day; `Int(lengthDays) + 1` covers every value
    /// `Position.dayOfMonth` can take within the span.
    public var dayCount: Int { Int(lengthDays) + 1 }

    /// e.g. "3/8" — the opening fraction in lowest terms.
    public var fractionLabel: String { "\(numerator)/\(harmonic)" }
}

public enum PeakCalendar {

    /// Where "now" (or any instant) falls in the calendar.
    public struct Position: Sendable, Equatable {
        /// 0-based index into ``PeakCalendar/months``.
        public let monthIndex: Int
        /// 1-based day within the month.
        public let dayOfMonth: Int
        /// 0…1 progress through the current month.
        public let fractionThroughMonth: Double
    }

    /// The 22 months, ordered from the December solstice (`Initia`, 0°).
    public static let months: [PeakMonth] = build()

    /// Which month/day a date lands in. Uses the same solstice-anchored,
    /// UTC year phase as every other timeframe, so the calendar and the
    /// year circle are one clock.
    public static func position(at date: Date) -> Position {
        let frac = yearFraction(at: date)
        var index = 0
        for i in months.indices {
            if openingFraction(months[i]) <= frac { index = i } else { break }
        }
        let start = openingFraction(months[index])
        let end = index + 1 < months.count ? openingFraction(months[index + 1]) : 1.0
        let daysElapsed = (frac - start) * TimeFrame.tropicalYearDays
        let day = max(1, Int(daysElapsed) + 1)
        let through = end > start ? (frac - start) / (end - start) : 0
        return Position(monthIndex: index, dayOfMonth: day, fractionThroughMonth: through)
    }

    /// The next instant at which ``position(at:)`` reports a different
    /// day — either the day rolling over inside the month, or the month
    /// itself opening (which resets the count to day 1).
    ///
    /// The year phase is linear in absolute time, so a target fraction
    /// converts back to a date by simple proportion; no search needed.
    /// Widgets use this to schedule a timeline entry per day rather than
    /// polling on a fixed clock interval.
    public static func nextDayBoundary(after date: Date) -> Date {
        let frac = yearFraction(at: date)
        let pos = position(at: date)
        let start = openingFraction(months[pos.monthIndex])
        // Days are counted from the month's opening, so the boundaries are
        // start + k/yearDays — capped by the next month's opening, whichever
        // comes first (the last day of a month is a partial one).
        let nextDay = start + Double(pos.dayOfMonth) / TimeFrame.tropicalYearDays
        let monthEnd = pos.monthIndex + 1 < months.count
            ? openingFraction(months[pos.monthIndex + 1])
            : 1.0
        let target = min(nextDay, monthEnd)
        return date.addingTimeInterval((target - frac) * TimeFrame.tropicalYearSeconds)
    }

    // MARK: - Derivation

    private static func yearFraction(at date: Date) -> Double {
        var frac = TimeFrame.year.degree(at: date) / 360.0
        frac = frac.truncatingRemainder(dividingBy: 1)
        if frac < 0 { frac += 1 }
        return frac
    }

    private static func openingFraction(_ m: PeakMonth) -> Double {
        m.openingDegree / 360.0
    }

    private static func build() -> [PeakMonth] {
        // Farey_8: every reduced fraction p/q with q in 1…8, in [0, 1).
        var reduced: [(p: Int, q: Int)] = []
        var seen = Set<Double>()
        for q in 1...8 {
            for p in 0..<q {
                let g = GeometryMath.gcd(p, q)
                let rp = p / g
                let rq = q / g
                let value = Double(rp) / Double(rq)
                if seen.insert(value).inserted {
                    reduced.append((rp, rq))
                }
            }
        }
        reduced.sort { Double($0.p) / Double($0.q) < Double($1.p) / Double($1.q) }

        let yearDays = TimeFrame.tropicalYearDays
        return reduced.enumerated().map { i, f in
            let start = Double(f.p) / Double(f.q)
            let end = i + 1 < reduced.count
                ? Double(reduced[i + 1].p) / Double(reduced[i + 1].q)
                : 1.0
            return PeakMonth(
                number: i + 1,
                name: name(numerator: f.p, harmonic: f.q),
                shorthand: shorthand(numerator: f.p, harmonic: f.q),
                numerator: f.p,
                harmonic: f.q,
                openingDegree: start * 360,
                lengthDays: (end - start) * yearDays,
                coincidingHarmonics: (3...8).filter { $0 % f.q == 0 }
            )
        }
    }

    // MARK: - Naming

    private static func rootName(_ q: Int) -> String {
        switch q {
        case 3: return "Tert"
        case 4: return "Quart"
        case 5: return "Quint"
        case 6: return "Hex"
        case 7: return "Sept"
        case 8: return "Oct"
        default: return ""
        }
    }

    private static func suffixName(_ p: Int) -> String {
        switch p {
        case 1: return "one"
        case 2: return "ava"
        case 3: return "is"
        case 4: return "yr"
        case 5: return "une"
        case 6: return "em"
        case 7: return "oz"
        default: return ""
        }
    }

    private static func name(numerator p: Int, harmonic q: Int) -> String {
        switch q {
        case 1: return "Initia"
        case 2: return "Meridia"
        default: return rootName(q) + suffixName(p)
        }
    }

    private static func rootLetter(_ q: Int) -> String {
        switch q {
        case 3: return "T"
        case 4, 5: return "Q"
        case 6: return "H"
        case 7: return "S"
        case 8: return "O"
        default: return ""
        }
    }

    /// First letter of the suffix — except `-oz`, which takes `Z` because
    /// its natural `O` collides with `-one`.
    private static func suffixLetter(_ p: Int) -> String {
        switch p {
        case 1: return "O"
        case 2: return "A"
        case 3: return "I"
        case 4: return "Y"
        case 5: return "U"
        case 6: return "E"
        case 7: return "Z"
        default: return ""
        }
    }

    private static func shorthand(numerator p: Int, harmonic q: Int) -> String {
        switch q {
        case 1: return "IN"
        case 2: return "ME"
        case 4:
            // Quart's peaks (numerators 1, 3) both collide with a Quint
            // peak, so it always carries the 'R' of quaRt.
            return "QR" + suffixLetter(p)
        case 5:
            // Quint disambiguates only on the numerators Quart also has.
            return (p == 1 || p == 3 ? "QN" : "Q") + suffixLetter(p)
        default:
            return rootLetter(q) + suffixLetter(p)
        }
    }
}
