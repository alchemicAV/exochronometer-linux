import { useRef, useEffect, useCallback, useState } from 'react';

// Throttle React re-renders to ~30fps instead of 60fps.
// The minute circle moves ~0.2°/frame at 30fps — still visually smooth,
// but halves the allocation rate from React's reconciliation overhead.
const FRAME_INTERVAL = 33;

export function useAnimationLoop() {
  const [timestamp, setTimestamp] = useState(Date.now());
  const rafRef = useRef();
  const lastUpdateRef = useRef(0);

  const tick = useCallback(() => {
    const now = Date.now();
    if (now - lastUpdateRef.current >= FRAME_INTERVAL) {
      lastUpdateRef.current = now;
      setTimestamp(now);
    }
    rafRef.current = requestAnimationFrame(tick);
  }, []);

  useEffect(() => {
    rafRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafRef.current);
  }, [tick]);

  return timestamp;
}
