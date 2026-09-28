import React, { useState, useCallback, useMemo, useId } from 'react';
import GeometryOverlay from './GeometryOverlay';
import GhostTrail from './GhostTrail';
import NoteIndicator from './NoteIndicator';
import NotePanel from './NotePanel';
import { getNodeDegrees } from '../utils/geometry';
import { computeGeometryOpacity, computeWindingOpacity } from '../utils/fadeUtils';
import './TimeCircle.css';

const SVG_SIZE = 200;
const CENTER = SVG_SIZE / 2;
const CIRCLE_RADIUS = 75;
const DOT_RADIUS = 4;

// Compute best opacity for a geometry at a given degree (no allocations)
const getGeomOpacity = (currentDegree, divisions) => {
  let best = 0;
  for (let i = 0; i < divisions; i++) {
    const nodeDeg = (i * 360) / divisions;
    const op = computeGeometryOpacity(currentDegree, nodeDeg);
    if (op > best) best = op;
  }
  return best;
};

const TimeCircle = ({
  circleId,
  label,
  sublabel,
  currentDegree,
  geometryList,
  liveMode,
  cycleDurationMs,
  nowMs,
  epochDegree,
  showGhostTrails,
  trailMode,
  noteLookback,
  notes,
  onDeleteNote,
  traditionalLabel,
}) => {
  const filterId = useId();
  const [openNoteNode, setOpenNoteNode] = useState(null);
  const [notePanelPos, setNotePanelPos] = useState({ x: 0, y: 0 });

  // Dot position
  const dotAngle = (currentDegree - 90) * (Math.PI / 180);
  const dotX = CENTER + CIRCLE_RADIUS * Math.cos(dotAngle);
  const dotY = CENTER + CIRCLE_RADIUS * Math.sin(dotAngle);

  // Collect all node degrees from active geometries that have notes
  // Regular polygons (skip=1): only notes from current rotation (1 * cycleDurationMs)
  // Star polygons (skip>1): notes from last `skip` rotations
  // Build note-to-node mapping (only changes when notes or geometry config changes)
  const noteNodeBase = useMemo(() => {
    const now = Date.now();

    if (notes.length === 0 || geometryList.length === 0) return [];

    const nodeMap = new Map(); // degree -> { degree, notes[] }

    for (const geom of geometryList) {
      const lookbackMs = noteLookback * cycleDurationMs;
      const recentNotes = notes.filter((n) => now - n.timestamp <= lookbackMs);
      if (recentNotes.length === 0) continue;

      const nodeDegrees = getNodeDegrees(geom.divisions);

      // Snap each note to its nearest geometry node
      for (const note of recentNotes) {
        const noteDeg = note.degrees[circleId];
        if (noteDeg === undefined) continue;

        // Find the closest node
        let bestNode = nodeDegrees[0];
        let bestDist = Infinity;
        for (const nodeDeg of nodeDegrees) {
          let diff = Math.abs(noteDeg - nodeDeg);
          if (diff > 180) diff = 360 - diff;
          if (diff < bestDist) {
            bestDist = diff;
            bestNode = nodeDeg;
          }
        }

        // Only snap if within half the node spacing
        const maxSnapDist = (360 / geom.divisions) / 4;
        if (bestDist > maxSnapDist) continue;

        const key = Math.round(bestNode);
        if (!nodeMap.has(key)) {
          nodeMap.set(key, { degree: bestNode, notes: [] });
        }
        const existing = nodeMap.get(key);
        if (!existing.notes.find((en) => en.id === note.id)) {
          existing.notes.push(note);
        }
      }
    }

    return Array.from(nodeMap.values());
  }, [geometryList, notes, circleId, cycleDurationMs, noteLookback]);

  // Compute opacity from currentDegree directly (avoids depending on unstable activeGeometries)
  const noteNodes = useMemo(() => {
    if (noteNodeBase.length === 0) return [];

    return noteNodeBase
      .map((node) => {
        let bestOpacity = 0;
        for (const geom of geometryList) {
          const nodeDegrees = getNodeDegrees(geom.divisions);
          for (const geomNodeDeg of nodeDegrees) {
            let diff = Math.abs(node.degree - geomNodeDeg);
            if (diff > 180) diff = 360 - diff;
            if (diff < 1) {
              // Compute opacity the same way getActiveGeometries does
              let geomOpacity = 0;
              for (let k = 0; k < geom.divisions; k++) {
                const nd = (k * 360) / geom.divisions;
                const op = computeGeometryOpacity(currentDegree, nd);
                if (op > geomOpacity) geomOpacity = op;
              }
              if (geomOpacity > bestOpacity) bestOpacity = geomOpacity;
            }
          }
        }
        return { ...node, opacity: bestOpacity };
      })
      .filter((node) => node.opacity > 0.001);
  }, [noteNodeBase, geometryList, currentDegree]);

  const handleIndicatorClick = useCallback((degree) => {
    const angle = (degree - 90) * (Math.PI / 180);
    const x = CENTER + (CIRCLE_RADIUS + 20) * Math.cos(angle);
    const y = CENTER + (CIRCLE_RADIUS + 20) * Math.sin(angle);
    setOpenNoteNode(degree);
    setNotePanelPos({ x, y });
  }, []);

  const openNodeData = useMemo(() => {
    if (openNoteNode === null) return null;
    return noteNodes.find((n) => Math.round(n.degree) === Math.round(openNoteNode));
  }, [openNoteNode, noteNodes]);

  return (
    <div className="time-circle">
      {/* Labels above */}
      <div className="time-circle__label">{label}</div>
      <div className="time-circle__sublabel">{sublabel}</div>
      <div className="time-circle__degree">{currentDegree.toFixed(1)}°</div>
      {traditionalLabel && (
        <div className="time-circle__traditional">{traditionalLabel}</div>
      )}

      <svg
        viewBox={`0 0 ${SVG_SIZE} ${SVG_SIZE}`}
        className="time-circle__svg"
      >
        <defs>
          <filter id={`glow-${filterId}`} filterUnits="userSpaceOnUse" x="0" y="0" width={SVG_SIZE} height={SVG_SIZE}>
            <feGaussianBlur stdDeviation="1.5" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
          <filter id={`dotGlow-${filterId}`}>
            <feGaussianBlur stdDeviation="3" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* Main circle outline */}
        <circle
          cx={CENTER}
          cy={CENTER}
          r={CIRCLE_RADIUS}
          fill="none"
          stroke="white"
          strokeWidth="1"
          opacity="0.6"
          filter={`url(#glow-${filterId})`}
        />

        {/* Geometry overlays — compute opacity inline, no intermediate objects.
            Regular polygons light on every vertex pass; star polygons are
            winding-gated (1-in-k passes, epoch-anchored). */}
        {geometryList.map((geom) => {
          const opacity = !liveMode
            ? 1
            : geom.skip === 1
              ? getGeomOpacity(currentDegree, geom.divisions)
              : computeWindingOpacity(
                  nowMs,
                  currentDegree,
                  cycleDurationMs,
                  epochDegree,
                  geom.divisions,
                  geom.skip
                );
          if (opacity <= 0.001) return null;
          return (
            <GeometryOverlay
              key={`${geom.divisions}-${geom.skip}`}
              divisions={geom.divisions}
              skip={geom.skip}
              path={geom.path}
              radius={CIRCLE_RADIUS}
              center={CENTER}
              opacity={opacity}
              glowFilterId={`glow-${filterId}`}
            />
          );
        })}

        {/* Orbiting dot */}
        <circle
          cx={dotX}
          cy={dotY}
          r={DOT_RADIUS}
          fill="white"
          filter={`url(#dotGlow-${filterId})`}
        />

        {/* Note indicators */}
        {noteNodes.map((node) => (
          <NoteIndicator
            key={Math.round(node.degree)}
            degree={node.degree}
            circleCenter={CENTER}
            circleRadius={CIRCLE_RADIUS}
            noteCount={node.notes.length}
            opacity={node.opacity}
            onClick={handleIndicatorClick}
          />
        ))}
      </svg>

      {/* Ghost trail */}
      <GhostTrail
        currentDegree={currentDegree}
        geometryList={geometryList}
        radius={CIRCLE_RADIUS}
        enabled={showGhostTrails}
        trailMode={trailMode}
      />

      {/* Note panel popover */}
      {openNoteNode !== null && openNodeData && (
        <NotePanel
          notes={openNodeData.notes}
          nodeDegree={openNoteNode}
          onClose={() => setOpenNoteNode(null)}
          onDelete={onDeleteNote}
          position={notePanelPos}
        />
      )}
    </div>
  );
};

export default TimeCircle;
