// Are the circles' indicator degrees independent of the machine's timezone?
//
// TimeFrame.ts claims "Degrees are ALWAYS UTC". That is the load-bearing claim
// for "two devices in different timezones see the same dot", so verify it by
// computing every timeframe's degree for a FIXED instant under several TZ
// values and diffing. Labels are expected to differ -- they are local by design.
import { allCases, degree, traditionalLabel } from "../dist/core/timeFrame.js";
import { moonDegree, quarterMoonDegree, phaseName } from "../dist/core/moonPhase.js";

const instants = [
  "2026-09-27T19:30:45.250Z",
  "2026-01-01T00:00:00.000Z",
  "2026-06-15T12:34:56.789Z",
  "2026-12-21T23:59:59.999Z",
  "2027-03-01T06:07:08.900Z",
];

const tz = process.env.TZ || "(unset)";
const rows = [];
for (const iso of instants) {
  const at = new Date(iso);
  const entry = { iso };
  for (const tf of allCases) entry[tf] = degree(tf, at);
  entry.moonPhase = phaseName(at);
  entry.label_day = traditionalLabel("day", at);
  entry.label_moon = traditionalLabel("moon", at);
  rows.push(entry);
}
console.log(JSON.stringify({ tz, rows }));
