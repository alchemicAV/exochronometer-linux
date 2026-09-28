/**
 * Port of ExochronometerCore/Geometry.swift
 * Pure integer/geometry math - no platform dependencies.
 */

export interface Edge {
  from: number;
  to: number;
}

export interface Shape {
  divisions: number;
  skip: number;
  path: Edge[];
  isRegular: boolean;
  nodeSpacing: number;
  id: string;
}

export function gcd(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y !== 0) {
    const t = y;
    y = x % y;
    x = t;
  }
  return x;
}

/** Largest odd divisor - pitch class of an integer multiplier under octave equivalence. */
export function oddPart(n: number): number {
  let x = Math.abs(n);
  while (x > 1 && x % 2 === 0) x /= 2;
  return x;
}

export function generateShapePath(divisions: number, skip: number): Edge[] {
  const path: Edge[] = [];
  const visited = new Set<number>();
  for (let start = 0; start < divisions; start++) {
    if (visited.has(start)) continue;
    let current = start;
    while (!visited.has(current)) {
      visited.add(current);
      const next = (current + skip) % divisions;
      path.push({ from: current, to: next });
      current = next;
    }
  }
  return path;
}

export function makeShape(divisions: number, skip: number): Shape {
  return {
    divisions,
    skip,
    path: generateShapePath(divisions, skip),
    isRegular: skip === 1,
    nodeSpacing: 360 / divisions,
    id: `${divisions}-${skip}`,
  };
}

export function buildShapeList(
  minDivisions = 3,
  maxDivisions = 12,
  includeStars = true,
): Shape[] {
  const shapes: Shape[] = [];
  if (minDivisions > maxDivisions) return shapes;
  for (let div = minDivisions; div <= maxDivisions; div++) {
    for (let skip = 1; skip < div; skip++) {
      if (skip >= div / 2) continue;
      if (gcd(div, skip) !== 1) continue;
      const isRegular = skip === 1;
      if (!includeStars && !isRegular) continue;
      shapes.push(makeShape(div, skip));
    }
  }
  return shapes;
}

export function nodeDegrees(divisions: number): number[] {
  return Array.from({ length: divisions }, (_, i) => (i * 360) / divisions);
}

/**
 * The shared shape list. In the Swift original this lived in
 * GeometryOverlayView.swift (a SwiftUI file) but is pure data.
 */
export const defaultShapes: Shape[] = buildShapeList(3, 8, true);
