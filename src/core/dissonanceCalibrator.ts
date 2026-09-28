/**
 * Port of ExochronometerCore/DissonanceCalibrator.swift
 *
 * One-year (or any-duration) headless simulation of the dissonance and
 * entropy meters so we can see the *practical* range. See the Swift source's
 * header comment for the rationale; this is a faithful transliteration.
 */

import { type HarmonicTone, totalTenney, totalEntropy, tenneyMeterMax, entropyMeterMax } from "./dissonanceMath.js";
import { activeTonesForScales, isFundamental } from "./harmonicAnalysis.js";
import { epochInstant } from "./moonPhase.js";

export interface CalibratorStats {
  sampleCount: number;
  sampleIntervalSeconds: number;
  duration: number;

  totalTenneyMax: number;
  totalTenneyP99: number;
  totalTenneyP95: number;
  totalTenneyMedian: number;
  totalTenneyMin: number;
  totalTenneyMean: number;

  totalEntropyMax: number;
  totalEntropyP99: number;
  totalEntropyP95: number;
  totalEntropyMedian: number;
  totalEntropyMin: number;
  totalEntropyMean: number;

  perPairTenneyMax: number;
  perPairTenneyP99: number;
  perPairTenneyP95: number;
  perPairTenneyMedian: number;

  perPairEntropyMax: number;
  perPairEntropyP99: number;
  perPairEntropyP95: number;
  perPairEntropyMedian: number;

  activeToneCountMax: number;
  activeToneCountMean: number;
}

/** Swift's `String(format: "%9.3f", x)` - right-aligned to width 9, 3 decimals. */
function f9_3(x: number): string {
  return x.toFixed(3).padStart(9, " ");
}

/** Swift's `String(format: "%.3f", x)`. */
function f3(x: number): string {
  return x.toFixed(3);
}

/** Swift's `String(format: "%.1f", x)`. */
function f1(x: number): string {
  return x.toFixed(1);
}

/** Swift's `String(format: "%.2f", x)`. */
function f2(x: number): string {
  return x.toFixed(2);
}

/** Swift computed property `Stats.description`. */
export function statsDescription(s: CalibratorStats): string {
  const dayCount = s.duration / 86400.0;
  return [
    "=== DissonanceCalibrator stats ===",
    `  duration:        ${f1(dayCount)} days`,
    `  sample interval: ${Math.trunc(s.sampleIntervalSeconds)} s`,
    `  samples:         ${s.sampleCount}`,
    "",
    `  active tones:    max ${s.activeToneCountMax}, mean ${f2(s.activeToneCountMean)}`,
    "",
    "  -- TENNEY total --",
    `    max     ${f9_3(s.totalTenneyMax)}`,
    `    p99     ${f9_3(s.totalTenneyP99)}`,
    `    p95     ${f9_3(s.totalTenneyP95)}`,
    `    median  ${f9_3(s.totalTenneyMedian)}`,
    `    min     ${f9_3(s.totalTenneyMin)}`,
    `    mean    ${f9_3(s.totalTenneyMean)}`,
    "",
    "  -- ENTROPY total --",
    `    max     ${f9_3(s.totalEntropyMax)}`,
    `    p99     ${f9_3(s.totalEntropyP99)}`,
    `    p95     ${f9_3(s.totalEntropyP95)}`,
    `    median  ${f9_3(s.totalEntropyMedian)}`,
    `    min     ${f9_3(s.totalEntropyMin)}`,
    `    mean    ${f9_3(s.totalEntropyMean)}`,
    "",
    "  -- TENNEY per-pair --",
    `    max     ${f9_3(s.perPairTenneyMax)}`,
    `    p99     ${f9_3(s.perPairTenneyP99)}`,
    `    p95     ${f9_3(s.perPairTenneyP95)}`,
    `    median  ${f9_3(s.perPairTenneyMedian)}`,
    `    (current meter cap: ${f3(tenneyMeterMax)})`,
    "",
    "  -- ENTROPY per-pair --",
    `    max     ${f9_3(s.perPairEntropyMax)}`,
    `    p99     ${f9_3(s.perPairEntropyP99)}`,
    `    p95     ${f9_3(s.perPairEntropyP95)}`,
    `    median  ${f9_3(s.perPairEntropyMedian)}`,
    `    (current meter cap: ${f3(entropyMeterMax)})`,
  ].join("\n");
}

/** Swift's `Int(p * Double(arr.count - 1))` - truncation toward zero. */
function percentile(arr: number[], p: number): number {
  if (arr.length === 0) return 0;
  const idx = Math.min(arr.length - 1, Math.max(0, Math.trunc(p * (arr.length - 1))));
  return arr[idx];
}

function mean(arr: number[]): number {
  if (arr.length === 0) return 0;
  let sum = 0;
  for (const v of arr) sum += v;
  return sum / arr.length;
}

/**
 * Run a synchronous simulation. For 1 year at 60s sampling this is ~525K
 * samples. Use a coarser `sampleIntervalSeconds` (e.g. 300 s = 5 min) for a
 * first pass; the percentile values converge fast.
 */
export function simulate(
  startDate: Date = epochInstant,
  duration: number = 365.25 * 86400,
  sampleIntervalSeconds: number = 60,
  scaling: number = 23,
  includeFundamentals: boolean = false,
): CalibratorStats {
  const nSamples = Math.max(1, Math.trunc(duration / sampleIntervalSeconds));

  const totalTenneys: number[] = [];
  const totalEntropies: number[] = [];
  const perPairTenneys: number[] = [];
  const perPairEntropies: number[] = [];

  let toneCountSum = 0;
  let toneCountMax = 0;

  const startMs = startDate.getTime();

  for (let i = 0; i < nSamples; i++) {
    const t = new Date(startMs + i * sampleIntervalSeconds * 1000);
    const raw: HarmonicTone[] = activeTonesForScales(t, [scaling]);
    const tones = includeFundamentals ? raw : raw.filter((x) => !isFundamental(x));
    toneCountSum += tones.length;
    if (tones.length > toneCountMax) toneCountMax = tones.length;

    const pairCount = Math.max(1, Math.floor((tones.length * (tones.length - 1)) / 2));
    const totalT = totalTenney(tones);
    const totalE = totalEntropy(tones);
    const perPairT = totalT / pairCount;
    const perPairE = totalE / pairCount;

    totalTenneys.push(totalT);
    totalEntropies.push(totalE);
    perPairTenneys.push(perPairT);
    perPairEntropies.push(perPairE);
  }

  totalTenneys.sort((a, b) => a - b);
  totalEntropies.sort((a, b) => a - b);
  perPairTenneys.sort((a, b) => a - b);
  perPairEntropies.sort((a, b) => a - b);

  return {
    sampleCount: nSamples,
    sampleIntervalSeconds,
    duration,

    totalTenneyMax: totalTenneys.length ? totalTenneys[totalTenneys.length - 1] : 0,
    totalTenneyP99: percentile(totalTenneys, 0.99),
    totalTenneyP95: percentile(totalTenneys, 0.95),
    totalTenneyMedian: percentile(totalTenneys, 0.5),
    totalTenneyMin: totalTenneys.length ? totalTenneys[0] : 0,
    totalTenneyMean: mean(totalTenneys),

    totalEntropyMax: totalEntropies.length ? totalEntropies[totalEntropies.length - 1] : 0,
    totalEntropyP99: percentile(totalEntropies, 0.99),
    totalEntropyP95: percentile(totalEntropies, 0.95),
    totalEntropyMedian: percentile(totalEntropies, 0.5),
    totalEntropyMin: totalEntropies.length ? totalEntropies[0] : 0,
    totalEntropyMean: mean(totalEntropies),

    perPairTenneyMax: perPairTenneys.length ? perPairTenneys[perPairTenneys.length - 1] : 0,
    perPairTenneyP99: percentile(perPairTenneys, 0.99),
    perPairTenneyP95: percentile(perPairTenneys, 0.95),
    perPairTenneyMedian: percentile(perPairTenneys, 0.5),

    perPairEntropyMax: perPairEntropies.length ? perPairEntropies[perPairEntropies.length - 1] : 0,
    perPairEntropyP99: percentile(perPairEntropies, 0.99),
    perPairEntropyP95: percentile(perPairEntropies, 0.95),
    perPairEntropyMedian: percentile(perPairEntropies, 0.5),

    activeToneCountMax: toneCountMax,
    activeToneCountMean: toneCountSum / nSamples,
  };
}