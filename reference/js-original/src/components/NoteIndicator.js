import React from 'react';

const NoteIndicator = ({ degree, circleCenter, circleRadius, noteCount, opacity = 1, onClick }) => {
  const indicatorRadius = circleRadius + 18;
  const angle = (degree - 90) * (Math.PI / 180);
  const x = circleCenter + indicatorRadius * Math.cos(angle);
  const y = circleCenter + indicatorRadius * Math.sin(angle);

  return (
    <g
      opacity={opacity}
      onClick={(e) => {
        e.stopPropagation();
        onClick(degree);
      }}
      style={{ cursor: 'pointer' }}
    >
      {/* Invisible hit area — makes the whole circle clickable */}
      <circle
        cx={x}
        cy={y}
        r={7}
        fill="transparent"
      />
      <circle
        cx={x}
        cy={y}
        r={7}
        fill="none"
        stroke="rgba(255, 255, 255, 0.6)"
        strokeWidth="1"
      />
      {noteCount > 1 && (
        <text
          x={x}
          y={y + 1}
          textAnchor="middle"
          dominantBaseline="middle"
          fill="rgba(255,255,255,0.7)"
          fontSize="7"
          fontFamily="'Courier New', monospace"
        >
          {noteCount}
        </text>
      )}
    </g>
  );
};

export default NoteIndicator;
