/**
 * Interval naming for {n/k} polygons.
 *
 * Extracted from Exochronometer/GeometryHarmonicsPage.swift, where the original
 * keeps it as a private function in the view rather than in the Core framework.
 * Copied faithfully - including its behaviour on octave cases, which the
 * reference vectors confirm rather than "fix".
 *
 * Octave-reduces n:k until n/k is in [1, 2), then names the resulting simple
 * ratio. {n/k} polygons share the name of their octave multiples - e.g. {7/1}
 * and {7/2} both reduce to 7:4 (Harmonic Seventh).
 */
export function intervalName(n: number, k: number): string {
  const num = n;
  let den = k;
  while (num >= 2 * den) den *= 2;
  switch (`${num},${den}`) {
    case "1,1": return "Unison";
    case "2,1": return "Octave";
    case "3,2": return "Perfect Fifth";
    case "4,3": return "Perfect Fourth";
    case "5,3": return "Major Sixth";
    case "5,4": return "Major Third";
    case "6,5": return "Minor Third";
    case "7,4": return "Harmonic Seventh";
    case "7,5": return "Septimal Tritone";
    case "7,6": return "Septimal Subminor Third";
    case "8,5": return "Minor Sixth";
    case "8,7": return "Septimal Major Second";
    case "9,5": return "Minor Seventh";
    case "9,7": return "Septimal Major Third";
    case "9,8": return "Major Second";
    case "15,8": return "Major Seventh";
    case "16,15": return "Minor Second";
    case "45,32": return "Tritone";
    default: return `${num}:${den} ratio`;
  }
}

/**
 * Display name for a {n/k} shape. Extracted from the same view file
 * (GeometryHarmonicsPage.swift), where it is a private computed property on
 * HarmonicRow.
 */
export function shapeName(divisions: number, skip: number): string {
  switch (`${divisions},${skip}`) {
    case "3,1": return "TRIANGLE";
    case "4,1": return "SQUARE";
    case "5,1": return "PENTAGON";
    case "5,2": return "PENTAGRAM";
    case "6,1": return "HEXAGON";
    case "7,1": return "HEPTAGON";
    case "7,2": return "HEPTAGRAM {7/2}";
    case "7,3": return "HEPTAGRAM {7/3}";
    case "8,1": return "OCTAGON";
    case "8,3": return "OCTAGRAM";
    default: return `{${divisions}/${skip}}`;
  }
}