import Foundation

public enum TimeFrame: String, CaseIterable, Identifiable, Codable, Sendable {
    case year
    case moon
    case quarterMoon
    case day
    case hour
    case minute

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .year:        return "ONE YEAR"
        case .moon:        return "MOON CYCLE"
        case .quarterMoon: return "1/4 MOON"
        case .day:         return "ONE DAY"
        case .hour:        return "ONE HOUR"
        case .minute:      return "ONE MINUTE"
        }
    }

    public var sublabel: String {
        switch self {
        case .year:        return "~365.24 days"
        case .moon:        return "~29.53 days"
        case .quarterMoon: return "~7.38 days"
        case .day:         return "24 hours"
        case .hour:        return "60 minutes"
        case .minute:      return "60 seconds"
        }
    }

    public var availableInWidget: Bool { self != .minute }

    /// Mean tropical year — the actual solstice-to-solstice year, used for
    /// both the year fundamental's frequency and the year phase so the two
    /// are a single clock.
    public static let tropicalYearDays: Double = 365.24219
    public static var tropicalYearSeconds: TimeInterval { tropicalYearDays * 24 * 60 * 60 }

    public var cycleDuration: TimeInterval {
        switch self {
        case .year:        return Self.tropicalYearSeconds
        case .moon:        return MoonPhase.synodicMonthSeconds
        case .quarterMoon: return MoonPhase.synodicMonthSeconds / 4
        case .day:         return 24 * 60 * 60
        case .hour:        return 60 * 60
        case .minute:      return 60
        }
    }

    /// Indicator position. **Always UTC** so two devices in different
    /// timezones see the same dot at the same instant — harmonics,
    /// snapshot comparability, and the macOS auto-poster all depend on
    /// this being globally synchronized. Display text (see
    /// `traditionalLabel`) stays on the local calendar.
    public func degree(at date: Date, calendar: Calendar = Self.utcCalendar) -> Double {
        switch self {
        case .year:        return Self.yearDegree(at: date, calendar: calendar)
        case .moon:        return MoonPhase.moonDegree(at: date)
        case .quarterMoon: return MoonPhase.quarterMoonDegree(at: date)
        case .day:         return Self.dayDegree(at: date, calendar: calendar)
        case .hour:        return Self.hourDegree(at: date, calendar: calendar)
        case .minute:      return Self.minuteDegree(at: date, calendar: calendar)
        }
    }

    public static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    public func traditionalLabel(at date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute, .second, .nanosecond],
            from: date
        )
        switch self {
        case .year:
            return String(comps.year ?? 0)
        case .moon:
            let m = max(1, min(12, comps.month ?? 1))
            return "\(Self.monthNames[m - 1]) \(comps.day ?? 0)"
        case .quarterMoon:
            let w = max(1, min(7, comps.weekday ?? 1))
            return Self.dayNames[w - 1]
        case .day:
            return String(format: "%02d:%02d:%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
        case .hour:
            return String(format: "%02d:%02d", comps.minute ?? 0, comps.second ?? 0)
        case .minute:
            let tenths = (comps.nanosecond ?? 0) / 100_000_000
            return String(format: "%02d.%d", comps.second ?? 0, tenths)
        }
    }

    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let dayNames = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]

    /// Year phase 0° = December solstice, advancing by the mean tropical
    /// year. An astronomical anchor (the same instant for every observer
    /// on Earth) instead of the civil Jan 1 convention; Jan 1 now sits
    /// ~9.9° into the cycle.
    private static func yearDegree(at date: Date, calendar: Calendar) -> Double {
        let elapsed = date.timeIntervalSince(PhaseEpoch.decemberSolstice)
        var frac = (elapsed / tropicalYearSeconds).truncatingRemainder(dividingBy: 1)
        if frac < 0 { frac += 1 }
        return frac * 360
    }

    private static func dayDegree(at date: Date, calendar: Calendar) -> Double {
        let startOfDay = calendar.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(startOfDay)
        return (elapsed / (24 * 60 * 60)) * 360
    }

    private static func hourDegree(at date: Date, calendar: Calendar) -> Double {
        let comps = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
        let seconds = Double(comps.minute ?? 0) * 60
            + Double(comps.second ?? 0)
            + Double(comps.nanosecond ?? 0) / 1_000_000_000
        return (seconds / 3600) * 360
    }

    private static func minuteDegree(at date: Date, calendar: Calendar) -> Double {
        let comps = calendar.dateComponents([.second, .nanosecond], from: date)
        let seconds = Double(comps.second ?? 0)
            + Double(comps.nanosecond ?? 0) / 1_000_000_000
        return (seconds / 60) * 360
    }
}
