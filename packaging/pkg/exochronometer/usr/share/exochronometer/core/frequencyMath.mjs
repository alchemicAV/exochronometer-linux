/**
 * Port of ExochronometerCore/FrequencyMath.swift
 *
 * Frequency/period formatting. The helpers use printf `%.2f` rounding, which is
 * NOT what JS toFixed does - see printfFixed below.
 */
import { tropicalYearSeconds } from "./timeFrame.mjs";
export const audibleMinHz = 20;
export const audibleMaxHz = 20000;
/**
 * `%.Nf` as C printf renders it - which is NOT what JS toFixed does.
 *
 * printf rounds the EXACT binary value of the double. Two traps:
 *  1. toFixed resolves an exact tie away from zero, printf rounds ties to even
 *     (default FE_TONEAREST): 0.125 -> printf "0.12", toFixed "0.13".
 *  2. Computing `x * 100` first and rounding that is wrong twice over - the
 *     multiply itself rounds. 0.005 stored as 0.005000000000000000104 must give
 *     "0.01" (printf does); 0.005 * 100 lands on 0.49999999999999994 and would
 *     give "0.00".
 *
 * So the value is read as a decimal expansion (toFixed(20) is exact for doubles
 * in this magnitude range) and rounded digit-wise, where "exactly half" is
 * decided by comparing digits rather than by a floating-point guess.
 *
 * NOTE: an earlier version used BigInt for exact integer arithmetic. QML's V4
 * JS engine has NO BigInt support, and a BigInt literal is a PARSE error that
 * kills the entire module import - so this must stay BigInt-free.
 */
export function printfFixed(x, digits) {
    if (!Number.isFinite(x))
        return String(x);
    const neg = x < 0;
    const v = Math.abs(x);
    const s = v.toFixed(20);
    const dot = s.indexOf(".");
    const intPart = dot < 0 ? s : s.slice(0, dot);
    let frac = dot < 0 ? "" : s.slice(dot + 1);
    while (frac.length < digits + 1)
        frac += "0";
    // beyond the range where digit-wise accumulation stays exact
    if (intPart.length > 12 || s.indexOf("e") >= 0 || s.indexOf("E") >= 0) {
        return (neg ? "-" : "") + v.toFixed(digits);
    }
    let n = parseInt(intPart, 10);
    let scale = 1;
    for (let i = 0; i < digits; i++) {
        n = n * 10 + (frac.charCodeAt(i) - 48);
        scale *= 10;
    }
    const rest = frac.slice(digits);
    // compare `rest` against "5" followed by zeros
    let cmp = 0;
    for (let i = 0; i < rest.length; i++) {
        const c = rest.charCodeAt(i) - 48;
        const h = i === 0 ? 5 : 0;
        if (c > h) {
            cmp = 1;
            break;
        }
        if (c < h) {
            cmp = -1;
            break;
        }
    }
    if (cmp > 0)
        n += 1;
    else if (cmp === 0) {
        if (n % 2 !== 0)
            n += 1;
    } // exact tie -> even
    const ip = Math.floor(n / scale);
    if (digits === 0)
        return (neg ? "-" : "") + String(ip);
    let fp = String(n % scale);
    while (fp.length < digits)
        fp = "0" + fp;
    return (neg ? "-" : "") + String(ip) + "." + fp;
}
/** f = 1 / period */
export function hz(forPeriod) {
    if (!(forPeriod > 0))
        return 0;
    return 1 / forPeriod;
}
/** Multiply by 2^n (n octaves up). Preserves all harmonic ratios. */
export function scaled(hzValue, octaves) {
    return hzValue * Math.pow(2, octaves);
}
/**
 * Pretty-print a frequency. Below 1 Hz, displays as a time period; above, as
 * Hz / kHz / MHz.
 */
export function format(hzValue) {
    if (!Number.isFinite(hzValue) || hzValue <= 0)
        return "—";
    if (hzValue < 1) {
        return formatDuration(1 / hzValue);
    }
    else if (hzValue >= 1_000_000) {
        return printfFixed(hzValue / 1_000_000, 2) + " MHz";
    }
    else if (hzValue >= 1_000) {
        return printfFixed(hzValue / 1_000, 2) + " kHz";
    }
    else {
        return printfFixed(hzValue, 2) + " Hz";
    }
}
/** Pretty-print a duration in seconds. */
export function formatDuration(seconds) {
    const year = tropicalYearSeconds;
    const day = 24 * 60 * 60;
    const hour = 60 * 60;
    if (seconds >= year) {
        return printfFixed(seconds / year, 2) + " years";
    }
    else if (seconds >= day) {
        return printfFixed(seconds / day, 2) + " days";
    }
    else if (seconds >= hour) {
        return printfFixed(seconds / hour, 2) + " hours";
    }
    else if (seconds >= 60) {
        return printfFixed(seconds / 60, 2) + " min";
    }
    else {
        return printfFixed(seconds, 2) + " sec";
    }
}
