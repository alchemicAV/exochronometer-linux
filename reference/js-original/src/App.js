import React, { useState, useRef, useMemo, useCallback } from 'react';
import { useAnimationLoop } from './hooks/useAnimationLoop';
import { useGeometries } from './hooks/useGeometries';
import { useNotes } from './hooks/useNotes';
import { CIRCLES } from './utils/timeUtils';
import TimeCircle from './components/TimeCircle';
import ControlBar from './components/ControlBar';
import DebugMenu from './components/DebugMenu';
import JournalInput from './components/JournalInput';
import Timeline from './components/Timeline';
import './App.css';

// Generate ambient particles
const particles = Array.from({ length: 20 }, (_, i) => ({
  id: i,
  left: `${Math.random() * 100}%`,
  animationDuration: `${15 + Math.random() * 25}s`,
  animationDelay: `${Math.random() * 20}s`,
  size: `${1 + Math.random() * 1.5}px`,
}));

const isMobile = window.innerWidth <= 768;
const DEFAULT_DISABLED_CIRCLES = isMobile
  ? new Set(['year', 'moon', 'quarterMoon', 'day', 'hour'])
  : new Set();

function App() {
  const timestamp = useAnimationLoop();
  const [minDiv, setMinDiv] = useState(3);
  const [maxDiv, setMaxDiv] = useState(8);
  const [showGhostTrails, setShowGhostTrails] = useState(true);
  const [debugMode, setDebugMode] = useState(false);
  const [disabledGeos, setDisabledGeos] = useState(new Set());
  const [disabledCircles, setDisabledCircles] = useState(DEFAULT_DISABLED_CIRCLES);
  const [noteLookback, setNoteLookback] = useState(6);
  const [liveMode, setLiveMode] = useState(true);
  const [showTraditionalTime, setShowTraditionalTime] = useState(false);
  const [showTimeline, setShowTimeline] = useState(false);
  const [trailMode, setTrailMode] = useState('time');
  const frozenDegreesRef = useRef(null);
  const { geometryList } = useGeometries(minDiv, maxDiv);
  const { notes, addNote, deleteNote } = useNotes();

  // Filter geometry list when debug mode has disabled shapes
  const filteredGeometryList = useMemo(() => {
    if (disabledGeos.size === 0) return geometryList;
    return geometryList.filter(
      (g) => !disabledGeos.has(`${g.divisions}-${g.skip}`)
    );
  }, [geometryList, disabledGeos]);

  // Filter visible circles
  const visibleCircles = useMemo(() => {
    return CIRCLES.filter((c) => !disabledCircles.has(c.id));
  }, [disabledCircles]);

  // Compute current degrees for all circles (always tracks real time)
  const degrees = useMemo(() => {
    const result = {};
    for (const circle of CIRCLES) {
      result[circle.id] = circle.getDegree(timestamp);
    }
    return result;
  }, [timestamp]);

  // Keep a ref to degrees so callbacks don't recreate every frame
  const degreesRef = useRef(degrees);
  degreesRef.current = degrees;

  // Toggle live/frozen mode
  const handleToggleLive = useCallback((checked) => {
    if (!checked) {
      // Entering frozen mode — snapshot current degrees
      frozenDegreesRef.current = { ...degreesRef.current };
    }
    setLiveMode(checked);
  }, []);

  // Display degrees: frozen snapshot or real-time
  const displayDegrees = liveMode ? degrees : (frozenDegreesRef.current || degrees);

  // Add note with current degrees (always uses real time, not frozen)
  const handleAddNote = useCallback(
    (text) => {
      addNote(text, degreesRef.current);
    },
    [addNote]
  );

  // Debug mode: toggle a single geometry
  const handleToggleGeo = useCallback((key) => {
    setDisabledGeos((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }, []);

  // Debug mode: enable all geometries
  const handleEnableAll = useCallback(() => {
    setDisabledGeos(new Set());
  }, []);

  // Debug mode: disable all geometries
  const handleDisableAll = useCallback(() => {
    setDisabledGeos(
      new Set(geometryList.map((g) => `${g.divisions}-${g.skip}`))
    );
  }, [geometryList]);

  // Toggle a circle on/off
  const handleToggleCircle = useCallback((circleId) => {
    setDisabledCircles((prev) => {
      const next = new Set(prev);
      if (next.has(circleId)) {
        next.delete(circleId);
      } else {
        next.add(circleId);
      }
      return next;
    });
  }, []);

  // Ghost trails hidden when debug mode is on
  const effectiveGhostTrails = showGhostTrails && !debugMode;

  return (
    <div className="app">
      {/* Ambient particles */}
      <div className="app__ambient">
        {particles.map((p) => (
          <div
            key={p.id}
            className="app__particle"
            style={{
              left: p.left,
              animationDuration: p.animationDuration,
              animationDelay: p.animationDelay,
              width: p.size,
              height: p.size,
            }}
          />
        ))}
      </div>

      <ControlBar
        minDiv={minDiv}
        maxDiv={maxDiv}
        onMinDivChange={setMinDiv}
        onMaxDivChange={setMaxDiv}
        showGhostTrails={showGhostTrails}
        onToggleGhosts={setShowGhostTrails}
        debugMode={debugMode}
        onToggleDebug={() => setDebugMode((d) => !d)}
      />

      <div className="circle-row">
        {visibleCircles.map((circle, i) => {
          const n = visibleCircles.length;
          const center = (n - 1) / 2;
          const d = center > 0 ? (i - center) / center : 0;
          const arcY = -8 + 20 * d * d;
          return (
            <div
              key={circle.id}
              className={`circle-row__item ${showTimeline ? 'circle-row__item--hidden' : ''}`}
              style={{ transform: `translateY(${arcY}px)` }}
            >
              <TimeCircle
                circleId={circle.id}
                label={circle.label}
                sublabel={circle.sublabel}
                currentDegree={displayDegrees[circle.id]}
                geometryList={filteredGeometryList}
                liveMode={liveMode}
                cycleDurationMs={circle.cycleDurationMs}
                nowMs={timestamp}
                epochDegree={circle.epochDegree}
                showGhostTrails={effectiveGhostTrails}
                trailMode={trailMode}
                noteLookback={noteLookback}
                notes={notes}
                onDeleteNote={deleteNote}
                traditionalLabel={showTraditionalTime ? circle.getTraditionalLabel(timestamp) : null}
              />
            </div>
          );
        })}

        <div className={`circle-row__timeline ${showTimeline ? 'circle-row__timeline--visible' : ''}`}>
          <Timeline notes={notes} onDeleteNote={deleteNote} />
        </div>

        {debugMode && (
          <DebugMenu
            geometryList={geometryList}
            disabledGeos={disabledGeos}
            onToggle={handleToggleGeo}
            onEnableAll={handleEnableAll}
            onDisableAll={handleDisableAll}
            liveMode={liveMode}
            onToggleLive={handleToggleLive}
            noteLookback={noteLookback}
            onNoteLookbackChange={setNoteLookback}
            circles={CIRCLES}
            disabledCircles={disabledCircles}
            onToggleCircle={handleToggleCircle}
            showTraditionalTime={showTraditionalTime}
            onToggleTraditionalTime={setShowTraditionalTime}
            showTimeline={showTimeline}
            onToggleTimeline={() => setShowTimeline((t) => !t)}
            trailMode={trailMode}
            onToggleTrailMode={() => setTrailMode((m) => m === 'time' ? 'geometry' : 'time')}
          />
        )}
      </div>

      <JournalInput onAddNote={handleAddNote} />
      <div className="app__title">
        EXOCHRONOMETER
        <div className="app__title-sub">JOURNAL</div>
      </div>
    </div>
  );
}

export default App;
