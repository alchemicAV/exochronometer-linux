/**
 * Port of ExochronometerCore/PeakCalendar.swift
 *
 * The year circle's geometric-peak calendar.
 *
 * Every inscribed polygon {n} on the year circle (divisions 3…8) reaches an
 * absolute peak - amplitude 1.0 - when the year indicator crosses one of its
 * vertices. Collecting every distinct vertex angle across all shapes gives the
 * Farey sequence of order 8: 22 fractions of the circle. The gaps between
 * consecutive peaks are the "months" - 22 variable-length spans, palindromic
 * about the December<->June solstice axis, summing to one mean tropical year.
 *
 * A peak at p/q (lowest terms) belongs to harmonic q - the simplest polygon
 * with a vertex there (2/8 is really 1/4, a Quart peak, not an Oct one). Each
 * month is named `root(q) + suffix(p)`: the root is the harmonic/interval
 * (Tert, Quart, Quint, Hex, Sept, Oct), the suffix is the vertex numerator
 * (-one … -oz). The two fixed points of the mirror - 0/1 and 1/2 - get their
 * own names, `Initia` and `Meridia`.
 */
import { degree, tropicalYearDays, tropicalYearSeconds } from "./timeFrame.mjs";
import { gcd } from "./geometry.mjs";
/** The 22 months, ordered from the December solstice (`Initia`, 0°). */
export const months = build();
/**
 * Which month/day a date lands in. Uses the same solstice-anchored, UTC year
 * phase as every other timeframe, so the calendar and the year circle are one
 * clock.
 */
export function position(at) {
    const frac = yearFraction(at);
    let index = 0;
    for (let i = 0; i < months.length; i++) {
        if (openingFraction(months[i]) <= frac)
            index = i;
        else
            break;
    }
    const start = openingFraction(months[index]);
    const end = index + 1 < months.length ? openingFraction(months[index + 1]) : 1.0;
    const daysElapsed = (frac - start) * tropicalYearDays;
    const day = Math.max(1, Math.trunc(daysElapsed) + 1);
    const through = end > start ? (frac - start) / (end - start) : 0;
    return { monthIndex: index, dayOfMonth: day, fractionThroughMonth: through };
}
/**
 * The next instant at which `position(at:)` reports a different day - either
 * the day rolling over inside the month, or the month itself opening (which
 * resets the count to day 1).
 *
 * The year phase is linear in absolute time, so a target fraction converts
 * back to a date by simple proportion; no search needed. Widgets use this to
 * schedule a timeline entry per day rather than polling on a fixed clock
 * interval.
 */
export function nextDayBoundary(after) {
    const frac = yearFraction(after);
    const pos = position(after);
    const start = openingFraction(months[pos.monthIndex]);
    // Days are counted from the month's opening, so the boundaries are
    // start + k/yearDays - capped by the next month's opening, whichever comes
    // first (the last day of a month is a partial one).
    const nextDay = start + pos.dayOfMonth / tropicalYearDays;
    const monthEnd = pos.monthIndex + 1 < months.length ? openingFraction(months[pos.monthIndex + 1]) : 1.0;
    const target = Math.min(nextDay, monthEnd);
    return new Date(after.getTime() + (target - frac) * tropicalYearSeconds * 1000);
}
// MARK: - Derivation
function yearFraction(at) {
    let frac = degree("year", at) / 360.0;
    frac = frac % 1;
    if (frac < 0)
        frac += 1;
    return frac;
}
function openingFraction(m) {
    return m.openingDegree / 360.0;
}
function build() {
    // Farey_8: every reduced fraction p/q with q in 1…8, in [0, 1).
    const reduced = [];
    const seen = new Set();
    for (let q = 1; q <= 8; q++) {
        for (let p = 0; p < q; p++) {
            const g = gcd(p, q);
            const rp = p / g;
            const rq = q / g;
            const value = rp / rq;
            if (!seen.has(value)) {
                seen.add(value);
                reduced.push({ p: rp, q: rq });
            }
        }
    }
    reduced.sort((a, b) => a.p / a.q - b.p / b.q);
    const yearDays = tropicalYearDays;
    return reduced.map((f, i) => {
        const start = f.p / f.q;
        const end = i + 1 < reduced.length ? reduced[i + 1].p / reduced[i + 1].q : 1.0;
        const lengthDays = (end - start) * yearDays;
        const coincidingHarmonics = [];
        for (let d = 3; d <= 8; d++) {
            if (d % f.q === 0)
                coincidingHarmonics.push(d);
        }
        return {
            number: i + 1,
            name: name(f.p, f.q),
            shorthand: shorthand(f.p, f.q),
            numerator: f.p,
            harmonic: f.q,
            openingDegree: start * 360,
            lengthDays,
            coincidingHarmonics,
            id: i + 1,
            dayCount: Math.trunc(lengthDays) + 1,
            fractionLabel: `${f.p}/${f.q}`,
        };
    });
}
// MARK: - Naming
function rootName(q) {
    switch (q) {
        case 3: return "Tert";
        case 4: return "Quart";
        case 5: return "Quint";
        case 6: return "Hex";
        case 7: return "Sept";
        case 8: return "Oct";
        default: return "";
    }
}
function suffixName(p) {
    switch (p) {
        case 1: return "one";
        case 2: return "ava";
        case 3: return "is";
        case 4: return "yr";
        case 5: return "une";
        case 6: return "em";
        case 7: return "oz";
        default: return "";
    }
}
function name(p, q) {
    switch (q) {
        case 1: return "Initia";
        case 2: return "Meridia";
        default: return rootName(q) + suffixName(p);
    }
}
function rootLetter(q) {
    switch (q) {
        case 3: return "T";
        case 4:
        case 5: return "Q";
        case 6: return "H";
        case 7: return "S";
        case 8: return "O";
        default: return "";
    }
}
/**
 * First letter of the suffix - except `-oz`, which takes `Z` because its
 * natural `O` collides with `-one`.
 */
function suffixLetter(p) {
    switch (p) {
        case 1: return "O";
        case 2: return "A";
        case 3: return "I";
        case 4: return "Y";
        case 5: return "U";
        case 6: return "E";
        case 7: return "Z";
        default: return "";
    }
}
function shorthand(p, q) {
    switch (q) {
        case 1: return "IN";
        case 2: return "ME";
        case 4:
            // Quart's peaks (numerators 1, 3) both collide with a Quint peak, so it
            // always carries the 'R' of quaRt.
            return "QR" + suffixLetter(p);
        case 5:
            // Quint disambiguates only on the numerators Quart also has.
            return (p === 1 || p === 3 ? "QN" : "Q") + suffixLetter(p);
        default:
            return rootLetter(q) + suffixLetter(p);
    }
}
