/**
 * Port of ExochronometerCore/PhasePortraitMath.swift
 *
 * Phase-portrait analytics shared by Mac widget and iOS Misc page.
 */

import { type HarmonicTone } from "./dissonanceMath.js";

/**
 * Closure tolerance: each tone is considered "closing" if its
 * cycle count is within `tolerance` of an integer. 0.05 ~ 18 degrees of
 * phase error at the window endpoint - barely perceptible visually.
 */
export const defaultTolerance = 0.05;

/** Swift's `Double.rounded()` rounds half away from zero; JS Math.round does not. */
function swiftRound(x: number): number {
  return Math.sign(x) * Math.floor(Math.abs(x) + 0.5);
}

/**
 * A phase portrait curve traces `frequency x window` cycles. The
 * curve closes (visual loop ending where it started) when every
 * constituent tone makes an integer number of cycles in the window.
 * Returns true iff every tone's cycle count is within `tolerance` of
 * an integer.
 */
export function isLoopClosed(
  tones: HarmonicTone[],
  windowSeconds: number,
  tolerance: number = defaultTolerance,
): boolean {
  if (tones.length === 0 || !(windowSeconds > 0)) return false;
  for (const tone of tones) {
    const cycles = tone.frequency * windowSeconds;
    const off = Math.abs(cycles - swiftRound(cycles));
    if (off > tolerance) return false;
  }
  return true;
}
