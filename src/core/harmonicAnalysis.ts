/**
 * Port of ExochronometerCore/HarmonicAnalysis.swift
 *
 * Enumerates the tones the instrument is currently sounding: one fundamental
 * per (timeframe, scale) plus every overtone / winding tone whose fade
 * opacity clears the threshold at the requested instant.
 */

import { type TimeFrame, allCases, cycleDuration, degree } from "./timeFrame.js";
import { type HarmonicTone } from "./dissonanceMath.js";
import { defaultShapes, oddPart } from "./geometry.js";
import { shapeOpacity, timeframeState, nodeActivation } from "./fadeMath.js";

/**
 * `HarmonicTone` is declared in `dissonanceMath.ts` (the lowest-level module
 * that needs it). Re-exported here so consumers can take it from the same
 * module as the analysis that produces it.
 */
export type { HarmonicTone };

/** Mirrors Swift's `ToneAssignment`. */
export interface ToneAssignment {
  timeframe: TimeFrame;
  scale: number;
}

/** Swift computed property `HarmonicTone.id`. */
export function toneId(t: HarmonicTone): string {
  return `${t.timeframe}-${t.divisions}/${t.skip}-${t.scaling}`;
}

/** Swift computed property `HarmonicTone.isFundamental`. */
export function isFundamental(t: HarmonicTone): boolean {
  return t.divisions === 1;
}

/** Swift computed property `HarmonicTone.divisionLabel`: "7" or "7/3". */
export function divisionLabel(t: HarmonicTone): string {
  return t.skip === 1 ? `${t.divisions}` : `${t.divisions}/${t.skip}`;
}

/**
 * All currently-active tones across an explicit list of (timeframe, scale)
 * pairs.
 *
 * NOTE ON NAMING: Swift declares two static overloads both named
 * `activeTones` — one taking `scales:`, one taking `assignments:`. TypeScript
 * has no argument-based overloading, so the core (assignments) form keeps the
 * exact Swift name and the `scales` convenience wrapper is emitted as
 * `activeTonesForScales`.
 */
export function activeTones(
  date: Date,
  assignments: ToneAssignment[],
  threshold = 0.01,
): HarmonicTone[] {
  const out: HarmonicTone[] = [];
  for (const entry of assignments) {
    const tf = entry.timeframe;
    const sc = entry.scale;
    const factor = Math.pow(2.0, sc);
    const fundamental = (1.0 / cycleDuration(tf)) * factor;
    const deg = degree(tf, date);

    out.push({
      timeframe: tf,
      divisions: 1,
      skip: 1,
      scaling: sc,
      frequency: fundamental,
      amplitude: 1.0,
    });

    for (let div = 3; div <= 8; div++) {
      const amp = shapeOpacity(deg, div);
      if (amp > threshold) {
        out.push({
          timeframe: tf,
          divisions: div,
          skip: 1,
          scaling: sc,
          frequency: fundamental * div,
          amplitude: amp,
        });
      }
    }

    // Star polygons whose winding number has an odd factor carry pitch
    // classes the integer harmonics lack ({7/3} -> 7/6, {8/3} -> 4/3) and
    // sound as distinct winding tones at (n/k)*f with winding-aware
    // activation. k=2 stars are exact octaves of their regular polygons and
    // stay aliased to the integer harmonics above. (THEORY.md 1.4)
    const state = timeframeState(tf, date);
    for (const shape of defaultShapes) {
      if (!(shape.divisions >= 3 && oddPart(shape.skip) > 1)) continue;
      let amp = 0.0;
      for (let vertex = 0; vertex < shape.divisions; vertex++) {
        const a = nodeActivation(shape, vertex, state);
        if (a > amp) amp = a;
      }
      if (amp > threshold) {
        out.push({
          timeframe: tf,
          divisions: shape.divisions,
          skip: shape.skip,
          scaling: sc,
          frequency: (fundamental * shape.divisions) / shape.skip,
          amplitude: amp,
        });
      }
    }
  }
  return out;
}

/**
 * Convenience wrapper (Swift's `activeTones(at:scales:threshold:)`) that
 * produces an assignment for every non-minute timeframe at every supplied
 * scale.
 */
export function activeTonesForScales(
  date: Date,
  scales: number[],
  threshold = 0.01,
): HarmonicTone[] {
  const assignments: ToneAssignment[] = [];
  for (const sc of scales) {
    for (const tf of allCases) {
      if (tf !== "minute") assignments.push({ timeframe: tf, scale: sc });
    }
  }
  return activeTones(date, assignments, threshold);
}
