import Foundation
import ExochronometerCore

// Reference vector generator for the four dissonance/voicing files.
//
// Dumps the pure-function state of ChordCatalog, DissonanceMath,
// DissonanceCalibration, PhasePortraitMath and SynthParams as JSON so a port
// to another language can be diffed against the Swift original numerically.
// Everything emitted here is a pure function of the inputs listed in each
// row, so the output is fully reproducible. Run with TZ=UTC.

struct Bundle: Codable {
    struct ChordRow: Codable {
        let name: String
        let abbr: String
        let intervals: [Double]
        let toneCount: Int
    }
    struct JIRow: Codable {
        let n: Int
        let d: Int
    }
    struct PairRow: Codable {
        let cents: Double
        let sigma: Double
        let tenney: Double
        let entropy: Double
    }
    struct ToneRow: Codable {
        let timeframe: String
        let divisions: Int
        let skip: Int
        let scaling: Int
        let frequency: Double
        let amplitude: Double
    }
    struct TotalRow: Codable {
        let label: String
        let tones: [ToneRow]
        let tenney: Double
        let entropy: Double
    }
    struct LoopRow: Codable {
        let label: String
        let window: Double
        let tol: Double?          // nil = Swift default argument used
        let tones: [ToneRow]
        let closed: Bool
    }
    struct Calibration: Codable {
        let tenneyMeterMax: Double
        let entropyMeterMax: Double
        let spilloverDisplayCap: Int
    }
    struct SynthRow: Codable {
        let attackMs: Double
        let releaseMs: Double
        let lowpassHz: Double
        let reverbMix: Double
        let reverbPreset: Int
        let tremoloRateHz: Double
        let tremoloDepth: Double
        let width: Double
        let unisonVoices: Int
        let detuneCents: Double
        let enrichment: Double
        let partials: Int
        let partialTilt: Double
    }
    struct PresetRow: Codable {
        let id: String
        let name: String
        let savedAtMs: Double
        let params: SynthRow
    }

    let chordIntervals: [ChordRow]
    let chordTriads: [ChordRow]
    let chordTetrads: [ChordRow]
    let chordAll: [ChordRow]
    let chordChords: [ChordRow]
    let jiRatios: [JIRow]
    let pairs: [PairRow]
    let totals: [TotalRow]
    let loops: [LoopRow]
    let calibration: Calibration
    let synthDefaults: SynthRow
    let synthSafePad: SynthRow
    let synthResetTimbre: SynthRow
    let reverbPresetNames: [String]
    let preset: PresetRow
}

// --- helpers -----------------------------------------------------------------

func chordRows(_ patterns: [ChordPattern]) -> [Bundle.ChordRow] {
    patterns.map { Bundle.ChordRow(name: $0.name, abbr: $0.abbreviation,
                                   intervals: $0.intervals, toneCount: $0.toneCount) }
}

func tone(_ tf: TimeFrame, _ divisions: Int, _ skip: Int, _ scaling: Int,
          _ frequency: Double, _ amplitude: Double) -> HarmonicTone {
    HarmonicTone(timeframe: tf, divisions: divisions, skip: skip, scaling: scaling,
                 frequency: frequency, amplitude: amplitude)
}

func toneRows(_ tones: [HarmonicTone]) -> [Bundle.ToneRow] {
    tones.map {
        Bundle.ToneRow(timeframe: $0.timeframe.rawValue, divisions: $0.divisions,
                       skip: $0.skip, scaling: $0.scaling,
                       frequency: $0.frequency, amplitude: $0.amplitude)
    }
}

func synthRow(_ p: SynthParams) -> Bundle.SynthRow {
    Bundle.SynthRow(attackMs: p.attackMs, releaseMs: p.releaseMs, lowpassHz: p.lowpassHz,
                    reverbMix: p.reverbMix, reverbPreset: p.reverbPreset,
                    tremoloRateHz: p.tremoloRateHz, tremoloDepth: p.tremoloDepth,
                    width: p.width, unisonVoices: p.unisonVoices,
                    detuneCents: p.detuneCents, enrichment: p.enrichment,
                    partials: p.partials, partialTilt: p.partialTilt)
}

// --- chord tables ------------------------------------------------------------

let chordIntervals = chordRows(ChordCatalog.intervals)
let chordTriads = chordRows(ChordCatalog.triads)
let chordTetrads = chordRows(ChordCatalog.tetrads)
let chordAll = chordRows(ChordCatalog.all)
let chordChords = chordRows(ChordCatalog.chords)

// --- JI ratio table ----------------------------------------------------------

let jiRows = DissonanceMath.jiRatios.map { Bundle.JIRow(n: $0.n, d: $0.d) }

// --- per-pair sweep ----------------------------------------------------------

var centsSweep: [Double] = []

// coarse sweep over three octaves, both signs
var c = -2400.0
while c <= 2400.0 + 1e-9 {
    centsSweep.append(c)
    c += 25
}
// fine sweep around every JI ratio's own cents value (Gaussian kernel edges)
for r in DissonanceMath.jiRatios {
    let rc = 1200 * log2(Double(r.n) / Double(r.d))
    var off = -40.0
    while off <= 40.0 + 1e-9 {
        centsSweep.append(rc + off)
        off += 2
    }
    // exactly on the ratio and a hair either side of it
    centsSweep.append(rc)
    centsSweep.append(rc + 1e-9)
    centsSweep.append(rc - 1e-9)
}
// octave-reduction and half-way cases for the Gaussian kernel
centsSweep += [1200, 2400, -1200, -2400, 3600, -3600, 600, 1800, 3000,
               0, 0.5, -0.5, 1e-9, -1e-9, -0.0, 1199.9999999, 1200.0000001,
               1e6, -1e6, 1234567.891, 4321.5, -4321.5]

let sigmas: [Double] = [30, 1, 5, 20, 100, 1000, 1e-6, 1e9]

var pairs: [Bundle.PairRow] = []
pairs.reserveCapacity(centsSweep.count * sigmas.count)
for sigma in sigmas {
    for cents in centsSweep {
        pairs.append(Bundle.PairRow(
            cents: cents, sigma: sigma,
            tenney: DissonanceMath.pairTenney(cents: cents, sigma: sigma),
            entropy: DissonanceMath.pairEntropy(cents: cents, sigma: sigma)))
    }
}
// exercise the default sigma argument explicitly once
for cents in [-1200.0, -100, -1e-9, 0, 0.5, 100, 300, 700, 1200, 2400, 1e6] {
    pairs.append(Bundle.PairRow(
        cents: cents, sigma: 30,
        tenney: DissonanceMath.pairTenney(cents: cents),
        entropy: DissonanceMath.pairEntropy(cents: cents)))
}

// --- total Tenney / entropy over realistic tone sets -------------------------

// A432-anchored 5-limit+7th bank at realistic amplitudes, plus edge cases.
let a432 = 432.0
let ratios: [(Double, Double)] = [
    (1.0 / 1.0, 1.0), (16.0 / 15.0, 0.4), (9.0 / 8.0, 0.7), (6.0 / 5.0, 0.55),
    (5.0 / 4.0, 0.8), (4.0 / 3.0, 0.6), (45.0 / 32.0, 0.33), (3.0 / 2.0, 0.9),
    (8.0 / 5.0, 0.45), (5.0 / 3.0, 0.5), (7.0 / 4.0, 0.42), (15.0 / 8.0, 0.29),
    (2.0 / 1.0, 0.35), (7.0 / 3.0, 0.22), (8.0 / 3.0, 0.18),
]

var toneSets: [(String, [HarmonicTone])] = []
toneSets.append(("empty", []))
toneSets.append(("single", [tone(.hour, 1, 1, 0, a432, 1.0)]))
toneSets.append(("two-octave", [
    tone(.hour, 1, 1, 0, a432, 0.8),
    tone(.hour, 1, 1, 1, a432 * 2, 0.5),
]))
toneSets.append(("two-fifth", [
    tone(.year, 1, 1, 0, a432, 1.0),
    tone(.minute, 3, 1, 5, a432 * 1.5, 0.6),
]))
toneSets.append(("triad", [
    tone(.year, 1, 1, 0, a432, 1.0),
    tone(.moon, 3, 1, 3, a432 * 1.25, 0.7),
    tone(.day, 3, 2, 4, a432 * 1.5, 0.5),
]))
// full JI bank
toneSets.append(("ji-bank", ratios.enumerated().map { (i, r) in
    tone(TimeFrame.allCases[i % TimeFrame.allCases.count], 1 + (i % 5),
         i % 3 == 0 ? 1 : 2, i % 7 - 3, a432 * r.0, r.1)
}))
// bank with zeros / negatives / repeated tones (exercises the `frequency > 0` guard)
toneSets.append(("degenerate", [
    tone(.day, 1, 1, 0, 0, 1.0),
    tone(.day, 1, 1, 0, a432, 1.0),
    tone(.day, 1, 1, 0, -a432, 0.5),
    tone(.day, 1, 1, 0, a432, 0.25),
    tone(.hour, 1, 1, 0, 0.001, 1.0),
    tone(.hour, 1, 1, 0, 1e6, 1.0),
    tone(.hour, 1, 1, 0, 1e300, 1.0),
]))
toneSets.append(("all-zero-amps", [
    tone(.year, 1, 1, 0, a432, 0),
    tone(.year, 1, 1, 0, a432 * 1.5, 0),
    tone(.year, 1, 1, 0, a432 * 1.2, 0),
]))
// a large bank, 20 tones
toneSets.append(("wide-20", (0..<20).map { i in
    tone(.minute, 1 + i % 6, 1 + i % 2, i % 5 - 2,
         a432 * (1.0 + Double(i) * 0.137), 0.1 + Double(i % 9) * 0.1)
}))

var totals: [Bundle.TotalRow] = []
for (label, tones) in toneSets {
    totals.append(Bundle.TotalRow(label: label, tones: toneRows(tones),
                                  tenney: DissonanceMath.totalTenney(tones),
                                  entropy: DissonanceMath.totalEntropy(tones)))
}

// --- phase-portrait loop closure --------------------------------------------

func f(_ hz: Double, _ amp: Double = 1.0) -> HarmonicTone {
    tone(.minute, 1, 1, 0, hz, amp)
}

var loopCases: [(String, [HarmonicTone], Double, Double?)] = []

// empty / non-positive window guards
loopCases.append(("empty-zero-window", [], 0, nil))
loopCases.append(("empty-positive-window", [], 10, nil))
loopCases.append(("one-zero-window", [f(1)], 0, nil))
loopCases.append(("one-negative-window", [f(1)], -10, nil))
// integer cycles
loopCases.append(("exact-integers", [f(1), f(2), f(3)], 1, nil))
loopCases.append(("exact-integers-long", [f(0.5), f(1.5), f(1200)], 2, nil))
// just inside / outside the default 0.05 tolerance
loopCases.append(("off-0.049", [f(1.049)], 1, nil))
loopCases.append(("off-0.051", [f(1.051)], 1, nil))
loopCases.append(("off-exact-tolerance", [f(1.05)], 1, nil))
loopCases.append(("off-minus-0.05", [f(0.95)], 1, nil))
// half-away-from-zero rounding: cycles = +/-0.5 must round to +/-1
loopCases.append(("half-cycle-positive", [f(0.5)], 1, nil))
loopCases.append(("half-cycle-negative", [f(-0.5)], 1, nil))
loopCases.append(("half-cycle-both", [f(0.5), f(1.5)], 2, nil))
loopCases.append(("neg-freq-integer", [f(-3)], 1, nil))
loopCases.append(("neg-freq-off", [f(-3.049)], 1, nil))
loopCases.append(("mixed-sign", [f(4), f(-4), f(8)], 1, nil))
// one bad tone among good ones
loopCases.append(("one-bad", [f(1), f(2), f(2.5)], 1, nil))
loopCases.append(("one-bad-last", [f(1), f(2), f(3), f(4.5)], 1, nil))
// explicit tolerances
for tol in [0.0, 1e-12, 0.001, 0.05, 0.1, 0.5, 100] {
    loopCases.append(("tol-\(tol)-exact", [f(1), f(2.5), f(7)], 1, tol))
    loopCases.append(("tol-\(tol)-off", [f(1.02), f(2.5), f(7)], 1, tol))
}
// windows other than 1
for w in [0.001, 0.5, 1, 2, 3.7, 60, 86400, 1000000, 1e-9] {
    loopCases.append(("window-\(w)-int", [f(1 / w), f(2 / w), f(3 / w)], w, nil))
    loopCases.append(("window-\(w)-off", [f(1 / w), f(2 / w), f(3 / w + 0.1 / w)], w, nil))
}
// denormals / tiny frequencies, and a big bank
loopCases.append(("tiny-freq", [f(1e-300), f(5e-324)], 1, nil))
loopCases.append(("huge-freq", [f(1e300), f(2e300)], 1, nil))
loopCases.append(("many-tones", (1...40).map { f(Double($0)) }, 1, nil))

var loops: [Bundle.LoopRow] = []
for (label, tones, window, tol) in loopCases {
    let closed: Bool
    if let t = tol {
        closed = PhasePortraitMath.isLoopClosed(tones: tones, windowSeconds: window, tolerance: t)
    } else {
        closed = PhasePortraitMath.isLoopClosed(tones: tones, windowSeconds: window)
    }
    loops.append(Bundle.LoopRow(label: label, window: window, tol: tol,
                                tones: toneRows(tones), closed: closed))
}

// --- calibration constants ---------------------------------------------------

let calibration = Bundle.Calibration(
    tenneyMeterMax: DissonanceCalibration.tenneyMeterMax,
    entropyMeterMax: DissonanceCalibration.entropyMeterMax,
    spilloverDisplayCap: DissonanceCalibration.spilloverDisplayCap)

// --- synth params ------------------------------------------------------------

let defaults = SynthParams()
var resetParams = SynthParams()
resetParams.resetTimbre()

let presetID = UUID(uuidString: "DE305D54-75B4-431B-ADB2-EB6B9E546014")!
let presetDate = Date(timeIntervalSince1970: 1_767_225_600)
let preset = SynthPreset(id: presetID, name: "Test Cathedral",
                         params: defaults, savedAt: presetDate)

let presetRow = Bundle.PresetRow(
    id: preset.id.uuidString, name: preset.name,
    savedAtMs: preset.savedAt.timeIntervalSince1970 * 1000,
    params: synthRow(preset.params))

// --- emit --------------------------------------------------------------------

let bundle = Bundle(
    chordIntervals: chordIntervals,
    chordTriads: chordTriads,
    chordTetrads: chordTetrads,
    chordAll: chordAll,
    chordChords: chordChords,
    jiRatios: jiRows,
    pairs: pairs,
    totals: totals,
    loops: loops,
    calibration: calibration,
    synthDefaults: synthRow(defaults),
    synthSafePad: synthRow(SynthParams.safePad),
    synthResetTimbre: synthRow(resetParams),
    reverbPresetNames: SynthParams.reverbPresetNames,
    preset: presetRow)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(bundle)
FileHandle.standardOutput.write(data)
