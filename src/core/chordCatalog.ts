/**
 * Port of ExochronometerCore/ChordCatalog.swift
 *
 * Recognized chord vocabulary used by the detector and the projector.
 * 5-limit + harmonic 7th; all intervals quoted from JI ratios.
 */

/**
 * One recognized chord shape - its intervals from the root in cents.
 * `intervals[0]` is always 0 (the root itself).
 */
export interface ChordPattern {
  name: string;
  abbreviation: string;
  intervals: number[];
}

/** Swift's `ChordPattern.toneCount` computed property. */
export function toneCount(pattern: ChordPattern): number {
  return pattern.intervals.length;
}

// Swift declares these as `private static let`; they stay module-private here
// for the same reason - only the tables below are the public surface.
const octave = 1200.0;
const p5 = 1200 * Math.log2(3.0 / 2.0);      // 701.96
const p4 = 1200 * Math.log2(4.0 / 3.0);      // 498.04
const m3 = 1200 * Math.log2(6.0 / 5.0);      // 315.64
const M3 = 1200 * Math.log2(5.0 / 4.0);      // 386.31
const M2 = 1200 * Math.log2(9.0 / 8.0);      // 203.91
const m2 = 1200 * Math.log2(16.0 / 15.0);    // 111.73
const M6 = 1200 * Math.log2(5.0 / 3.0);      // 884.36
const m6 = 1200 * Math.log2(8.0 / 5.0);      // 813.69
const M7 = 1200 * Math.log2(15.0 / 8.0);     // 1088.27
const m7 = 1200 * Math.log2(16.0 / 9.0);     // 996.09
const h7 = 1200 * Math.log2(7.0 / 4.0);      // 968.83
const tt = 1200 * Math.log2(45.0 / 32.0);    // 590.22

export const intervals: ChordPattern[] = [
  { name: "Octave", abbreviation: "8va", intervals: [0, octave] },
  { name: "Perfect Fifth", abbreviation: "P5", intervals: [0, p5] },
  { name: "Perfect Fourth", abbreviation: "P4", intervals: [0, p4] },
  { name: "Major Third", abbreviation: "M3", intervals: [0, M3] },
  { name: "Minor Third", abbreviation: "m3", intervals: [0, m3] },
  { name: "Major Second", abbreviation: "M2", intervals: [0, M2] },
  { name: "Major Sixth", abbreviation: "M6", intervals: [0, M6] },
  { name: "Minor Sixth", abbreviation: "m6", intervals: [0, m6] },
  { name: "Major Seventh", abbreviation: "M7", intervals: [0, M7] },
  { name: "Harmonic Seventh", abbreviation: "h7", intervals: [0, h7] },
  { name: "Tritone", abbreviation: "TT", intervals: [0, tt] },
];

export const triads: ChordPattern[] = [
  { name: "Major Triad", abbreviation: "maj", intervals: [0, M3, p5] },
  { name: "Minor Triad", abbreviation: "min", intervals: [0, m3, p5] },
  { name: "Diminished Triad", abbreviation: "dim", intervals: [0, m3, tt] },
  { name: "Augmented Triad", abbreviation: "aug", intervals: [0, M3, m6 + m2] },
  { name: "Suspended 2", abbreviation: "sus2", intervals: [0, M2, p5] },
  { name: "Suspended 4", abbreviation: "sus4", intervals: [0, p4, p5] },
  // "Open Fifth + 8va" (0, P5, octave) was removed 2026-06-10: with
  // only two distinct pitch classes it is an interval in chord
  // costume, and the exact MN:7/3 <-> MN/QM:7 winding fifth left it
  // one drifting day-tone away from firing five times a day.
  // Rule: a chord requires >=3 distinct pitch classes.
];

export const tetrads: ChordPattern[] = [
  { name: "Major 7", abbreviation: "maj7", intervals: [0, M3, p5, M7] },
  { name: "Minor 7", abbreviation: "min7", intervals: [0, m3, p5, m7] },
  { name: "Dominant 7", abbreviation: "dom7", intervals: [0, M3, p5, m7] },
  { name: "Harmonic Dom 7", abbreviation: "h-dom7", intervals: [0, M3, p5, h7] },
  { name: "Half-Diminished 7", abbreviation: "m7\u266D5", intervals: [0, m3, tt, m7] },
  { name: "Diminished 7", abbreviation: "dim7", intervals: [0, m3, tt, M6] },
  { name: "Major 6", abbreviation: "maj6", intervals: [0, M3, p5, M6] },
  { name: "Minor 6", abbreviation: "min6", intervals: [0, m3, p5, M6] },
  { name: "Sus2 + 7", abbreviation: "sus2/7", intervals: [0, M2, p5, m7] },
  { name: "Sus4 + 7", abbreviation: "sus4/7", intervals: [0, p4, p5, m7] },
];

export const all: ChordPattern[] = [...intervals, ...triads, ...tetrads];

/**
 * Triads + tetrads only - convergence uses this so the upcoming-
 * events list isn't flooded by the dozens of cross-timeframe
 * fundamental intervals that are permanently active.
 */
export const chords: ChordPattern[] = [...triads, ...tetrads];
