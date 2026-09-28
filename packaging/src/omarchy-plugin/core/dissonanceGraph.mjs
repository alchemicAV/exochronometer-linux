/**
 * Port of ExochronometerCore/DissonanceGraph.swift
 *
 * Time window the cumulative dissonance graph covers, plus the pure-function
 * sampler that walks it.
 */
import { activeTonesForScales, isFundamental } from "./harmonicAnalysis.mjs";
import { totalTenney, totalEntropy, tenneyMeterMax, entropyMeterMax } from "./dissonanceMath.mjs";
/** Swift `CaseIterable.allCases`, in declaration order. */
export const allRanges = ["oneDay", "oneQuarterMoon"];
/** Swift computed property `DissonanceGraphRange.seconds`. */
export function rangeSeconds(range) {
    switch (range) {
        case "oneDay":
            return 86400;
        case "oneQuarterMoon":
            return (86400 * 29.530588853) / 4;
    }
}
/** Swift computed property `DissonanceGraphRange.label`. */
export function rangeLabel(range) {
    switch (range) {
        case "oneDay":
            return "1 DAY";
        case "oneQuarterMoon":
            return "1 QTR MOON";
    }
}
/**
 * Pure-function sampler. Caller is responsible for running this on a
 * background priority - 240 buckets x tone-set computation can take ~1 s
 * wall-clock.
 */
export function samples(endingAt, range, includeFundamentals, scaling = 23, bucketCount = 240) {
    const rangeSecs = rangeSeconds(range);
    const bucketSeconds = rangeSecs / bucketCount;
    const out = [];
    for (let i = 0; i < bucketCount; i++) {
        const offset = (bucketCount - i) * bucketSeconds;
        const date = new Date(endingAt.getTime() - offset * 1000);
        let tones = activeTonesForScales(date, [scaling]);
        if (!includeFundamentals) {
            tones = tones.filter((t) => !isFundamental(t));
        }
        const pairCount = Math.max(1, Math.floor((tones.length * (tones.length - 1)) / 2));
        const tenneyPerPair = totalTenney(tones) / pairCount;
        const entropyPerPair = totalEntropy(tones) / pairCount;
        const tNorm = tenneyPerPair / tenneyMeterMax;
        const eNorm = entropyPerPair / entropyMeterMax;
        out.push({
            date,
            tenneyNormalized: tNorm,
            entropyNormalized: eNorm,
            pairCount,
        });
    }
    return out;
}
