/**
 * Port of ExochronometerCore/ChordDetector.swift
 *
 * Finds chord patterns whose constituent tones are simultaneously active, and
 * collapses octave-equivalent duplicates (HR:4 vs HR:8) by pitch class.
 */

import { type ChordPattern, toneCount, all as allPatterns } from "./chordCatalog.js";
import { type HarmonicTone, toneId } from "./harmonicAnalysis.js";
import { oddPart } from "./geometry.js";

/** One detected chord - which tones form it, which pattern they match, and how close the match is. */
export interface ChordMatch {
  pattern: ChordPattern;
  tones: HarmonicTone[];
  fitCents: number;
}

/** Swift computed property `ChordMatch.id`. */
export function chordMatchId(m: ChordMatch): string {
  return `${m.pattern.abbreviation}|` + m.tones.map(toneId).join(",");
}

/**
 * Per-interval tolerance - a chord "matches" if every required interval lies
 * within +/-tolerance of its ideal cents value. +/-25c is the perceptual
 * "noticeably stretched but still recognisable as that chord" threshold.
 */
export const tolerance = 25;

/**
 * Octave-equivalence-aware identity for a chord match. HR:4 and HR:8 share the
 * same odd-part (1), so any chord pattern matched twice with just these swapped
 * collapses to a single signature. A winding tone's pitch class is
 * oddPart(divisions)/oddPart(skip), so {7/3} ("7:3") stays distinct from the
 * integer 7th harmonic ("7:1").
 */
export function pitchClassSignature(tones: HarmonicTone[], pattern: ChordPattern): string {
  const parts = tones
    .map((t) => `${t.timeframe}.${oddPart(t.divisions)}:${oddPart(t.skip)}`)
    .sort();
  return `${pattern.abbreviation}|${parts.join("+")}`;
}

/** Swift's `forEachCombination` - index-ordered combinations, emitted in lexicographic index order. */
export function forEachCombination<T>(items: T[], k: number, body: (combo: T[]) => void): void {
  if (!(k > 0) || k > items.length) return;
  const indices: number[] = Array.from({ length: k }, (_, i) => i);
  const n = items.length;
  for (;;) {
    body(indices.map((i) => items[i]));
    let i = k - 1;
    while (i >= 0 && indices[i] === i + n - k) i -= 1;
    if (i < 0) return;
    indices[i] += 1;
    for (let j = i + 1; j < k; j++) indices[j] = indices[j - 1] + 1;
  }
}

/**
 * Find all chord patterns whose constituent tones are currently active above
 * `amplitudeThreshold`. Sorted by fit (lowest cents error first). When the same
 * tone subset matches multiple patterns (e.g. the same triad sitting between
 * major and minor), only the closest fit is kept.
 */
export function detect(
  tones: HarmonicTone[],
  amplitudeThreshold = 0.3,
  patterns: ChordPattern[] = allPatterns,
  toleranceArg: number = tolerance,
): ChordMatch[] {
  const active = tones.filter((t) => t.amplitude >= amplitudeThreshold && t.frequency > 0);
  if (active.length < 2) return [];

  const bestPerSubset = new Map<string, ChordMatch>();

  for (const pattern of patterns) {
    const n = toneCount(pattern);
    if (active.length < n) continue;
    forEachCombination(active, n, (combo) => {
      const m = match(combo, pattern, toleranceArg);
      if (m === null) return;
      const key = [...combo]
        .sort((a, b) => a.frequency - b.frequency)
        .map(toneId)
        .join(",");
      const existing = bestPerSubset.get(key);
      if (existing !== undefined && existing.fitCents <= m.fitCents) return;
      bestPerSubset.set(key, m);
    });
  }

  // Second pass: dedupe by pitch-class signature so HR:4-vs-HR:8 duplicates
  // collapse. Prefer the match with the *higher* total division (more
  // high-octave tones - these have superset firing windows, so they catch every
  // event a lower-octave equivalent would). Tie-break by fit.
  const bestPerSignature = new Map<string, ChordMatch>();
  for (const m of bestPerSubset.values()) {
    const sig = pitchClassSignature(m.tones, m.pattern);
    const existing = bestPerSignature.get(sig);
    if (existing !== undefined) {
      const existingDivSum = existing.tones.reduce((acc, t) => acc + t.divisions, 0);
      const matchDivSum = m.tones.reduce((acc, t) => acc + t.divisions, 0);
      if (existingDivSum > matchDivSum) continue;
      if (existingDivSum === matchDivSum && existing.fitCents <= m.fitCents) continue;
    }
    bestPerSignature.set(sig, m);
  }
  return [...bestPerSignature.values()].sort((a, b) => a.fitCents - b.fitCents);
}

/**
 * Match a specific tone subset against a specific pattern. Treats the
 * lowest-frequency tone (in pitch-class) as the root and computes intervals
 * from it to each higher tone.
 */
export function match(
  tones: HarmonicTone[],
  pattern: ChordPattern,
  toleranceArg: number = tolerance,
): ChordMatch | null {
  if (tones.length !== toneCount(pattern)) return null;
  const sorted = [...tones].sort((a, b) => a.frequency - b.frequency);
  const root = sorted[0].frequency;

  const actualIntervals: number[] = sorted.map((t) =>
    t.frequency === root ? 0 : 1200 * Math.log2(t.frequency / root),
  );
  // Sort both interval lists so we don't depend on input ordering.
  const actualSorted = [...actualIntervals].sort((a, b) => a - b);
  const patternSorted = [...pattern.intervals].sort((a, b) => a - b);

  let totalError = 0;
  for (let i = 0; i < patternSorted.length; i++) {
    const actual = octaveReduce(actualSorted[i]);
    const expected = octaveReduce(patternSorted[i]);
    const dist = circularCentsDistance(actual, expected);
    if (dist > toleranceArg) return null;
    totalError += dist;
  }
  return { pattern, tones: sorted, fitCents: totalError };
}

function octaveReduce(cents: number): number {
  const m = cents % 1200;
  return m < 0 ? m + 1200 : m;
}

function circularCentsDistance(a: number, b: number): number {
  const raw = Math.abs(a - b);
  return Math.min(raw, 1200 - raw);
}
