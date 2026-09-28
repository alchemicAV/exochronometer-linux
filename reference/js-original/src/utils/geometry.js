// Geometry convergence math - ported from Starship-Coil-Designer

export const gcd = (a, b) => {
  a = Math.abs(Math.round(a));
  b = Math.abs(Math.round(b));
  while (b) {
    [a, b] = [b, a % b];
  }
  return a;
};

export const generateShapePath = (divisions, skip) => {
  const path = [];
  const visited = new Set();

  // Trace all components — for compound shapes (gcd > 1),
  // each component starts from the next unvisited node
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
};

// Build list of valid geometry shapes.
// Each shape: { divisions, skip, path, isRegular, nodeSpacing }
// nodeSpacing = 360 / divisions (degrees between nodes)
export const buildGeometryList = (minDivisions = 3, maxDivisions = 12, includeStars = true) => {
  const shapes = [];

  for (let div = minDivisions; div <= maxDivisions; div++) {
    for (let skip = 1; skip < div; skip++) {
      // Skip mirrors and degenerate diameters (skip >= div/2)
      if (skip >= div / 2) continue;

      // Skip compound shapes (gcd > 1): these are multiple separate
      // components, not one continuous line (e.g. {6,2} = two triangles)
      if (gcd(div, skip) !== 1) continue;

      const isReg = skip === 1;
      if (!includeStars && !isReg) continue;

      const path = generateShapePath(div, skip);

      shapes.push({
        divisions: div,
        skip,
        path,
        isRegular: isReg,
        nodeSpacing: 360 / div,
      });
    }
  }

  return shapes;
};

// Get the node positions (in degrees) for a geometry
export const getNodeDegrees = (divisions) => {
  return Array.from({ length: divisions }, (_, i) => (i * 360) / divisions);
};
