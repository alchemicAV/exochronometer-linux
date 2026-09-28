// Moon phase calculation using synodic month

// Universal phase anchor: the "meeting of sun and moon" of December 2014.
// New moon at 2014-12-22 01:36 UTC, ~2.5 h after the December solstice
// (2014-12-21 23:03 UTC) — a Metonic-cycle alignment (1995 → 2014 → 2033).
// Moon phase 0° and the solstice-anchored year phase 0° coincide to
// within 2.5 hours. Matches PhaseEpoch in the iOS/macOS app.
export const PHASE_EPOCH_MS = Date.UTC(2014, 11, 22, 1, 36, 0);
export const DECEMBER_SOLSTICE_2014_MS = Date.UTC(2014, 11, 21, 23, 3, 0);

const REFERENCE_NEW_MOON_UTC = PHASE_EPOCH_MS;

// Mean synodic month (Meeus, Astronomical Algorithms)
export const SYNODIC_MONTH_DAYS = 29.530588853;
export const SYNODIC_MONTH_MS = SYNODIC_MONTH_DAYS * 24 * 60 * 60 * 1000;
export const QUARTER_MOON_MS = SYNODIC_MONTH_MS / 4;

// Get moon phase as 0-1 (0 = new moon, 0.5 = full moon)
export const getMoonPhase = (nowMs) => {
  const elapsed = nowMs - REFERENCE_NEW_MOON_UTC;
  return (((elapsed / SYNODIC_MONTH_MS) % 1) + 1) % 1;
};

// Get moon degree (0-360)
export const getMoonDegree = (nowMs) => {
  return getMoonPhase(nowMs) * 360;
};

// Get quarter moon degree (0-360, cycles 4x per synodic month)
export const getQuarterMoonDegree = (nowMs) => {
  const elapsed = nowMs - REFERENCE_NEW_MOON_UTC;
  const phase = (((elapsed / QUARTER_MOON_MS) % 1) + 1) % 1;
  return phase * 360;
};

// Phase name for display
export const getMoonPhaseName = (phase) => {
  if (phase < 0.0625) return 'New Moon';
  if (phase < 0.1875) return 'Waxing Crescent';
  if (phase < 0.3125) return 'First Quarter';
  if (phase < 0.4375) return 'Waxing Gibbous';
  if (phase < 0.5625) return 'Full Moon';
  if (phase < 0.6875) return 'Waning Gibbous';
  if (phase < 0.8125) return 'Last Quarter';
  if (phase < 0.9375) return 'Waning Crescent';
  return 'New Moon';
};
