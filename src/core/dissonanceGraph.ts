/**
 * Port of ExochronometerCore/DissonanceGraph.swift
 *
 * Time window the cumulative dissonance graph covers, plus the pure-function
 * sampler that walks it.
 */

import { activeTonesForScales, isFundamental } from "./harmonicAnalysis.js";
import { totalTenney, totalEntropy, tenneyMeterMax, entropyMeterMax } from "./dissonanceMath.js";

export type DissonanceGraphRange = "oneDay" | "oneQuarterMoon";

/** Swift `CaseIterable.allCases`, in declaration order. */
export const allRanges: DissonanceGraphRange[] = ["oneDay", "oneQuarterMoon"];

/** Swift computed property `DissonanceGraphRange.seconds`. */
export function rangeSeconds(range: DissonanceGraphRange): number {
  switch (range) {
    case "oneDay":
      return 86400;
    case "oneQuarterMoon":
      return (86400 * 29.530588853) / 4;
  }
}

/** Swift computed property `DissonanceGraphRange.label`. */
export function rangeLabel(range: DissonanceGraphRange): string {
  switch (range) {
    case "oneDay":
      return "1 DAY";
    case "oneQuarterMoon":
      return "1 QTR MOON";
  }
}

export interface DissonanceGraphSample {
  date: Date;
  /** perPair / meterMax (>1 means spillover) */
  tenneyNormalized: number;
  entropyNormalized: number;
  pairCount: number;
}

/**
 * Pure-function sampler. Caller is responsible for running this on a
 * background priority - 240 buckets x tone-set computation can take ~1 s
 * wall-clock.
 */
export function samples(
  endingAt: Date,
  range: DissonanceGraphRange,
  includeFundamentals: boolean,
  scaling = 23,
  bucketCount = 240,
): DissonanceGraphSample[] {
  const rangeSecs = rangeSeconds(range);
  const bucketSeconds = rangeSecs / bucketCount;
  const out: DissonanceGraphSample[] = [];
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
