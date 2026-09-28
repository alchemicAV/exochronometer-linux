/**
 * Port of ExochronometerCore/TimeFrame.swift
 *
 * Degrees are ALWAYS UTC (globally synchronized - two devices in different
 * timezones must see the same dot at the same instant). Display labels use the
 * LOCAL calendar, matching Swift's `Calendar.current`.
 */

import { moonDegree, quarterMoonDegree, synodicMonthSeconds, decemberSolstice } from "./moonPhase.js";

export type TimeFrame = "year" | "moon" | "quarterMoon" | "day" | "hour" | "minute";

/** Declaration order matters - it is the order ExoSnapshot emits. */
export const allCases: TimeFrame[] = ["year", "moon", "quarterMoon", "day", "hour", "minute"];

/** Mean tropical year - solstice-to-solstice, the year clock. */
export const tropicalYearDays = 365.24219;
export const tropicalYearSeconds = tropicalYearDays * 24 * 60 * 60;

const SECONDS_PER_DAY = 24 * 60 * 60;

export function cycleDuration(tf: TimeFrame): number {
  switch (tf) {
    case "year":
      return tropicalYearSeconds;
    case "moon":
      return synodicMonthSeconds;
    case "quarterMoon":
      return synodicMonthSeconds / 4;
    case "day":
      return SECONDS_PER_DAY;
    case "hour":
      return 60 * 60;
    case "minute":
      return 60;
  }
}

export function label(tf: TimeFrame): string {
  switch (tf) {
    case "year": return "ONE YEAR";
    case "moon": return "MOON CYCLE";
    case "quarterMoon": return "1/4 MOON";
    case "day": return "ONE DAY";
    case "hour": return "ONE HOUR";
    case "minute": return "ONE MINUTE";
  }
}

export function sublabel(tf: TimeFrame): string {
  switch (tf) {
    case "year": return "~365.24 days";
    case "moon": return "~29.53 days";
    case "quarterMoon": return "~7.38 days";
    case "day": return "24 hours";
    case "hour": return "60 minutes";
    case "minute": return "60 seconds";
  }
}

export function availableInWidget(tf: TimeFrame): boolean {
  return tf !== "minute";
}

// --- degrees (UTC) -----------------------------------------------------------

function yearDegree(at: Date): number {
  const elapsed = (at.getTime() - decemberSolstice.getTime()) / 1000;
  let frac = (elapsed / tropicalYearSeconds) % 1;
  if (frac < 0) frac += 1;
  return frac * 360;
}

function dayDegree(at: Date): number {
  const t = at.getTime() / 1000;
  const startOfDay = Math.floor(t / SECONDS_PER_DAY) * SECONDS_PER_DAY;
  return ((t - startOfDay) / SECONDS_PER_DAY) * 360;
}

function hourDegree(at: Date): number {
  const seconds =
    at.getUTCMinutes() * 60 + at.getUTCSeconds() + at.getUTCMilliseconds() / 1000;
  return (seconds / 3600) * 360;
}

function minuteDegree(at: Date): number {
  const seconds = at.getUTCSeconds() + at.getUTCMilliseconds() / 1000;
  return (seconds / 60) * 360;
}

/** Indicator position in degrees. Always UTC. */
export function degree(tf: TimeFrame, at: Date): number {
  switch (tf) {
    case "year": return yearDegree(at);
    case "moon": return moonDegree(at);
    case "quarterMoon": return quarterMoonDegree(at);
    case "day": return dayDegree(at);
    case "hour": return hourDegree(at);
    case "minute": return minuteDegree(at);
  }
}

// --- labels (local calendar) -------------------------------------------------

const monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const dayNames = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"];

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

/** Display text on the local civil calendar. */
export function traditionalLabel(tf: TimeFrame, at: Date): string {
  switch (tf) {
    case "year":
      return String(at.getFullYear());
    case "moon": {
      const m = Math.max(1, Math.min(12, at.getMonth() + 1));
      return `${monthNames[m - 1]} ${at.getDate()}`;
    }
    case "quarterMoon": {
      const w = at.getDay(); // 0 = Sunday, matching Swift weekday 1 = Sunday
      return dayNames[w];
    }
    case "day":
      return `${pad2(at.getHours())}:${pad2(at.getMinutes())}:${pad2(at.getSeconds())}`;
    case "hour":
      return `${pad2(at.getMinutes())}:${pad2(at.getSeconds())}`;
    case "minute": {
      const tenths = Math.floor(at.getMilliseconds() / 100);
      return `${pad2(at.getSeconds())}.${tenths}`;
    }
  }
}
