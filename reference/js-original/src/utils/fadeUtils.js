// Geometry fade/opacity envelope

import { PHASE_EPOCH_MS } from './moonPhase';

// Circular distance between two angles (0-360), returned as 0-180
const circularDistance = (a, b) => {
  let diff = a - b;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return Math.abs(diff);
};

// Cosine-eased opacity: smooth breathing effect
export const computeGeometryOpacity = (currentDegree, targetDegree, fadeFraction = 0.03) => {
  const fadeWindow = fadeFraction * 360; // 10.8 degrees
  const dist = circularDistance(currentDegree, targetDegree);
  if (dist > fadeWindow) return 0;
  return Math.cos((dist / fadeWindow) * (Math.PI / 2));
};

// Winding-aware opacity for a star polygon {n/k}: the shape lights only
// when the dot is passing a vertex its winding path visits on the
// CURRENT rotation of the k-rotation cycle (anchored at the universal
// epoch) — 1-in-k vertex passes, not every pass. Matches the native
// app's FadeMath.nodeActivation.
export const computeWindingOpacity = (
  nowMs,
  currentDegree,
  cycleDurationMs,
  epochDegree,
  divisions,
  skip,
  fadeFraction = 0.03
) => {
  const totalCycleMs = skip * cycleDurationMs;
  const cycleBoundaryMs = nowMs - (currentDegree / 360) * cycleDurationMs;
  const epochBoundaryMs = PHASE_EPOCH_MS - (epochDegree / 360) * cycleDurationMs;
  const cycleIndex = Math.round((cycleBoundaryMs - epochBoundaryMs) / cycleDurationMs);
  const rotation = ((cycleIndex % skip) + skip) % skip;
  const kCycleStartMs = cycleBoundaryMs - rotation * cycleDurationMs;
  const currentOffsetMs = nowMs - kCycleStartMs;
  const fadeTimeMs = fadeFraction * cycleDurationMs;

  let best = 0;
  for (let step = 0; step < divisions; step++) {
    const visitOffsetMs = (step * totalCycleMs) / divisions;
    let delta = currentOffsetMs - visitOffsetMs;
    if (delta > totalCycleMs / 2) delta -= totalCycleMs;
    if (delta < -totalCycleMs / 2) delta += totalCycleMs;
    if (Math.abs(delta) <= fadeTimeMs) {
      const op = Math.cos((delta / fadeTimeMs) * (Math.PI / 2));
      if (op > best) best = op;
    }
  }
  return best;
};

// Find all active geometries.
// A geometry appears when the dot is near ANY node of that shape.
// Nodes are at multiples of 360/divisions.
export const getActiveGeometries = (currentDegree, geometryList, fadeFraction = 0.03) => {
  const active = [];

  for (const shape of geometryList) {
    let bestOpacity = 0;
    for (let i = 0; i < shape.divisions; i++) {
      const nodeDegree = (i * 360) / shape.divisions;
      const opacity = computeGeometryOpacity(currentDegree, nodeDegree, fadeFraction);
      if (opacity > bestOpacity) {
        bestOpacity = opacity;
      }
    }

    if (bestOpacity > 0.001) {
      active.push({ ...shape, opacity: bestOpacity });
    }
  }

  return active;
};
