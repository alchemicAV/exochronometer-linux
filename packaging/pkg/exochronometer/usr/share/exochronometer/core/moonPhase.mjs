/**
 * Port of ExochronometerCore/MoonPhase.swift (including the PhaseEpoch anchor).
 *
 * All times are UTC instants, so this is timezone-independent.
 */
/** Universal phase anchor: the new moon of 2014-12-22 01:36 UTC. */
export const epochInstant = new Date(Date.UTC(2014, 11, 22, 1, 36, 0));
/** December solstice 2014-12-21 23:03 UTC - year phase 0. */
export const decemberSolstice = new Date(Date.UTC(2014, 11, 21, 23, 3, 0));
/** Same instant as epochInstant so moon math and winding share one anchor. */
export const referenceNewMoon = epochInstant;
export const synodicMonthDays = 29.530588853;
export const synodicMonthSeconds = synodicMonthDays * 24 * 60 * 60;
export const quarterMoonSeconds = synodicMonthSeconds / 4;
function secondsBetween(later, earlier) {
    return (later.getTime() - earlier.getTime()) / 1000;
}
export function phase(at) {
    const m = secondsBetween(at, referenceNewMoon) / synodicMonthSeconds;
    return m - Math.floor(m);
}
export function moonDegree(at) {
    return phase(at) * 360;
}
export function quarterMoonDegree(at) {
    const m = secondsBetween(at, referenceNewMoon) / quarterMoonSeconds;
    return (m - Math.floor(m)) * 360;
}
export function phaseName(forPhase) {
    if (forPhase < 0.0625)
        return "New Moon";
    if (forPhase < 0.1875)
        return "Waxing Crescent";
    if (forPhase < 0.3125)
        return "First Quarter";
    if (forPhase < 0.4375)
        return "Waxing Gibbous";
    if (forPhase < 0.5625)
        return "Full Moon";
    if (forPhase < 0.6875)
        return "Waning Gibbous";
    if (forPhase < 0.8125)
        return "Last Quarter";
    if (forPhase < 0.9375)
        return "Waning Crescent";
    return "New Moon";
}
