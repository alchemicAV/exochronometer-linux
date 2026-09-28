/**
 * Port of ExochronometerCore/HarmonicColor.swift
 *
 * A tone's frequency mapped to a position on the closed octave colour wheel
 * (R -> Y -> G -> C -> B -> M -> R). Shared by the Color Mapping mode and by
 * the normalized Phase Portrait so its overlaid curves match the Color Mapping
 * hues.
 */
/**
 * Pitch class as a hue in [0, 1). Uses log2(frequency) modulo 1 so
 * equal-temperament octaves wrap cleanly.
 */
export function hue(forFrequency) {
    if (!(forFrequency > 0))
        return 0;
    const logF = Math.log2(forFrequency);
    let h = logF - Math.floor(logF);
    if (h < 0)
        h += 1;
    return h;
}
/** Closed octave wheel: R -> Y -> G -> C -> B -> M -> R. */
export function hueToRGB(hueValue) {
    const h = hueValue * 6;
    // Swift's truncatingRemainder(dividingBy:) truncates toward zero; JS `%`
    // does the same, so negative hues normalise identically.
    const mod = h % 6;
    const normalized = mod < 0 ? mod + 6 : mod;
    const i = Math.trunc(normalized);
    const f = normalized - i;
    if (i === 0)
        return { r: 1, g: f, b: 0 };
    if (i === 1)
        return { r: 1 - f, g: 1, b: 0 };
    if (i === 2)
        return { r: 0, g: 1, b: f };
    if (i === 3)
        return { r: 0, g: 1 - f, b: 1 };
    if (i === 4)
        return { r: f, g: 0, b: 1 };
    return { r: 1, g: 0, b: 1 - f };
}
/** Amplitude-weighted colour blend across a list of tones. Black if none. */
export function blendedColor(tones) {
    let r = 0, g = 0, b = 0, w = 0;
    for (const tone of tones) {
        if (!(tone.frequency > 0))
            continue;
        const c = hueToRGB(hue(tone.frequency));
        r += c.r * tone.amplitude;
        g += c.g * tone.amplitude;
        b += c.b * tone.amplitude;
        w += tone.amplitude;
    }
    if (!(w > 0))
        return { r: 0, g: 0, b: 0 };
    return { r: r / w, g: g / w, b: b / w };
}
