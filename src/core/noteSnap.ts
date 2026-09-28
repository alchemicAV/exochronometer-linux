/**
 * Port of ExochronometerCore/NoteSnap.swift
 *
 * Snaps user notes onto the geometry nodes of the year/moon/… circles and
 * gives the resulting nodes their breathing opacity.
 *
 * UUIDs cross the port boundary as plain strings (the Swift `UUID.uuidString`
 * lowercased form), so the data survives JSON and QML unchanged.
 */

import { type TimeFrame, cycleDuration } from "./timeFrame.js";
import { type Shape, defaultShapes, nodeDegrees } from "./geometry.js";
import { shapeOpacity } from "./fadeMath.js";

/** Swift: `NoteSnapshot`. */
export interface NoteSnapshot {
  id: string;
  timestamp: Date;
  degrees: { [frame: string]: number };
}

/**
 * Swift: `NoteSnapshot.degree(for:)`. `degrees` is keyed by
 * `TimeFrame.rawValue`, so a note simply has no reading for a circle it was
 * not captured against.
 */
export function noteDegree(note: NoteSnapshot, frame: TimeFrame): number | null {
  const v = note.degrees[frame];
  return v === undefined ? null : v;
}

/** Swift: `NoteSnap.Node`. */
export interface NoteSnapNode {
  degree: number;
  noteIDs: string[];
  id: number;
}

/** Swift's `Double.rounded()` rounds half away from zero; JS Math.round does not. */
function swiftRound(x: number): number {
  return Math.sign(x) * Math.floor(Math.abs(x) + 0.5);
}

/**
 * Snap each note to the nearest geometry node for each shape, within
 * (360 / divisions) / 4 of that node. A single note can light up multiple
 * nodes across different shapes. Filtered to the lookback window
 * (`lookbackCycles * circle.cycleDuration`).
 */
export function snap(
  notes: NoteSnapshot[],
  circle: TimeFrame,
  shapes: Shape[] = defaultShapes,
  lookbackCycles = 6,
  now: Date = new Date(),
): NoteSnapNode[] {
  if (notes.length === 0 || shapes.length === 0) return [];
  const lookback = lookbackCycles * cycleDuration(circle);
  const recent = notes.filter((n) => (now.getTime() - n.timestamp.getTime()) / 1000 <= lookback);
  if (recent.length === 0) return [];

  const map = new Map<number, { degree: number; ids: string[] }>();

  for (const shape of shapes) {
    const nodes = nodeDegrees(shape.divisions);
    const maxSnap = 360.0 / shape.divisions / 4;

    for (const note of recent) {
      const noteDeg = noteDegree(note, circle);
      if (noteDeg === null) continue;
      let bestNode = nodes[0];
      let bestDist = Number.POSITIVE_INFINITY;
      for (const nd of nodes) {
        let d = Math.abs(noteDeg - nd);
        if (d > 180) d = 360 - d;
        if (d < bestDist) {
          bestDist = d;
          bestNode = nd;
        }
      }
      if (bestDist > maxSnap) continue;

      const key = swiftRound(bestNode);
      const existing = map.get(key);
      if (existing !== undefined) {
        if (!existing.ids.includes(note.id)) existing.ids.push(note.id);
      } else {
        map.set(key, { degree: bestNode, ids: [note.id] });
      }
    }
  }

  return Array.from(map.values()).map((e) => ({
    degree: e.degree,
    noteIDs: e.ids,
    id: swiftRound(e.degree),
  }));
}

/**
 * Breathing opacity for a snapped node: max across all shapes that have a
 * vertex within 1° of this node degree.
 */
export function nodeOpacity(
  nodeDegree: number,
  currentDegree: number,
  shapes: Shape[] = defaultShapes,
  fadeFraction = 0.03,
): number {
  let best = 0.0;
  for (const shape of shapes) {
    const nodes = nodeDegrees(shape.divisions);
    for (const nd of nodes) {
      let d = Math.abs(nodeDegree - nd);
      if (d > 180) d = 360 - d;
      if (d < 1) {
        const op = shapeOpacity(currentDegree, shape.divisions, fadeFraction);
        if (op > best) best = op;
        break;
      }
    }
  }
  return best;
}
