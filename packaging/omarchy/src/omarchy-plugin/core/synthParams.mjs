/** Swift's `SynthParams()` memberwise default init. */
export function makeSynthParams() {
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
export const reverbPresetNames = [
    "Small Room", "Medium Room", "Medium Hall", "Large Hall", "Cathedral", "Plate",
];
/**
 * A strictly information-preserving voicing: softened, rolled-off,
 * reverbed, stereo-doubled - but every frequency is one the chord already
 * contained. This is the default.
 */
export const safePad = makeSynthParams();
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
export function resetTimbre(params) {
    params.unisonVoices = 2;
    params.detuneCents = 0;
    params.enrichment = 0;
    params.partials = 3;
    params.partialTilt = 1.4;
    return params;
}
/**
 * RFC 4122 v4 UUID. Swift's `UUID()` default argument has no portable JS
 * equivalent; QML's V4 engine has no `crypto.randomUUID`, so this is
 * hand-rolled from `Math.random`. Nothing numeric in this port depends on
 * it - it is only used as the default id of a preset.
 */
function uuidV4() {
    const hex = "0123456789abcdef";
    let out = "";
    for (let i = 0; i < 36; i++) {
        if (i === 8 || i === 13 || i === 18 || i === 23) {
            out += "-";
            continue;
        }
        if (i === 14) {
            out += "4";
            continue;
        }
        const r = Math.floor(Math.random() * 16);
        // variant nibble: 8, 9, a or b
        out += i === 19 ? hex[(r & 0x3) | 0x8] : hex[r];
    }
    return out;
}
/** Swift's `SynthPreset(id:name:params:savedAt:)` init, with the same defaults. */
export function makeSynthPreset(name, params, id = uuidV4(), savedAt = new Date()) {
    return { id, name, params, savedAt };
}
