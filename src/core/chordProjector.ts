/**
 * Port of ExochronometerCore/ChordProjector.swift
 *
 * Forward-search for chord events: windows in the future during which every
 * tone of a recognized chord pattern is simultaneously active above threshold.
 */

import { type ChordPattern, all as allPatterns } from "./chordCatalog.js";
import {
  type ChordMatch,
  detect,
  match as detectorMatch,
  pitchClassSignature,
  tolerance as detectorTolerance,
  forEachCombination,
} from "./chordDetector.js";
import { type HarmonicTone, activeTonesForScales } from "./harmonicAnalysis.js";
import { type TimeFrame, allCases, cycleDuration, degree } from "./timeFrame.js";
import { type Shape, defaultShapes, oddPart } from "./geometry.js";
import { nodeActivation, shapeOpacity, timeframeState } from "./fadeMath.js";

/** One predicted chord event - a future window during which all tones of a recognized chord pattern are active. */
export interface ChordEvent {
  pattern: ChordPattern;
  toneSignature: ToneSignature[];
  startTime: Date;
  peakTime: Date;
  endTime: Date;
  fitCents: number;
  peakAmplitudeProduct: number;
}

/** Swift's nested `ChordEvent.ToneSignature`. */
export interface ToneSignature {
  timeframe: TimeFrame;
  divisions: number;
  skip: number;
}

/** Swift computed property `ToneSignature.divisionLabel`: "7" for integer harmonics, "7/3" for winding tones. */
export function toneSignatureLabel(sig: ToneSignature): string {
  return sig.skip === 1 ? `${sig.divisions}` : `${sig.divisions}/${sig.skip}`;
}

/** Swift computed property `ChordEvent.id`. */
export function chordEventId(e: ChordEvent): string {
  const sig = e.toneSignature
    .map((s) => `${s.timeframe}.${toneSignatureLabel(s)}`)
    .join("+");
  return `${e.pattern.abbreviation}|${sig}|${Math.trunc(e.startTime.getTime() / 1000)}`;
}

/** Swift's internal `ChordProjector.CandidateChord`. */
export interface CandidateChord {
  pattern: ChordPattern;
  tones: HarmonicTone[];
  fitCents: number;
}

// --- amplitude lookup table --------------------------------------------------

/**
 * Pre-computes amplitude for every (timeframe, divisions/skip) at one instant so
 * the projector can do constant-time lookups instead of recomputing
 * shapeOpacity per candidate-tone per sample.
 */
function buildToneAmplitudeTable(at: Date, scaling: number): Map<string, number> {
  void scaling;
  const amps = new Map<string, number>();
  for (const tf of allCases) {
    if (tf === "minute") continue;
    const deg = degree(tf, at);
    amps.set(`${tf}|1/1`, 1.0);
    for (let div = 3; div <= 8; div++) {
      amps.set(`${tf}|${div}/1`, shapeOpacity(deg, div));
    }
    const state = timeframeState(tf, at);
    for (const shape of defaultShapes) {
      if (!(oddPart(shape.skip) > 1)) continue;
      let amp = 0.0;
      for (let vertex = 0; vertex < shape.divisions; vertex++) {
        const a = nodeActivation(shape, vertex, state);
        if (a > amp) amp = a;
      }
      amps.set(`${tf}|${shape.divisions}/${shape.skip}`, amp);
    }
  }
  return amps;
}

function amplitudeOf(table: Map<string, number>, tone: HarmonicTone): number {
  return table.get(`${tone.timeframe}|${tone.divisions}/${tone.skip}`) ?? 0;
}

// --- forward search ----------------------------------------------------------

/**
 * Forward-search for upcoming chord events.
 *
 * - `from`              Start of the search window.
 * - `lookahead`         How far forward to look. 1 month is the sweet spot.
 * - `amplitudeThreshold` Each constituent tone must be at or above this
 *                        amplitude for the chord to count as "active."
 * - `sampleInterval`    How finely to sample the timeline.
 * - `patterns`          Which chord vocabulary to search.
 * - `maxResults`        Hard cap on returned events.
 */
/**
 * Resumable scan state for `upcoming`.
 *
 * The 30-day projection costs ~0.16ms per sample in QML's V4 engine, so the
 * full 43,200-sample scan takes ~7s - which would freeze the UI thread solid.
 * The scan is therefore exposed as begin/step/finish so a caller can advance it
 * in time-sliced chunks across event-loop turns. `upcoming` below is the
 * original one-shot call, unchanged, built from these three.
 */
export interface UpcomingScan {
  candidatesRef: Candidate[];
  openEvents: Map<Candidate, OpenEvent>;
  events: ChordEvent[];
  stillRunningFromStart: Set<Candidate>;
  i: number;
  nSamples: number;
  fromMs: number;
  sampleInterval: number;
  scaling: number;
  amplitudeThreshold: number;
  maxResults: number;
  done: boolean;
}

export function beginUpcoming(
  from: Date,
  lookahead: number,
  amplitudeThreshold = 0.3,
  sampleInterval = 60,
  scaling = 23,
  includeFundamentals = true,
  crossTimeframeOnly = false,
  excludeHourly = false,
  excludeCurrentlyActive = true,
  patterns: ChordPattern[] = allPatterns,
  maxResults = 50,
): UpcomingScan {
  const candidates = candidateChords(
    scaling,
    patterns,
    detectorTolerance,
    includeFundamentals,
    crossTimeframeOnly,
    excludeHourly,
  );

  const scan: UpcomingScan = {
    candidatesRef: candidates.map((inner) => ({ inner })),
    openEvents: new Map<Candidate, OpenEvent>(),
    events: [],
    stillRunningFromStart: new Set<Candidate>(),
    i: 0,
    nSamples: Math.trunc(lookahead / sampleInterval),
    fromMs: from.getTime(),
    sampleInterval: sampleInterval,
    scaling: scaling,
    amplitudeThreshold: amplitudeThreshold,
    maxResults: maxResults,
    done: false,
  };

  if (scan.candidatesRef.length === 0 || !(scan.nSamples > 0)) {
    scan.done = true;
    return scan;
  }

  // Seed pass at t = from: any candidate already active at t=0 is "in progress"
  // - we don't generate an upcoming event for it until it deactivates and
  // reactivates. (Those chords are shown by the convergence widget's NOW
  // section instead.)
  if (excludeCurrentlyActive) {
    const initialAmps = buildToneAmplitudeTable(from, scaling);
    for (const cand of scan.candidatesRef) {
      const allActive = cand.inner.tones.every(
        (tone) => amplitudeOf(initialAmps, tone) >= amplitudeThreshold,
      );
      if (allActive) scan.stillRunningFromStart.add(cand);
    }
  }

  return scan;
}

/**
 * Advance the scan by at most `budgetMs` of wall-clock work. Returns true when
 * the scan has finished (or hit its result cap).
 */
export function stepUpcoming(scan: UpcomingScan, budgetMs = 8): boolean {
  if (scan.done) return true;

  const t0 = Date.now();
  while (scan.i <= scan.nSamples) {
    const t = new Date(scan.fromMs + scan.i * scan.sampleInterval * 1000);
    const amps = buildToneAmplitudeTable(t, scan.scaling);
    for (const cand of scan.candidatesRef) {
      const ampProduct = cand.inner.tones.reduce(
        (acc, tone) => acc * amplitudeOf(amps, tone),
        1.0,
      );
      const allActive = cand.inner.tones.every(
        (tone) => amplitudeOf(amps, tone) >= scan.amplitudeThreshold,
      );

      if (allActive) {
        // If this candidate was active at t=0 and has never gone inactive
        // since, skip - it's not a *new* event.
        if (scan.stillRunningFromStart.has(cand)) continue;

        const open = scan.openEvents.get(cand);
        if (open !== undefined) {
          open.endTime = t;
          if (ampProduct > open.peakAmplitudeProduct) {
            open.peakAmplitudeProduct = ampProduct;
            open.peakTime = t;
          }
        } else {
          scan.openEvents.set(cand, {
            startTime: t,
            peakTime: t,
            endTime: t,
            peakAmplitudeProduct: ampProduct,
          });
        }
      } else {
        // First time this candidate goes inactive - it's now eligible for
        // future activations to count as new events.
        if (scan.stillRunningFromStart.delete(cand)) continue;
        const open = scan.openEvents.get(cand);
        if (open !== undefined) {
          scan.openEvents.delete(cand);
          scan.events.push({
            pattern: cand.inner.pattern,
            toneSignature: cand.inner.tones.map((tone) => ({
              timeframe: tone.timeframe,
              divisions: tone.divisions,
              skip: tone.skip,
            })),
            startTime: open.startTime,
            peakTime: open.peakTime,
            endTime: open.endTime,
            fitCents: cand.inner.fitCents,
            peakAmplitudeProduct: open.peakAmplitudeProduct,
          });
        }
      }
    }

    scan.i++;
    if (scan.events.length >= scan.maxResults * 2) break;
    if (Date.now() - t0 >= budgetMs) break;
  }

  if (scan.i > scan.nSamples || scan.events.length >= scan.maxResults * 2) {
    scan.done = true;
  }
  return scan.done;
}

export function finishUpcoming(scan: UpcomingScan): ChordEvent[] {
  return scan.events
    .sort((a, b) => a.startTime.getTime() - b.startTime.getTime())
    .slice(0, scan.maxResults);
}

export function upcoming(
  from: Date,
  lookahead: number,
  amplitudeThreshold = 0.3,
  sampleInterval = 60,
  scaling = 23,
  includeFundamentals = true,
  crossTimeframeOnly = false,
  excludeHourly = false,
  excludeCurrentlyActive = true,
  patterns: ChordPattern[] = allPatterns,
  maxResults = 50,
): ChordEvent[] {
  const scan = beginUpcoming(
    from, lookahead, amplitudeThreshold, sampleInterval, scaling,
    includeFundamentals, crossTimeframeOnly, excludeHourly,
    excludeCurrentlyActive, patterns, maxResults,
  );
  while (!stepUpcoming(scan, Infinity)) { /* run to completion */ }
  return finishUpcoming(scan);
}

/** Detect chord patterns currently active at `date`. */
export function current(
  date: Date,
  amplitudeThreshold = 0.3,
  scaling = 23,
  includeFundamentals = true,
  crossTimeframeOnly = false,
  excludeHourly = false,
  patterns: ChordPattern[] = allPatterns,
): ChordMatch[] {
  let tones = activeTonesForScales(date, [scaling]);
  if (!includeFundamentals) {
    tones = tones.filter((t) => t.divisions !== 1);
  }
  if (excludeHourly) {
    tones = tones.filter((t) => t.timeframe !== "hour");
  }
  // Restrict to canonical-highest-per-PC divisions so we don't detect HR:4 and
  // HR:8 as two separate chord events. Winding tones ({7/3}, {8/3}) are unique
  // pitch classes and always pass.
  const pc1Canonical = includeFundamentals ? 1 : 8;
  const canonicalDivisions = new Set<number>([pc1Canonical, 6, 5, 7]);
  tones = tones.filter((t) => !(t.skip === 1 && !canonicalDivisions.has(t.divisions)));
  const matches = detect(tones, amplitudeThreshold, patterns);
  if (crossTimeframeOnly) {
    // Drop matches whose tones all share one timeframe - those fire constantly
    // when a single cycle has dense overtones and dilute the meaningful
    // cross-timeframe convergences.
    return matches.filter((m) => new Set(m.tones.map((t) => t.timeframe)).size > 1);
  }
  return matches;
}

// --- candidate enumeration ---------------------------------------------------

/** Swift's private struct `CandidateKey` - the cache key for a candidate set. */
export interface CandidateKey {
  scaling: number;
  patternIDs: string[];
  tolerance: number;
  includeFundamentals: boolean;
  crossTimeframeOnly: boolean;
  excludeHourly: boolean;
}

function candidateKeyString(key: CandidateKey): string {
  return [
    key.scaling,
    key.patternIDs.join(","),
    key.tolerance,
    key.includeFundamentals,
    key.crossTimeframeOnly,
    key.excludeHourly,
  ].join("|");
}

const candidateCache = new Map<string, CandidateChord[]>();

/**
 * Enumerate every (toneSubset, chordPattern) combination from the finite
 * universe (5 timeframes x canonical integer divisions plus the {7/3} and {8/3}
 * winding tones) that matches a pattern within tolerance. Computed once per
 * (scaling, patterns) combo and cached.
 */
export function candidateChords(
  scaling = 23,
  patterns: ChordPattern[] = allPatterns,
  tolerance: number = detectorTolerance,
  includeFundamentals = true,
  crossTimeframeOnly = false,
  excludeHourly = false,
): CandidateChord[] {
  const key: CandidateKey = {
    scaling,
    patternIDs: patterns.map((p) => p.abbreviation),
    tolerance,
    includeFundamentals,
    crossTimeframeOnly,
    excludeHourly,
  };
  const cacheKey = candidateKeyString(key);
  const cached = candidateCache.get(cacheKey);
  if (cached !== undefined) return cached;

  const universe = makeUniverse(scaling, includeFundamentals, excludeHourly);
  const found: CandidateChord[] = [];
  const seenSignatures = new Set<string>();

  for (const pattern of patterns) {
    const n = pattern.intervals.length;
    if (universe.length < n) continue;
    forEachCombination(universe, n, (combo) => {
      if (crossTimeframeOnly) {
        const seenTFs = new Set<TimeFrame>();
        for (const tone of combo) seenTFs.add(tone.timeframe);
        if (seenTFs.size < 2) return;
      }
      const m = detectorMatch(combo, pattern, tolerance);
      if (m !== null) {
        const signature = pitchClassSignature(m.tones, pattern);
        if (seenSignatures.has(signature)) return;
        seenSignatures.add(signature);
        found.push({ pattern, tones: m.tones, fitCents: m.fitCents });
      }
    });
  }
  candidateCache.set(cacheKey, found);
  return found;
}

function makeUniverse(
  scaling: number,
  includeFundamentals = true,
  excludeHourly = false,
): HarmonicTone[] {
  const tones: HarmonicTone[] = [];
  // One canonical representative per (timeframe, pitch class), using the
  // *highest* division available. The higher-octave overtones fire at every
  // moment their lower-octave equivalents do (since their vertex sets are
  // supersets), so they catch every chord event a lower-octave canonical would,
  // plus additional ones.
  //
  // PC1 special case: if fundamentals are included we use div=1 (always at
  // amp=1.0) because it's even more permissive than div=8. Otherwise we fall
  // back to div=8.
  const pc1Canonical = includeFundamentals ? 1 : 8;
  const baseDivisions = [pc1Canonical, 6, 5, 7];

  for (const tf of allCases) {
    if (tf === "minute") continue;
    if (excludeHourly && tf === "hour") continue;
    const fundamental = (1.0 / cycleDuration(tf)) * Math.pow(2.0, scaling);
    for (const div of baseDivisions) {
      tones.push({
        timeframe: tf,
        divisions: div,
        skip: 1,
        scaling,
        frequency: fundamental * div,
        amplitude: 1.0,
      });
    }
    // Winding tones - distinct pitch classes (7/6 and 4/3) with no
    // integer-harmonic equivalent.
    for (const shape of defaultShapes) {
      if (!(oddPart(shape.skip) > 1)) continue;
      tones.push(toneFromShape(tf, shape, fundamental, scaling));
    }
  }
  return tones;
}

function toneFromShape(
  tf: TimeFrame,
  shape: Shape,
  fundamental: number,
  scaling: number,
): HarmonicTone {
  return {
    timeframe: tf,
    divisions: shape.divisions,
    skip: shape.skip,
    scaling,
    frequency: (fundamental * shape.divisions) / shape.skip,
    amplitude: 1.0,
  };
}

// --- internals ---------------------------------------------------------------

interface OpenEvent {
  startTime: Date;
  peakTime: Date;
  endTime: Date;
  peakAmplitudeProduct: number;
}

/** Swift's private `Candidate` class - an identity wrapper around a CandidateChord. */
interface Candidate {
  inner: CandidateChord;
}