/**
 * Port of ExochronometerCore/SynthParams.swift
 *
 * All knob/switch values for the harmonic synth voicing layer.
 *
 * The tone *bank* (which frequencies sound, and at what amplitude) is fixed
 * by the geometry - that is the instrument's information and it is never
 * touched here. These parameters shape only how that fixed set is *rendered*
 * to audio. The fields are grouped by whether they can introduce frequencies
 * the chord didn't already contain:
 *
 * - **Information-safe** (envelope, tone, space, movement, width): add no new
 *   pitch classes. Every cents relationship the meters measure stays exact;
 *   reverb and the low-pass only *remove* or smear energy, never invent it.
 * - **Information-trading** (unison detune, harmonic enrichment): add
 *   frequencies near or on the real tones. Default to neutral so the engine
 *   starts as a softened-but-honest pad; they exist to be auditioned, with
 *   the understanding that e.g. a 3rd partial on the day lands on the hour.
 */
export interface SynthParams {
  // Envelope - information-safe
  /** Per-tone amplitude slew toward its geometry target. Removes the 30 Hz update zipper and softens note on/off into a pad swell. */
  attackMs: number;
  releaseMs: number;

  // Tone - information-safe (global low-pass)
  /** Rolls off the piercing top end - the hour tone (2.3 kHz) and its partials up to ~18 kHz are what read as tinnitus. Removes energy only. */
  lowpassHz: number;

  // Space - information-safe (reverb)
  /** Wet/dry, 0...100. The single biggest "pad" move: smears existing tones in time, introduces no frequency. */
  reverbMix: number;
  /** Index into `reverbPresetNames`. */
  reverbPreset: number;

  // Movement - information-safe
  /** Sub-audio amplitude LFO. Gentle "breathing"; its sidebands are sub-Hz and perceptually inaudible as pitch. */
  tremoloRateHz: number;
  tremoloDepth: number;
  /** Stereo spread of the unison voices, 0...1. With >=2 voices at detune 0 this is phase-decorrelated doubling - width with no new frequencies. */
  width: number;

  // Timbre - ALTERS THE CHORD (information-trading; default neutral)
  /** Copies per tone, 1...3. Two at detune 0 = information-safe doubling. */
  unisonVoices: number;
  /** Cents spread across the unison voices. 0 = pure; >0 = chorus shimmer that blurs the exact intervals the meters read. */
  detuneCents: number;
  /** Mix of added integer partials (k*f), 0...1. 0 = pure sine. Above 0 this fabricates frequencies that can coincide with real tones in the bank. */
  enrichment: number;
  /** Number of added partials above the fundamental, k = 2...(1+partials). */
  partials: number;
  /** Partial rolloff exponent: gain(k) = enrichment / k^tilt. */
  partialTilt: number;
}

/** Swift's `SynthParams()` memberwise default init. */
export function makeSynthParams(): SynthParams {
  return {
    attackMs: 150,
    releaseMs: 800,
    lowpassHz: 2700,
    reverbMix: 80,
    reverbPreset: 4,
    tremoloRateHz: 0,
    tremoloDepth: 0,
    width: 0.35,
    unisonVoices: 2,
    detuneCents: 2.2,
    enrichment: 0.8,
    partials: 3,
    partialTilt: 0,
  };
}

/** Display names for the reverb presets, indexed by `reverbPreset`. */
export const reverbPresetNames: string[] = [
  "Small Room", "Medium Room", "Medium Hall", "Large Hall", "Cathedral", "Plate",
];

/**
 * A strictly information-preserving voicing: softened, rolled-off,
 * reverbed, stereo-doubled - but every frequency is one the chord already
 * contained. This is the default.
 */
export const safePad: SynthParams = makeSynthParams();

/**
 * Zero out every information-trading knob (back to pure sines, mono-safe
 * doubling). Leaves the safe effects alone.
 *
 * Swift's `mutating func resetTimbre()` mutates in place; JS has no value
 * semantics for object literals, so this mutates the passed object like the
 * Swift method does and also returns it for convenience. It deliberately
 * does NOT touch `detuneCents`' siblings outside the fixed list below, nor
 * `attackMs`/`releaseMs`/`lowpassHz`/`reverbMix`/`reverbPreset`/
 * `tremoloRateHz`/`tremoloDepth`/`width`.
 */
export function resetTimbre(params: SynthParams): SynthParams {
  params.unisonVoices = 2;
  params.detuneCents = 0;
  params.enrichment = 0;
  params.partials = 3;
  params.partialTilt = 1.4;
  return params;
}

/**
 * A named, saveable voicing. Exported to a JSON file so a sound can move
 * between machines and survive a wipe.
 *
 * Swift's `UUID` becomes a `string` and `Date` stays a `Date`.
 */
export interface SynthPreset {
  id: string;
  name: string;
  params: SynthParams;
  savedAt: Date;
}

/**
 * RFC 4122 v4 UUID. Swift's `UUID()` default argument has no portable JS
 * equivalent; QML's V4 engine has no `crypto.randomUUID`, so this is
 * hand-rolled from `Math.random`. Nothing numeric in this port depends on
 * it - it is only used as the default id of a preset.
 */
function uuidV4(): string {
  const hex = "0123456789abcdef";
  let out = "";
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) { out += "-"; continue; }
    if (i === 14) { out += "4"; continue; }
    const r = Math.floor(Math.random() * 16);
    // variant nibble: 8, 9, a or b
    out += i === 19 ? hex[(r & 0x3) | 0x8] : hex[r];
  }
  return out;
}

/** Swift's `SynthPreset(id:name:params:savedAt:)` init, with the same defaults. */
export function makeSynthPreset(
  name: string,
  params: SynthParams,
  id: string = uuidV4(),
  savedAt: Date = new Date(),
): SynthPreset {
  return { id, name, params, savedAt };
}
