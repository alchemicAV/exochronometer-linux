import React from 'react';
import './DebugMenu.css';

// Mini SVG preview of a geometry shape
const ShapePreview = React.memo(({ divisions, path, size = 36 }) => {
  const center = size / 2;
  const radius = size / 2 - 2;

  const points = Array.from({ length: divisions }, (_, i) => {
    const angle = ((i * 360) / divisions - 90) * (Math.PI / 180);
    return {
      x: center + radius * Math.cos(angle),
      y: center + radius * Math.sin(angle),
    };
  });

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="shape-preview">
      {path.map(({ from, to }, i) => (
        <line
          key={i}
          x1={points[from].x}
          y1={points[from].y}
          x2={points[to].x}
          y2={points[to].y}
          stroke="white"
          strokeWidth="1"
        />
      ))}
    </svg>
  );
});

const DebugMenu = ({
  geometryList,
  disabledGeos,
  onToggle,
  onEnableAll,
  onDisableAll,
  liveMode,
  onToggleLive,
  noteLookback,
  onNoteLookbackChange,
  circles,
  disabledCircles,
  onToggleCircle,
  showTraditionalTime,
  onToggleTraditionalTime,
  showTimeline,
  onToggleTimeline,
  trailMode,
  onToggleTrailMode,
}) => {
  return (
    <div className="debug-menu">
      <div className="debug-menu__content">
        <div className="debug-menu__header">
          <label className="debug-menu__live-toggle">
            <input
              type="checkbox"
              checked={liveMode}
              onChange={(e) => onToggleLive(e.target.checked)}
            />
            <span className="debug-menu__live-label">LIVE</span>
          </label>
          <button
            className={`debug-menu__action ${showTimeline ? 'debug-menu__action--active' : ''}`}
            onClick={onToggleTimeline}
          >
            {showTimeline ? 'LOOPS' : 'TIMELINE'}
          </button>
        </div>

        {/* Circle toggle cards */}
        <div className="debug-menu__circle-grid">
          {circles.map((circle) => {
            const enabled = !disabledCircles.has(circle.id);
            return (
              <button
                key={circle.id}
                className={`debug-menu__circle-btn ${enabled ? 'debug-menu__circle-btn--on' : 'debug-menu__circle-btn--off'}`}
                onClick={() => onToggleCircle(circle.id)}
                title={circle.sublabel}
              >
                <svg width="26" height="26" viewBox="0 0 26 26" className="shape-preview">
                  <circle cx="13" cy="13" r="10" fill="none" stroke="white" strokeWidth="1" />
                </svg>
                <span className="debug-menu__circle-btn-label">{circle.label}</span>
              </button>
            );
          })}
        </div>

        <div className="debug-menu__grid">
          {geometryList.map((geom) => {
            const key = `${geom.divisions}-${geom.skip}`;
            const enabled = !disabledGeos.has(key);
            const label = geom.skip === 1
              ? `{${geom.divisions}}`
              : `{${geom.divisions}/${geom.skip}}`;

            return (
              <button
                key={key}
                className={`debug-menu__btn ${enabled ? 'debug-menu__btn--on' : 'debug-menu__btn--off'}`}
                onClick={() => onToggle(key)}
                title={`${geom.divisions} divisions, skip ${geom.skip}${geom.isRegular ? '' : ' (star)'}`}
              >
                <ShapePreview divisions={geom.divisions} path={geom.path} />
                <span className="debug-menu__btn-label">{label}</span>
              </button>
            );
          })}
        </div>

        <div className="debug-menu__header">
          <button className="debug-menu__action" onClick={onEnableAll}>
            ALL ON
          </button>
          <button className="debug-menu__action" onClick={onDisableAll}>
            ALL OFF
          </button>
        </div>

        <div className="debug-menu__settings-row">
          <div className="debug-menu__setting">
            <span className="debug-menu__setting-label">HOLD NOTES FOR</span>
            <select
              className="debug-menu__select"
              value={noteLookback}
              onChange={(e) => onNoteLookbackChange(Number(e.target.value))}
            >
              {Array.from({ length: 12 }, (_, i) => i + 1).map((n) => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
            <span className="debug-menu__setting-label">ROTATIONS</span>
          </div>
        </div>

        <div className="debug-menu__settings-row">
          <button
            className={`debug-menu__action ${trailMode === 'geometry' ? 'debug-menu__action--active' : ''}`}
            onClick={onToggleTrailMode}
          >
            TRAIL: {trailMode === 'time' ? 'TIME' : 'GEO'}
          </button>
          <label className="debug-menu__live-toggle">
            <input
              type="checkbox"
              checked={showTraditionalTime}
              onChange={(e) => onToggleTraditionalTime(e.target.checked)}
            />
            <span className="debug-menu__live-label">TRADITIONAL TIME</span>
          </label>
        </div>
      </div>
    </div>
  );
};

export default DebugMenu;
