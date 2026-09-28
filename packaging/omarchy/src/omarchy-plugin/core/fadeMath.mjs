/**
 * Port of ExochronometerCore/FadeMath.swift
 *
 * The "breathing" logic: a shape fades in as the indicator sweeps past its
 * vertices, and for {n/k} star polygons the active window is the path-visit of
 * the winding traversal rather than bare node proximity.
 */
import { degree, cycleDuration } from "./timeFrame.mjs";
import { epochInstant } from "./moonPhase.mjs";
/** Shortest angular distance between two angles, in [0, 180]. */
export function circularDistance(a, b) {
    let diff = a - b;
    if (diff > 180)
        diff -= 360;
    if (diff < -180)
        diff += 360;
    return Math.abs(diff);
}
/**
 * Cosine-eased opacity centered on `targetDegree`. fadeFraction is the
 * half-window as a fraction of 360 degrees (0.03 = 10.8 degree window).
 */
export function opacity(currentDegree, targetDegree, fadeFraction = 0.03) {
    const fadeWindow = fadeFraction * 360;
    const dist = circularDistance(currentDegree, targetDegree);
    if (dist > fadeWindow)
        return 0;
    return Math.cos((dist / fadeWindow) * (Math.PI / 2));
}
/** Best opacity across all `divisions` evenly-spaced nodes. */
export function shapeOpacity(currentDegree, divisions, fadeFraction = 0.03) {
    let best = 0;
    for (let i = 0; i < divisions; i++) {
        const nodeDeg = (i * 360) / divisions;
        const op = opacity(currentDegree, nodeDeg, fadeFraction);
        if (op > best)
            best = op;
    }
    return best;
}
/** Swift's `Double.rounded()` rounds half away from zero; JS Math.round does not. */
function swiftRound(x) {
    return Math.sign(x) * Math.floor(Math.abs(x) + 0.5);
}
function seconds(a, b) {
    return (a.getTime() - b.getTime()) / 1000;
}
export function timeframeState(timeframe, date, epoch = epochInstant) {
    const cycle = cycleDuration(timeframe);
    const currentDegree = degree(timeframe, date);
    const cycleBoundarySeconds = date.getTime() / 1000 - (currentDegree / 360) * cycle;
    const epochDegree = degree(timeframe, epoch);
    const epochBoundarySeconds = epoch.getTime() / 1000 - (epochDegree / 360) * cycle;
    const cyclesSinceEpoch = (cycleBoundarySeconds - epochBoundarySeconds) / cycle;
    return {
        timeframe,
        date,
        currentDegree,
        cycleBoundarySeconds,
        cycleIndex: swiftRound(cyclesSinceEpoch),
    };
}
/**
 * Activation level for a single vertex of `shape`.
 *
 * The k-cycle is anchored two ways at once: each individual cycle starts at the
 * timeframe's natural boundary (so path-visits coincide with the indicator
 * passing the vertex's geometric angle), while the rotation index within the
 * k-cycle counts from the epoch's nearest boundary, so the rotation
 * alternation is globally consistent.
 */
export function nodeActivation(shape, vertexIndex, state, fadeFraction = 0.03) {
    const n = shape.divisions;
    const k = shape.skip;
    const cycle = cycleDuration(state.timeframe);
    if (!(cycle > 0))
        return 0;
    let pathStep = -1;
    for (let j = 0; j < n; j++) {
        if ((j * k) % n === vertexIndex) {
            pathStep = j;
            break;
        }
    }
    if (pathStep < 0)
        return 0;
    const totalCycle = k * cycle;
    const visitOffset = (pathStep * totalCycle) / n;
    const rotation = ((state.cycleIndex % k) + k) % k;
    const kCycleStartSeconds = state.cycleBoundarySeconds - rotation * cycle;
    const currentOffset = state.date.getTime() / 1000 - kCycleStartSeconds;
    let delta = currentOffset - visitOffset;
    if (delta > totalCycle / 2)
        delta -= totalCycle;
    if (delta < -totalCycle / 2)
        delta += totalCycle;
    const fadeTime = fadeFraction * cycle;
    if (Math.abs(delta) > fadeTime)
        return 0;
    return Math.cos((delta / fadeTime) * (Math.PI / 2));
}
/**
 * Seconds until an overtone exits its current fade window, or null when it is
 * not inside one right now. Fundamentals (divisions == 1) return null since
 * they never fade out.
 */
export function timeUntilOvertoneExit(timeframe, divisions, skip, at, fadeFraction = 0.03) {
    if (!(divisions > 1))
        return null;
    if (skip > 1) {
        return timeUntilWindingExit(timeframe, divisions, skip, at, fadeFraction);
    }
    const currentDeg = degree(timeframe, at);
    const fadeWindow = fadeFraction * 360;
    let bestExitDelta = Number.POSITIVE_INFINITY;
    for (let i = 0; i < divisions; i++) {
        const node = (i * 360) / divisions;
        let delta = node - currentDeg;
        while (delta < -180)
            delta += 360;
        while (delta > 180)
            delta -= 360;
        if (delta >= -fadeWindow && delta < fadeWindow) {
            const exitDelta = delta + fadeWindow;
            if (exitDelta < bestExitDelta)
                bestExitDelta = exitDelta;
        }
    }
    if (!Number.isFinite(bestExitDelta))
        return null;
    const degreesPerSecond = 360 / cycleDuration(timeframe);
    return bestExitDelta / degreesPerSecond;
}
/** Winding-aware exit time: mirrors nodeActivation's visit math. */
function timeUntilWindingExit(timeframe, n, k, at, fadeFraction) {
    const cycle = cycleDuration(timeframe);
    if (!(cycle > 0))
        return null;
    const state = timeframeState(timeframe, at);
    const totalCycle = k * cycle;
    const rotation = ((state.cycleIndex % k) + k) % k;
    const kCycleStartSeconds = state.cycleBoundarySeconds - rotation * cycle;
    const currentOffset = state.date.getTime() / 1000 - kCycleStartSeconds;
    const fadeTime = fadeFraction * cycle;
    let bestExit = Number.POSITIVE_INFINITY;
    for (let pathStep = 0; pathStep < n; pathStep++) {
        const visitOffset = (pathStep * totalCycle) / n;
        let delta = currentOffset - visitOffset;
        if (delta > totalCycle / 2)
            delta -= totalCycle;
        if (delta < -totalCycle / 2)
            delta += totalCycle;
        if (Math.abs(delta) <= fadeTime) {
            const exit = fadeTime - delta;
            if (exit < bestExit)
                bestExit = exit;
        }
    }
    return Number.isFinite(bestExit) ? bestExit : null;
}
