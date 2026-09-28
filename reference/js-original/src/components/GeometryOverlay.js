import React, { useMemo } from 'react';

const GeometryOverlay = React.memo(({ divisions, skip, path, radius, center, opacity, glowFilterId }) => {
  // Points only depend on divisions/radius/center (stable), not opacity
  const points = useMemo(() =>
    Array.from({ length: divisions }, (_, i) => {
      const angle = ((i * 360) / divisions - 90) * (Math.PI / 180);
      return {
        x: center + radius * Math.cos(angle),
        y: center + radius * Math.sin(angle),
      };
    }),
    [divisions, radius, center]
  );

  return (
    <g opacity={opacity}>
      {path.map(({ from, to }, i) => (
        <line
          key={i}
          x1={points[from].x}
          y1={points[from].y}
          x2={points[to].x}
          y2={points[to].y}
          stroke="rgba(255,255,255,0.85)"
          strokeWidth="0.6"
          filter={glowFilterId ? `url(#${glowFilterId})` : undefined}
        />
      ))}
    </g>
  );
});

export default GeometryOverlay;
