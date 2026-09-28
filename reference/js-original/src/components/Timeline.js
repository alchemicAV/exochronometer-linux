import React, { useMemo, useRef, useState, useCallback } from 'react';
import './Timeline.css';

const FLAG_HEIGHTS = [36, 60, 84]; // staggered heights to avoid overlap
const ZOOM_LEVELS = [0.25, 0.5, 1, 2, 4, 8];
const DEFAULT_ZOOM_IDX = 2;
const MIN_GAP = 60;  // minimum px between notes at 1x zoom
const PX_PER_HOUR = 12; // base linear scale: px per hour of real time at 1x

const Timeline = ({ notes, onDeleteNote }) => {
  const scrollRef = useRef(null);
  const [zoomIdx, setZoomIdx] = useState(DEFAULT_ZOOM_IDX);
  const zoom = ZOOM_LEVELS[zoomIdx];

  // Sort notes by timestamp
  const sortedNotes = useMemo(() => {
    return [...notes].sort((a, b) => a.timestamp - b.timestamp);
  }, [notes]);

  // Compute positions and flag heights
  const noteLayout = useMemo(() => {
    if (sortedNotes.length === 0) return { items: [], totalWidth: 0 };

    if (sortedNotes.length === 1) {
      return {
        items: [{ ...sortedNotes[0], x: 60, flagHeight: FLAG_HEIGHTS[1] }],
        totalWidth: 160,
      };
    }

    // Compute time gaps — linear scale proportional to real time
    const gaps = [];
    for (let i = 1; i < sortedNotes.length; i++) {
      gaps.push(sortedNotes[i].timestamp - sortedNotes[i - 1].timestamp);
    }

    const MS_PER_HOUR = 3600000;
    const pixelGaps = gaps.map((g) => {
      const hours = g / MS_PER_HOUR;
      return Math.max(MIN_GAP, hours * PX_PER_HOUR) * zoom;
    });

    // Build positions
    const items = [];
    let x = 60;

    for (let i = 0; i < sortedNotes.length; i++) {
      let heightIdx = i % FLAG_HEIGHTS.length;

      if (i > 0) {
        const prevGap = pixelGaps[i - 1];
        const prevHeightIdx = items[i - 1]._heightIdx;
        if (prevGap < 100 * zoom && heightIdx === prevHeightIdx) {
          heightIdx = (heightIdx + 1) % FLAG_HEIGHTS.length;
        }
      }

      items.push({
        ...sortedNotes[i],
        x,
        flagHeight: FLAG_HEIGHTS[heightIdx],
        _heightIdx: heightIdx,
      });

      if (i < sortedNotes.length - 1) {
        x += pixelGaps[i];
      }
    }

    return { items, totalWidth: x + 60 };
  }, [sortedNotes, zoom]);

  const scroll = useCallback((direction) => {
    if (scrollRef.current) {
      scrollRef.current.scrollBy({ left: direction * 300, behavior: 'smooth' });
    }
  }, []);

  const zoomIn = useCallback(() => {
    setZoomIdx((i) => Math.min(i + 1, ZOOM_LEVELS.length - 1));
  }, []);

  const zoomOut = useCallback(() => {
    setZoomIdx((i) => Math.max(i - 1, 0));
  }, []);

  if (notes.length === 0) {
    return (
      <div className="timeline">
        <div className="timeline__empty">NO NOTES</div>
      </div>
    );
  }

  const formatDate = (ts) => {
    const d = new Date(ts);
    const mo = d.toLocaleString('en', { month: 'short' }).toUpperCase();
    const day = d.getDate();
    return `${mo} ${day}`;
  };

  const formatTime = (ts) => {
    const d = new Date(ts);
    const h = String(d.getHours()).padStart(2, '0');
    const m = String(d.getMinutes()).padStart(2, '0');
    return `${h}:${m}`;
  };

  return (
    <div className="timeline">
      <button className="timeline__arrow timeline__arrow--left" onClick={() => scroll(-1)}>
        <svg width="14" height="14" viewBox="0 0 14 14">
          <polygon points="10,2 4,7 10,12" fill="white" />
        </svg>
      </button>

      <div className="timeline__scroll" ref={scrollRef}>
        <div className="timeline__track" style={{ minWidth: noteLayout.totalWidth }}>
          {/* Horizontal line — spans full width */}
          <div className="timeline__line" />

          {/* Note flags */}
          {noteLayout.items.map((note) => (
            <div
              key={note.id}
              className="timeline__flag"
              style={{ left: note.x }}
            >
              <div
                className="timeline__flag-stem"
                style={{ height: note.flagHeight }}
              />
              <div
                className="timeline__flag-content"
                style={{ bottom: note.flagHeight + 4 }}
              >
                <span className="timeline__flag-date">{formatDate(note.timestamp)}</span>
                <span className="timeline__flag-time">{formatTime(note.timestamp)}</span>
                <span className="timeline__flag-text">{note.text}</span>
              </div>
              <div className="timeline__flag-dot" />
            </div>
          ))}
        </div>
      </div>

      <button className="timeline__arrow timeline__arrow--right" onClick={() => scroll(1)}>
        <svg width="14" height="14" viewBox="0 0 14 14">
          <polygon points="4,2 10,7 4,12" fill="white" />
        </svg>
      </button>

      <div className="timeline__zoom">
        <button className="timeline__zoom-btn" onClick={zoomOut} disabled={zoomIdx === 0}>-</button>
        <span className="timeline__zoom-label">{zoom}x</span>
        <button className="timeline__zoom-btn" onClick={zoomIn} disabled={zoomIdx === ZOOM_LEVELS.length - 1}>+</button>
      </div>
    </div>
  );
};

export default Timeline;
