import Foundation

/// All knob/switch values for the harmonic synth voicing layer.
///
/// The tone *bank* (which frequencies sound, and at what amplitude) is fixed
/// by the geometry — that is the instrument's information and it is never
/// touched here. These parameters shape only how that fixed set is *rendered*
/// to audio. The fields are grouped by whether they can introduce frequencies
/// the chord didn't already contain:
///
/// - **Information-safe** (envelope, tone, space, movement, width): add no new
///   pitch classes. Every cents relationship the meters measure stays exact;
///   reverb and the low-pass only *remove* or smear energy, never invent it.
/// - **Information-trading** (unison detune, harmonic enrichment): add
///   frequencies near or on the real tones. Default to neutral so the engine
///   starts as a softened-but-honest pad; they exist to be auditioned, with
///   the understanding that e.g. a 3rd partial on the day lands on the hour.
public struct SynthParams: Codable, Equatable, Sendable {
    // MARK: Envelope — information-safe
    /// Per-tone amplitude slew toward its geometry target. Removes the 30 Hz
    /// update zipper and softens note on/off into a pad swell.
    public var attackMs: Double = 150
    public var releaseMs: Double = 800

    // MARK: Tone — information-safe (global low-pass)
    /// Rolls off the piercing top end — the hour tone (2.3 kHz) and its
    /// partials up to ~18 kHz are what read as tinnitus. Removes energy only.
    public var lowpassHz: Double = 2700

    // MARK: Space — information-safe (reverb)
    /// Wet/dry, 0…100. The single biggest "pad" move: smears existing tones
    /// in time, introduces no frequency.
    public var reverbMix: Double = 80
    /// Index into `SynthParams.reverbPresetNames`.
    public var reverbPreset: Int = 4

    // MARK: Movement — information-safe
    /// Sub-audio amplitude LFO. Gentle "breathing"; its sidebands are sub-Hz
    /// and perceptually inaudible as pitch.
    public var tremoloRateHz: Double = 0
    public var tremoloDepth: Double = 0
    /// Stereo spread of the unison voices, 0…1. With ≥2 voices at detune 0
    /// this is phase-decorrelated doubling — width with no new frequencies.
    public var width: Double = 0.35

    // MARK: Timbre — ALTERS THE CHORD (information-trading; default neutral)
    /// Copies per tone, 1…3. Two at detune 0 = information-safe doubling.
    public var unisonVoices: Int = 2
    /// Cents spread across the unison voices. 0 = pure; >0 = chorus shimmer
    /// that blurs the exact intervals the meters read.
    public var detuneCents: Double = 2.2
    /// Mix of added integer partials (k·f), 0…1. 0 = pure sine. Above 0 this
    /// fabricates frequencies that can coincide with real tones in the bank.
    public var enrichment: Double = 0.8
    /// Number of added partials above the fundamental, k = 2…(1+partials).
    public var partials: Int = 3
    /// Partial rolloff exponent: gain(k) = enrichment / k^tilt.
    public var partialTilt: Double = 0

    public init() {}

    /// Display names for the reverb presets, indexed by `reverbPreset`.
    public static let reverbPresetNames = [
        "Small Room", "Medium Room", "Medium Hall", "Large Hall", "Cathedral", "Plate",
    ]

    /// A strictly information-preserving voicing: softened, rolled-off,
    /// reverbed, stereo-doubled — but every frequency is one the chord already
    /// contained. This is the default.
    public static let safePad = SynthParams()

    /// Zero out every information-trading knob (back to pure sines, mono-safe
    /// doubling). Leaves the safe effects alone.
    public mutating func resetTimbre() {
        unisonVoices = 2
        detuneCents = 0
        enrichment = 0
        partials = 3
        partialTilt = 1.4
    }
}

/// A named, saveable voicing. Exported to a JSON file so a sound can move
/// between machines and survive a wipe.
public struct SynthPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var params: SynthParams
    public var savedAt: Date

    public init(id: UUID = UUID(), name: String, params: SynthParams, savedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.params = params
        self.savedAt = savedAt
    }
}
