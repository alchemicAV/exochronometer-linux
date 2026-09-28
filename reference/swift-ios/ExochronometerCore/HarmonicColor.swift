import SwiftUI

/// Mapping from a tone's frequency to a position on the closed octave
/// color wheel (RGB → magenta → RGB). Shared by ColorMapping widget,
/// per-timeframe color stripes elsewhere, and the normalized
/// PhasePortrait widget so its overlaid curves match the colors used
/// in ColorMapping.
public enum HarmonicColor {
    /// Pitch class as a hue in [0, 1). Uses log₂(frequency) modulo 1
    /// so equal-temperament octaves wrap cleanly.
    public static func hue(forFrequency freq: Double) -> Double {
        guard freq > 0 else { return 0 }
        let logF = log2(freq)
        var hue = logF - floor(logF)
        if hue < 0 { hue += 1 }
        return hue
    }

    /// Amplitude-weighted color blend across a list of tones. Returns
    /// black if no tones contribute.
    public static func blendedColor(of tones: [HarmonicTone]) -> Color {
        var r: Double = 0, g: Double = 0, b: Double = 0, w: Double = 0
        for tone in tones {
            guard tone.frequency > 0 else { continue }
            let (cr, cg, cb) = hueToRGB(hue(forFrequency: tone.frequency))
            r += cr * tone.amplitude
            g += cg * tone.amplitude
            b += cb * tone.amplitude
            w += tone.amplitude
        }
        guard w > 0 else { return .black }
        return Color(red: r / w, green: g / w, blue: b / w)
    }

    /// Closed octave wheel: R → Y → G → C → B → M → R.
    public static func hueToRGB(_ hue: Double) -> (Double, Double, Double) {
        let h = hue * 6
        let mod = h.truncatingRemainder(dividingBy: 6)
        let normalized = mod < 0 ? mod + 6 : mod
        let i = Int(normalized)
        let f = normalized - Double(i)
        switch i {
        case 0:  return (1, f, 0)
        case 1:  return (1 - f, 1, 0)
        case 2:  return (0, 1, f)
        case 3:  return (0, 1 - f, 1)
        case 4:  return (f, 0, 1)
        default: return (1, 0, 1 - f)
        }
    }
}
