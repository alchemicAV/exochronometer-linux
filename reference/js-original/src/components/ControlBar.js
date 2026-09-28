import React from 'react';
import './ControlBar.css';

// Divisors of 360 that are >= 3 — the only divisions producing
// clean geometric convergences where (degrees * divisions) % 360 === 0
const VIABLE_DIVISIONS = [3, 4, 5, 6, 8, 9, 10, 12, 15, 18, 20, 24, 30, 36];

const ControlBar = ({
  minDiv,
  maxDiv,
  onMinDivChange,
  onMaxDivChange,
  showGhostTrails,
  onToggleGhosts,
  debugMode,
  onToggleDebug,
}) => {
  return (
    <div className="control-bar">
      <div className="control-range">
        <span className="control-range__label">DIVISIONS</span>
        <div className="control-range__inputs">
          <select
            className="control-range__select"
            value={minDiv}
            onChange={(e) => onMinDivChange(Number(e.target.value))}
          >
            {VIABLE_DIVISIONS.filter((d) => d <= maxDiv).map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
          <span className="control-range__sep">—</span>
          <select
            className="control-range__select"
            value={maxDiv}
            onChange={(e) => onMaxDivChange(Number(e.target.value))}
          >
            {VIABLE_DIVISIONS.filter((d) => d >= minDiv).map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
        </div>
      </div>
      <label className="control-toggle">
        <input
          type="checkbox"
          checked={showGhostTrails}
          onChange={(e) => onToggleGhosts(e.target.checked)}
        />
        <span className="control-toggle__label">TRAILS</span>
      </label>
      <button
        className={`control-btn control-btn--more ${debugMode ? 'control-btn--active' : ''}`}
        onClick={onToggleDebug}
      >
        MORE
      </button>
    </div>
  );
};

export default ControlBar;
