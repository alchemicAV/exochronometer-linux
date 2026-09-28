// Time-to-degree conversion for all circles.
//
// All phases are UTC-anchored — global synchrony is a core commitment:
// two devices anywhere on Earth show the same dot at the same instant.
// Display text (getTraditionalLabel) stays on the local clock.

import {
  getMoonDegree,
  getQuarterMoonDegree,
  SYNODIC_MONTH_MS,
  QUARTER_MOON_MS,
  PHASE_EPOCH_MS,
  DECEMBER_SOLSTICE_2014_MS,
} from './moonPhase';

// Mean tropical year — the actual solstice-to-solstice year. One clock
// for both the year's phase and (in the native app) its frequency.
export const TROPICAL_YEAR_DAYS = 365.24219;

const DAY_MS = 24 * 60 * 60 * 1000;
const YEAR_MS = TROPICAL_YEAR_DAYS * DAY_MS;
const HOUR_MS = 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

const DAY_NAMES = ['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
const MONTH_NAMES = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

// Year phase 0° = December solstice, advancing by the mean tropical
// year. An astronomical anchor (the same instant for every observer)
// instead of the civil Jan 1 convention; Jan 1 sits ~10° into the cycle.
export const getYearDegree = (nowMs) => {
  const frac = ((((nowMs - DECEMBER_SOLSTICE_2014_MS) / YEAR_MS) % 1) + 1) % 1;
  return frac * 360;
};

// Unix time is UTC-midnight aligned, so the modulo IS the UTC day phase.
export const getDayDegree = (nowMs) => {
  return (((nowMs % DAY_MS) + DAY_MS) % DAY_MS) / DAY_MS * 360;
};

export const getHourDegree = (nowMs) => {
  return (((nowMs % HOUR_MS) + HOUR_MS) % HOUR_MS) / HOUR_MS * 360;
};

export const getMinuteDegree = (nowMs) => {
  return (((nowMs % MINUTE_MS) + MINUTE_MS) % MINUTE_MS) / MINUTE_MS * 360;
};

const pad2 = (n) => String(n).padStart(2, '0');

// Circle configuration
export const CIRCLES = [
  {
    id: 'year',
    label: 'ONE YEAR',
    sublabel: '~365.24 days',
    getDegree: getYearDegree,
    cycleDurationMs: YEAR_MS,
    getTraditionalLabel: (nowMs) => {
      const d = new Date(nowMs);
      return `${d.getFullYear()}`;
    },
  },
  {
    id: 'moon',
    label: 'MOON CYCLE',
    sublabel: '~29.53 days',
    getDegree: getMoonDegree,
    cycleDurationMs: SYNODIC_MONTH_MS,
    getTraditionalLabel: (nowMs) => {
      const d = new Date(nowMs);
      return `${MONTH_NAMES[d.getMonth()]} ${d.getDate()}`;
    },
  },
  {
    id: 'quarterMoon',
    label: '1/4 MOON',
    sublabel: '~7.38 days',
    getDegree: getQuarterMoonDegree,
    cycleDurationMs: QUARTER_MOON_MS,
    getTraditionalLabel: (nowMs) => {
      const d = new Date(nowMs);
      return DAY_NAMES[d.getDay()];
    },
  },
  {
    id: 'day',
    label: 'ONE DAY',
    sublabel: '24 hours',
    getDegree: getDayDegree,
    cycleDurationMs: DAY_MS,
    getTraditionalLabel: (nowMs) => {
      const d = new Date(nowMs);
      return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
    },
  },
  {
    id: 'hour',
    label: 'ONE HOUR',
    sublabel: '60 minutes',
    getDegree: getHourDegree,
    cycleDurationMs: HOUR_MS,
    getTraditionalLabel: (nowMs) => {
      const d = new Date(nowMs);
      return `${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
    },
  },
  {
    id: 'minute',
    label: 'ONE MINUTE',
    sublabel: '60 seconds',
    getDegree: getMinuteDegree,
    cycleDurationMs: MINUTE_MS,
    getTraditionalLabel: (nowMs) => {
      const d = new Date(nowMs);
      const sec = d.getSeconds();
      const tenths = Math.floor(d.getMilliseconds() / 100);
      return `${pad2(sec)}.${tenths}`;
    },
  },
];

// Each circle's phase at the universal epoch — anchors the star-polygon
// winding rotation count (constant per circle, computed once).
for (const circle of CIRCLES) {
  circle.epochDegree = circle.getDegree(PHASE_EPOCH_MS);
}
