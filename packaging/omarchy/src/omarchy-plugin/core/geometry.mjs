/**
 * Port of ExochronometerCore/Geometry.swift
 * Pure integer/geometry math - no platform dependencies.
 */
export function gcd(a, b) {
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
export function oddPart(n) {
    let x = Math.abs(n);
    while (x > 1 && x % 2 === 0)
        x /= 2;
    return x;
}
export function generateShapePath(divisions, skip) {
    const path = [];
    const visited = new Set();
    for (let start = 0; start < divisions; start++) {
        if (visited.has(start))
            continue;
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
export function makeShape(divisions, skip) {
    return {
        divisions,
        skip,
        path: generateShapePath(divisions, skip),
        isRegular: skip === 1,
        nodeSpacing: 360 / divisions,
        id: `${divisions}-${skip}`,
    };
}
export function buildShapeList(minDivisions = 3, maxDivisions = 12, includeStars = true) {
    const shapes = [];
    if (minDivisions > maxDivisions)
        return shapes;
    for (let div = minDivisions; div <= maxDivisions; div++) {
        for (let skip = 1; skip < div; skip++) {
            if (skip >= div / 2)
                continue;
            if (gcd(div, skip) !== 1)
                continue;
            const isRegular = skip === 1;
            if (!includeStars && !isRegular)
                continue;
            shapes.push(makeShape(div, skip));
        }
    }
    return shapes;
}
export function nodeDegrees(divisions) {
    return Array.from({ length: divisions }, (_, i) => (i * 360) / divisions);
}
/**
 * The shared shape list. In the Swift original this lived in
 * GeometryOverlayView.swift (a SwiftUI file) but is pure data.
 */
export const defaultShapes = buildShapeList(3, 8, true);
