import Foundation

// Reference vectors for HarmonicColor - verbatim port target of
// reference/swift-ios/ExochronometerCore/HarmonicColor.swift
// (lines 11-50).

func hue(forFrequency freq: Double) -> Double {
    guard freq > 0 else { return 0 }
    let logF = log2(freq)
    var h = logF - floor(logF)
    if h < 0 { h += 1 }
    return h
}

func hueToRGB(_ hue: Double) -> (Double, Double, Double) {
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

struct BlendTone {
    let frequency: Double
    let amplitude: Double
}

func blendedColor(_ tones: [BlendTone]) -> (Double, Double, Double) {
    var r = 0.0, g = 0.0, b = 0.0, w = 0.0
    for tone in tones {
        guard tone.frequency > 0 else { continue }
        let (cr, cg, cb) = hueToRGB(hue(forFrequency: tone.frequency))
        r += cr * tone.amplitude
        g += cg * tone.amplitude
        b += cb * tone.amplitude
        w += tone.amplitude
    }
    guard w > 0 else { return (0, 0, 0) }
    return (r / w, g / w, b / w)
}

struct Bundle: Codable {
    struct HueRow: Codable { let freq: Double; let hue: Double }
    struct RgbRow: Codable { let hue: Double; let r: Double; let g: Double; let b: Double }
    struct BlendRow: Codable {
        let freqs: [Double]; let amps: [Double]
        let r: Double; let g: Double; let b: Double
    }
    let hues: [HueRow]
    let rgbs: [RgbRow]
    let blends: [BlendRow]
    let realTones: [BlendRow]
}

// Frequency sweep: includes sub-1 Hz (year/moon fundamentals at low scaling),
// powers of two (exact octaves -> hue 0), and non-dyadic values.
var freqs: [Double] = [0, -1, -0.5, 1e-9, 0.1, 0.5, 1, 2, 3, 4, 8, 16, 432, 440,
                       2330.17, 776.72, 420.84, 210.42, 17.01, 1e6, 2.4e9]
for i in 1...300 { freqs.append(Double(i) * 7.31) }
for i in 1...200 { freqs.append(pow(2.0, Double(i) / 24.0)) }   // quarter-tone steps
for i in 1...150 { freqs.append(Double(i) / 8.0) }

// Hue sweep including exact boundaries and negatives.
var hues: [Double] = [0, 0.1, 0.16666666666666666, 1.0 / 3.0, 0.5, 2.0 / 3.0,
                      0.8333333333333334, 0.9999999999, 1, 1.5, -0.1, -0.5, -1, -2.25]
for i in 0...200 { hues.append(Double(i) / 200.0) }

// Blends: real-ish tone sets plus edge cases (empty, all-zero amplitude,
// non-positive frequency skipped).
var blends: [( [Double], [Double] )] = [
    ([], []),
    ([440], [0]),
    ([440], [1]),
    ([0, 440], [1, 0.5]),
    ([440, 880], [1, 1]),
    ([210.42, 420.84, 841.67], [1.0, 0.42, 0.31]),
    ([17.01, 776.72, 2330.17], [1.0, 0.55, 0.12]),
    ([-5, 440], [0.5, 0.5]),
]
for i in 1...120 {
    let a = Double(i) * 3.7
    let b = Double(i) * 11.13
    let c = Double(i) * 0.53
    blends.append(([a, b, c], [1.0, Double(i % 10) / 10.0, Double(i % 7) / 7.0]))
}

let bundle = Bundle(
    hues: freqs.map { Bundle.HueRow(freq: $0, hue: hue(forFrequency: $0)) },
    rgbs: hues.map {
        let c = hueToRGB($0)
        return Bundle.RgbRow(hue: $0, r: c.0, g: c.1, b: c.2)
    },
    blends: blends.map {
        let c = blendedColor(zip($0.0, $0.1).map { BlendTone(frequency: $0, amplitude: $1) })
        return Bundle.BlendRow(freqs: $0.0, amps: $0.1, r: c.0, g: c.1, b: c.2)
    },
    realTones: []
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(bundle))