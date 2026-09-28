/**
 * Port of ExochronometerCore/JustIntonation.swift
 * 5-limit just intonation pitches relative to A = 432 Hz.
 */
export const referenceA = 432.0;
export const ratios = [
    { name: "A", ratio: 1.0 },
    { name: "A♯", ratio: 16 / 15 },
    { name: "B", ratio: 9 / 8 },
    { name: "C", ratio: 6 / 5 },
    { name: "C♯", ratio: 5 / 4 },
    { name: "D", ratio: 4 / 3 },
    { name: "D♯", ratio: 45 / 32 },
    { name: "E", ratio: 3 / 2 },
    { name: "F", ratio: 8 / 5 },
    { name: "F♯", ratio: 5 / 3 },
    { name: "G", ratio: 16 / 9 },
    { name: "G♯", ratio: 15 / 8 },
];
/** Each note's cents-from-A position (for the cents wheel labels). */
export const labels = ratios.map((r) => ({
    name: r.name,
    cents: 1200 * Math.log2(r.ratio),
}));
/**
 * Octave-reduces `frequency` into [referenceA, 2*referenceA), then picks the
 * JI note nearest in cents. Also probes the next-octave A so a just-below-octave
 * frequency snaps to A above instead of G# way below.
 */
export function closestNote(frequency) {
    if (!(frequency > 0) || !Number.isFinite(frequency)) {
        return { noteName: "—", centsDelta: 0 };
    }
    let f = frequency;
    while (f < referenceA)
        f *= 2;
    while (f >= 2 * referenceA)
        f /= 2;
    let bestName = "A";
    let bestAbsCents = Number.POSITIVE_INFINITY;
    let bestSigned = 0;
    for (const { name, ratio } of ratios) {
        const pitch = ratio * referenceA;
        const cents = 1200 * Math.log2(f / pitch);
        if (Math.abs(cents) < bestAbsCents) {
            bestAbsCents = Math.abs(cents);
            bestSigned = cents;
            bestName = name;
        }
    }
    const centsToHighA = 1200 * Math.log2(f / (2 * referenceA));
    if (Math.abs(centsToHighA) < bestAbsCents) {
        bestAbsCents = Math.abs(centsToHighA);
        bestSigned = centsToHighA;
        bestName = "A";
    }
    return { noteName: bestName, centsDelta: bestSigned };
}
