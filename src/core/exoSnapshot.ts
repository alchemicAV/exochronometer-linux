/**
 * Port of ExochronometerCore/ExoSnapshot.swift
 *
 * JSON payload capturing the full universal state at a moment in time. v1
 * captures everything that is a pure function of `timestamp`; v2 (2026-06)
 * re-anchored the year phase to the December solstice.
 */

import { allCases, cycleDuration, degree, traditionalLabel, type TimeFrame } from "./timeFrame.js";
import { moonDegree, phase, phaseName, quarterMoonDegree } from "./moonPhase.js";
import { defaultShapes } from "./geometry.js";
import { closestNote } from "./justIntonation.js";

export const currentVersion = 2;

export interface TimeframeSnapshot {
  timeframe: TimeFrame;
  degree: number;
  cycleDurationSeconds: number;
  traditionalLabel: string;
}

export interface MoonSnapshot {
  phase: number;
  phaseName: string;
  moonDegree: number;
  quarterMoonDegree: number;
}

export interface GeometryHarmonicSnapshot {
  timeframe: TimeFrame;
  divisions: number;
  skip: number;
  periodSeconds: number;
  frequencyHz: number;
  jiNoteName: string;
  centsDeltaFromA432: number;
}

export interface ExoSnapshot {
  version: number;
  timestamp: Date;
  timezoneIdentifier: string;
  note: string;
  timeframes: TimeframeSnapshot[];
  moon: MoonSnapshot;
  harmonics: GeometryHarmonicSnapshot[];
}

function currentTimezoneIdentifier(): string {
  const offMin = -new Date().getTimezoneOffset(); // minutes east of UTC
  let name = "";
  try {
    name = Intl.DateTimeFormat().resolvedOptions().timeZone || "";
  } catch (e) {
    // NOTE: the binding must be explicit. QML's V4 JS engine rejects the
    // ES2019 optional catch binding form (`catch {`) at parse time, which
    // fails the whole module import rather than just this call.
    void e;
  }
  // QML's V4 engine has no Intl timezone database and reports "UTC" for every
  // zone, which would be a lie on a machine running UTC-4. Cross-check the
  // actual offset and fall back to a numeric label instead.
  if (!name || (name === "UTC" && offMin !== 0)) {
    if (offMin === 0) return "UTC";
    const sign = offMin < 0 ? "-" : "+";
    const abs = Math.abs(offMin);
    const hh = String(Math.floor(abs / 60)).padStart(2, "0");
    const mm = String(abs % 60).padStart(2, "0");
    return `UTC${sign}${hh}:${mm}`;
  }
  return name;
}

/**
 * Capture the moment. Pure - derives everything from `date` plus the epoch
 * constants, exactly like the Swift original.
 */
export function capture(at: Date = new Date(), note = ""): ExoSnapshot {
  const timeframes: TimeframeSnapshot[] = allCases.map((tf) => ({
    timeframe: tf,
    degree: degree(tf, at),
    cycleDurationSeconds: cycleDuration(tf),
    traditionalLabel: traditionalLabel(tf, at),
  }));

  const ph = phase(at);
  const moon: MoonSnapshot = {
    phase: ph,
    phaseName: phaseName(ph),
    moonDegree: moonDegree(at),
    quarterMoonDegree: quarterMoonDegree(at),
  };

  const harmonics: GeometryHarmonicSnapshot[] = [];
  harmonics.length = 0;
  for (const tf of allCases) {
    for (const shape of defaultShapes) {
      const period = (cycleDuration(tf) * shape.skip) / shape.divisions;
      const frequency = period > 0 ? 1 / period : 0;
      const ji = closestNote(frequency);
      harmonics.push({
        timeframe: tf,
        divisions: shape.divisions,
        skip: shape.skip,
        periodSeconds: period,
        frequencyHz: frequency,
        jiNoteName: ji.noteName,
        centsDeltaFromA432: ji.centsDelta,
      });
    }
  }

  return {
    version: currentVersion,
    timestamp: at,
    timezoneIdentifier: currentTimezoneIdentifier(),
    note,
    timeframes,
    moon,
    harmonics,
  };
}
