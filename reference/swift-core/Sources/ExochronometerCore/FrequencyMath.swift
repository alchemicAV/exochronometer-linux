import Foundation

public enum FrequencyMath {
    public static let audibleMinHz: Double = 20
    public static let audibleMaxHz: Double = 20_000

    /// f = 1 / period
    public static func hz(forPeriod seconds: TimeInterval) -> Double {
        guard seconds > 0 else { return 0 }
        return 1.0 / seconds
    }

    /// Multiply by 2^n (n octaves up). Preserves all harmonic ratios.
    public static func scaled(_ hz: Double, octaves: Int) -> Double {
        hz * pow(2.0, Double(octaves))
    }

    /// Pretty-print a frequency. Below 1 Hz, displays as a time period;
    /// above, as Hz / kHz / MHz.
    public static func format(_ hz: Double) -> String {
        if !hz.isFinite || hz <= 0 { return "—" }
        if hz < 1 {
            let seconds = 1.0 / hz
            return formatDuration(seconds)
        } else if hz >= 1_000_000 {
            return String(format: "%.2f MHz", hz / 1_000_000)
        } else if hz >= 1_000 {
            return String(format: "%.2f kHz", hz / 1_000)
        } else {
            return String(format: "%.2f Hz", hz)
        }
    }

    /// Pretty-print a duration in seconds.
    public static func formatDuration(_ seconds: Double) -> String {
        let year: Double = TimeFrame.tropicalYearSeconds
        let day: Double = 24 * 60 * 60
        let hour: Double = 60 * 60

        if seconds >= year {
            return String(format: "%.2f years", seconds / year)
        } else if seconds >= day {
            return String(format: "%.2f days", seconds / day)
        } else if seconds >= hour {
            return String(format: "%.2f hours", seconds / hour)
        } else if seconds >= 60 {
            return String(format: "%.2f min", seconds / 60)
        } else {
            return String(format: "%.2f sec", seconds)
        }
    }
}
