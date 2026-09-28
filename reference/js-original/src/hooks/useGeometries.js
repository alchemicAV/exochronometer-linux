import { useMemo } from 'react';
import { buildGeometryList } from '../utils/geometry';

export function useGeometries(minDivisions = 3, maxDivisions = 12) {
  const geometryList = useMemo(() => {
    // Always include stars — range controls which divisions appear
    return buildGeometryList(minDivisions, maxDivisions, true);
  }, [minDivisions, maxDivisions]);

  return { geometryList };
}
