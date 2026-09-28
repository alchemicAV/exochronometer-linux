/**
 * Port of ExochronometerCore/DissonanceMath.swift
 *
 * Shared pairwise dissonance and entropy calculations. Both iOS Misc page
 * and Mac dissonance widget call into these so the math is consistent
 * across platforms.
 */

import { type TimeFrame } from "./timeFrame.js";

/**
 * Port of ExochronometerCore/HarmonicAnalysis.swift's `HarmonicTone`.
 *
 * NOTE: `HarmonicAnalysis.swift` is not part of this port's assigned file
 * set, so the struct both `DissonanceMath` and `PhasePortraitMath` take as
 * input is declared here (the lowest-level file that needs it) rather than
 * being imported from a not-yet-existing `./harmonicAnalysis.js`. The field
 * set, names and order are verbatim from the Swift struct; move this to
 * `harmonicAnalysis.ts` if/when that file is ported.
 */
export interface HarmonicTone {
  timeframe: TimeFrame;
  /** 1 for the fundamental, 3..8 for overtones. */
  divisions: number;
  /** Winding number k of the source shape; 1 for fundamentals, regular polygons, and k=2 aliases. */
  skip: number;
  /** Octaves of 2 by which the natural frequency is shifted. */
  scaling: number;
  /** Scaled frequency in Hz. */
  frequency: number;
  /** 0..1 */
  amplitude: number;
}

/**
 * JI ratio set used by every per-pair calculation. 5-limit + harmonic
 * 7th, anchored at A - same set the cents wheel labels with.
 */
export const jiRatios: { n: number; d: number }[] = [
  { n: 1, d: 1 }, { n: 16, d: 15 }, { n: 9, d: 8 }, { n: 6, d: 5 }, { n: 5, d: 4 }, { n: 4, d: 3 },
  { n: 45, d: 32 }, { n: 3, d: 2 }, { n: 8, d: 5 }, { n: 5, d: 3 }, { n: 7, d: 4 }, { n: 15, d: 8 }, { n: 2, d: 1 },
];

/**
 * Per-pair Tenney height - weighted average of JI ratio complexities
 * using a Gaussian kernel over cents distance.
 */
export function pairTenney(cents: number, sigma = 30): number {
  const octave = octaveCents(cents);
  let weighted = 0;
  let weightSum = 0;
  for (const { n, d } of jiRatios) {
    const ratioCents = 1200 * Math.log2(n / d);
    const dist = Math.min(
      Math.abs(octave - ratioCents),
      Math.abs(octave - ratioCents - 1200),
      Math.abs(octave - ratioCents + 1200),
    );
    const w = Math.exp((-dist * dist) / (2 * sigma * sigma));
    weighted += Math.log2(n * d) * w;
    weightSum += w;
  }
  return weightSum > 0 ? weighted / weightSum : Math.log2(45.0 * 32.0);
}

/**
 * Per-pair Shannon entropy - entropy of the JI-ratio identification
 * distribution. High = ambiguous interval; low = clearly resolves to
 * one JI ratio.
 */
export function pairEntropy(cents: number, sigma = 30): number {
  const octave = octaveCents(cents);
  const probs: number[] = [];
  for (const { n, d } of jiRatios) {
    const ratioCents = 1200 * Math.log2(n / d);
    const dist = Math.min(
      Math.abs(octave - ratioCents),
      Math.abs(octave - ratioCents - 1200),
      Math.abs(octave - ratioCents + 1200),
    );
    probs.push(Math.exp((-dist * dist) / (2 * sigma * sigma)));
  }
  const sum = probs.reduce((acc, p) => acc + p, 0);
  if (!(sum > 0)) return Math.log(jiRatios.length);
  let h = 0;
  for (const p of probs) {
    if (p > 1e-10) {
      const pn = p / sum;
      h -= pn * Math.log(pn);
    }
  }
  return h;
}

/** Amplitude-weighted total Tenney across all active pairs. */
export function totalTenney(tones: HarmonicTone[]): number {
  if (tones.length < 2) return 0;
  let total = 0;
  for (let i = 0; i < tones.length; i++) {
    for (let j = i + 1; j < tones.length; j++) {
      const a = tones[i];
      const b = tones[j];
      if (!(a.frequency > 0) || !(b.frequency > 0)) continue;
      const lo = Math.min(a.frequency, b.frequency);
      const hi = Math.max(a.frequency, b.frequency);
      const cents = Math.abs(1200 * Math.log2(hi / lo));
      total += pairTenney(cents) * a.amplitude * b.amplitude;
    }
  }
  return total;
}

/** Amplitude-weighted total entropy across all active pairs. */
export function totalEntropy(tones: HarmonicTone[]): number {
  if (tones.length < 2) return 0;
  let total = 0;
  for (let i = 0; i < tones.length; i++) {
    for (let j = i + 1; j < tones.length; j++) {
      const a = tones[i];
      const b = tones[j];
      if (!(a.frequency > 0) || !(b.frequency > 0)) continue;
      const cents = Math.abs(1200 * Math.log2(b.frequency / a.frequency));
      total += pairEntropy(cents) * a.amplitude * b.amplitude;
    }
  }
  return total;
}

/**
 * Swift's `truncatingRemainder` is C `fmod`, which JS `%` matches exactly
 * (same sign as the dividend, exact for these magnitudes).
 */
function octaveCents(cents: number): number {
  return ((cents % 1200) + 1200) % 1200;
}

/**
 * Calibration constants for the dissonance and entropy meters.
 *
 * `...MeterMax` is the per-pair value at which the meter reads 100%,
 * derived from the 99th percentile of a 1-year simulation (5-min
 * sampling from `PhaseEpoch.instant`, `includeFundamentals = false`).
 * Values above this trigger the spillover overlay. Spillover display
 * is capped at `+spilloverDisplayCap%` to keep the UI bounded.
 *
 * NOTE: these values predate the v2 changes (solstice-anchored tropical
 * year, Metonic epoch, {7/3} and {8/3} winding tones). The winding tones
 * add pairs with new pitch classes (7/6, 4/3), which shifts the
 * distribution - re-run the Mac app's Calibration menu and update these.
 */
export const tenneyMeterMax = 3.95;
export const entropyMeterMax = 0.336;

/**
 * Upper bound on the spillover percentage shown in the UI. The
 * simulation max came in around +225% for Tenney and +180% for
 * Entropy; 300% gives generous headroom for once-a-year extremes
 * while preventing pathological cases from producing absurd text.
 */
export const spilloverDisplayCap = 300;
