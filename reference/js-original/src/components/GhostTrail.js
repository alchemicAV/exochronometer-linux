import React, { useRef, useEffect } from 'react';
import { computeGeometryOpacity } from '../utils/fadeUtils';
import './GhostTrail.css';

const TRAIL_LENGTH = 60;
const TRAIL_MAX_HEIGHT = 180;

// Compute best opacity for a geometry at a given degree (inline, no allocations)
const getGeomOpacity = (sliceDeg, divisions) => {
  let best = 0;
  for (let i = 0; i < divisions; i++) {
    const nodeDeg = (i * 360) / divisions;
    const op = computeGeometryOpacity(sliceDeg, nodeDeg);
    if (op > best) best = op;
  }
  return best;
};

// Collect all unique geometry node degrees, sorted
const getNodeDegreeList = (geometryList) => {
  const degSet = new Set();
  for (const geom of geometryList) {
    for (let i = 0; i < geom.divisions; i++) {
      // Round to avoid floating point duplicates
      degSet.add(Math.round(((i * 360) / geom.divisions) * 1000) / 1000);
    }
  }
  return Array.from(degSet).sort((a, b) => a - b);
};

// Check if a degree is a node for this geometry (within small tolerance)
const isNodeDegree = (deg, divisions) => {
  for (let i = 0; i < divisions; i++) {
    const nodeDeg = (i * 360) / divisions;
    if (Math.abs(deg - nodeDeg) < 0.01) return true;
  }
  return false;
};

const GhostTrail = ({ currentDegree, geometryList, radius, enabled, trailMode }) => {
  const canvasRef = useRef(null);
  const pointsCacheRef = useRef(new Map());

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');

    if (!enabled) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      return;
    }

    const width = canvas.width;
    const height = canvas.height;
    const centerX = width / 2;
    const topPad = radius + 6; // room for full top circle

    ctx.clearRect(0, 0, width, height);

    // Pre-compute points per divisions count (they only depend on divisions + radius + centerX)
    const pointsCache = pointsCacheRef.current;
    for (const geom of geometryList) {
      const cacheKey = geom.divisions;
      if (!pointsCache.has(cacheKey) || pointsCache.get(cacheKey)._radius !== radius) {
        const points = Array.from({ length: geom.divisions }, (_, j) => {
          const angle = ((j * 360) / geom.divisions - 90) * (Math.PI / 180);
          return {
            x: centerX + radius * Math.cos(angle),
            y: radius * Math.sin(angle),
          };
        });
        points._radius = radius;
        pointsCache.set(cacheKey, points);
      }
    }

    // Build slice positions based on trail mode
    let sliceDegrees;
    let totalSlots; // used for Y spacing

    if (trailMode === 'geometry') {
      // Geometry mode: slices at geometry node positions only
      const allNodes = getNodeDegreeList(geometryList);
      totalSlots = allNodes.length;
      sliceDegrees = allNodes.filter((d) => d > 0 && d <= currentDegree);
    } else {
      // Time mode: fixed-interval slices
      const sliceStep = 360 / TRAIL_LENGTH;
      const numSlices = Math.max(1, Math.floor(currentDegree / sliceStep));
      totalSlots = TRAIL_LENGTH;
      sliceDegrees = [];
      for (let i = 0; i < numSlices; i++) {
        sliceDegrees.push((i + 1) * sliceStep);
      }
    }

    const numSlices = sliceDegrees.length;

    for (let i = numSlices - 1; i >= 0; i--) {
      const sliceDeg = sliceDegrees[i];

      // Y position: newest (i=numSlices-1) at top, oldest (i=0) at bottom
      const progress = numSlices > 1 ? (numSlices - 1 - i) / (totalSlots - 1) : 0;
      const yOffset = topPad + progress * TRAIL_MAX_HEIGHT;

      const baseOpacity = (1 - progress) * 0.25;
      const scale = 1 - progress * 0.12;

      ctx.save();
      ctx.translate(centerX, yOffset);
      ctx.scale(scale, scale);
      ctx.translate(-centerX, 0);

      // Draw circle outline
      ctx.globalAlpha = baseOpacity;
      ctx.beginPath();
      ctx.arc(centerX, 0, radius, 0, Math.PI * 2);
      ctx.strokeStyle = 'white';
      ctx.lineWidth = 0.5;
      ctx.stroke();

      // Draw geometries
      if (trailMode === 'geometry') {
        // Geometry mode: only draw geometries that have a node at this exact degree, at full opacity
        for (const geom of geometryList) {
          if (!isNodeDegree(sliceDeg, geom.divisions)) continue;
          ctx.globalAlpha = Math.min(baseOpacity * 2, 0.45);
          const points = pointsCache.get(geom.divisions);
          for (const { from, to } of geom.path) {
            ctx.beginPath();
            ctx.moveTo(points[from].x, points[from].y);
            ctx.lineTo(points[to].x, points[to].y);
            ctx.strokeStyle = 'white';
            ctx.lineWidth = 0.7;
            ctx.stroke();
          }
        }
      } else {
        // Time mode: interpolated opacity
        for (const geom of geometryList) {
          const opacity = getGeomOpacity(sliceDeg, geom.divisions);
          if (opacity <= 0.001) continue;
          ctx.globalAlpha = baseOpacity * opacity;
          const points = pointsCache.get(geom.divisions);
          for (const { from, to } of geom.path) {
            ctx.beginPath();
            ctx.moveTo(points[from].x, points[from].y);
            ctx.lineTo(points[to].x, points[to].y);
            ctx.strokeStyle = 'white';
            ctx.lineWidth = 0.3;
            ctx.stroke();
          }
        }
      }

      // Draw dot
      ctx.globalAlpha = baseOpacity;
      const dotRad = (sliceDeg - 90) * (Math.PI / 180);
      const dotX = centerX + radius * Math.cos(dotRad);
      const dotY = radius * Math.sin(dotRad);
      ctx.beginPath();
      ctx.arc(dotX, dotY, 2, 0, Math.PI * 2);
      ctx.fillStyle = 'white';
      ctx.fill();

      ctx.restore();
    }
  }, [currentDegree, geometryList, radius, enabled, trailMode]);

  // Canvas tall enough for: top circle padding + trail height + bottom circle padding
  const canvasHeight = (radius + 6) + TRAIL_MAX_HEIGHT + radius + 6;

  return (
    <canvas
      ref={canvasRef}
      width={radius * 2 + 40}
      height={canvasHeight}
      className={`ghost-trail ${enabled ? 'ghost-trail--visible' : ''}`}
    />
  );
};

export default GhostTrail;
