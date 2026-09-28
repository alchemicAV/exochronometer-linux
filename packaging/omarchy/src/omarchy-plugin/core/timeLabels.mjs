/**
 * Node date labels drawn OUTSIDE each circle.
 *
 * Port of the pure (non-drawing) half of Exochronometer/TimeCircleView.swift -
 * `cycleStartDate`, `dateForNode` and `formatter`, copied from the iOS view
 * rather than the Core framework, since that is where the original keeps them.
 *
 * The date math is anchored on UTC (to match the indicator, which is UTC), while
 * the rendered label uses the LOCAL calendar - so the string shown at a node is
 * the wall-clock time the user would read there.
 *
 * Validated against reference/vectors-nodelabels-*.json, emitted by
 * reference/vec-nodelabels/ from the verbatim Swift originals.
 */
import { cycleDuration, tropicalYearSeconds } from "./timeFrame.mjs";
import { decemberSolstice, referenceNewMoon, synodicMonthSeconds, quarterMoonSeconds, } from "./moonPhase.mjs";
import { defaultShapes } from "./geometry.mjs";
import { shapeOpacity } from "./fadeMath.mjs";
const SECONDS_PER_DAY = 24 * 60 * 60;
/** Date format string per timeframe, mirroring `formatter(for:)`. */
export function nodeLabelPattern(tf) {
    switch (tf) {
        case "year":
        case "moon":
            return "M/d";
        case "quarterMoon":
            return "M/d HH:mm";
        case "day":
        case "hour":
            return "HH:mm";
        case "minute":
            return "mm:ss";
    }
}
function pad2(n) {
    return String(n).padStart(2, "0");
}
/** Render a node's instant with that timeframe's format, on the LOCAL calendar. */
export function nodeLabel(tf, at) {
    const M = at.getMonth() + 1;
    const D = at.getDate();
    const HH = pad2(at.getHours());
    const mm = pad2(at.getMinutes());
    const ss = pad2(at.getSeconds());
    switch (tf) {
        case "year":
        case "moon":
            return `${M}/${D}`;
        case "quarterMoon":
            return `${M}/${D} ${HH}:${mm}`;
        case "day":
        case "hour":
            return `${HH}:${mm}`;
        case "minute":
            return `${mm}:${ss}`;
    }
}
/**
 * Start of the cycle currently containing `now`, in epoch milliseconds.
 *
 * Calendar-bound timeframes use their UTC boundary (matching
 * `TimeFrame.utcCalendar`); the year is solstice-anchored and the moon pair are
 * anchored on the reference new moon.
 */
export function cycleStartMs(tf, now) {
    const t = now.getTime() / 1000; // seconds, keeps Double precision
    switch (tf) {
        case "year": {
            const base = decemberSolstice.getTime() / 1000;
            const completed = Math.floor((t - base) / tropicalYearSeconds);
            return (base + completed * tropicalYearSeconds) * 1000;
        }
        case "day":
            return Math.floor(t / SECONDS_PER_DAY) * SECONDS_PER_DAY * 1000;
        case "hour":
            return Math.floor(t / 3600) * 3600 * 1000;
        case "minute":
            return Math.floor(t / 60) * 60 * 1000;
        case "moon": {
            const base = referenceNewMoon.getTime() / 1000;
            const completed = Math.floor((t - base) / synodicMonthSeconds);
            return (base + completed * synodicMonthSeconds) * 1000;
        }
        case "quarterMoon": {
            const base = referenceNewMoon.getTime() / 1000;
            const completed = Math.floor((t - base) / quarterMoonSeconds);
            return (base + completed * quarterMoonSeconds) * 1000;
        }
    }
}
/** The instant a given node degree was (or will be) passed, in epoch milliseconds. */
export function nodeDateMs(degree, tf, now) {
    const offset = (degree / 360) * cycleDuration(tf) * 1000;
    return cycleStartMs(tf, now) + offset;
}
/**
 * Distinct node angles currently lit across every default shape, with the best
 * opacity at each - the `nodesByAngle` table the view draws labels for.
 * Nodes below the 0.05 cut are omitted, as in the original.
 */
export function activeNodeDegrees(currentDegree, fadeFraction = 0.03) {
    const byAngle = new Map();
    for (const shape of defaultShapes) {
        const op = shapeOpacity(currentDegree, shape.divisions, fadeFraction);
        if (op < 0.05)
            continue;
        for (let i = 0; i < shape.divisions; i++) {
            const angle = (i * 360) / shape.divisions;
            const key = Math.round(angle); // Swift: Int(angle.rounded())
            byAngle.set(key, Math.max(byAngle.get(key) ?? 0, op));
        }
    }
    return [...byAngle.entries()].map(([degree, opacity]) => ({ degree, opacity }));
}
