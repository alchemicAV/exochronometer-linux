/**
 * Render the instrument's composite signal to a 16-bit PCM WAV, through the
 * synth's voicing layer.
 *
 * The tone BANK is fixed by the geometry and is never touched here: this shapes
 * only how that fixed set is rendered, which is exactly the split the Swift
 * original draws between its tone set and `SynthParams`. The parameters, in the
 * order the pipeline applies them, are:
 *
 *   unisonVoices + detuneCents  copies per tone, spread in cents (decorrelated
 *                               by giving each copy its own phase)
 *   partials + enrichment +     integer harmonics above each copy, gain
 *     partialTilt               enrichment / k^tilt, skipped above Nyquist
 *   width                       constant-power panning of the unison copies
 *   tremoloRateHz + depth       sub-audio amplitude LFO
 *   lowpassHz                   one-pole low-pass (6 dB/oct)
 *   reverbMix + reverbPreset    Schroeder comb + allpass network, wet/dry
 *   attackMs + releaseMs        NOTE: applied by the player as a volume ramp,
 *                               not baked in - a sustaining loop must not
 *                               re-swell on every pass. See SynthPlayer.qml.
 *
 * Two properties of the output are load-bearing and are checked by
 * `test/validate-wav.mjs`:
 *
 *   - **The loop seam is continuous.** The player sustains by repeating this
 *     buffer, so the tail is crossfaded back into the head. Without that, every
 *     pass clicks.
 *   - **Nothing is fabricated above Nyquist.** Adding partials to a 16 kHz hour
 *     tone would otherwise alias harmonics down into the audible band as
 *     frequencies the chord does not contain, which is the one thing the
 *     information-safe half of the parameter set is supposed to avoid.
 */
/** A shaping that leaves the signal alone, for callers that pass nothing. */
export const dryShape = {
    attackMs: 0, releaseMs: 0, lowpassHz: 20000, reverbMix: 0, reverbPreset: 0,
    tremoloRateHz: 0, tremoloDepth: 0, width: 0, unisonVoices: 1, detuneCents: 0,
    enrichment: 0, partials: 0, partialTilt: 0,
};
export const sampleRate = 44100;
export const bitsPerSample = 16;
/** Peak level the buffer is scaled to, leaving a little headroom. */
export const headroom = 0.9;
/** Nothing is rendered above this fraction of the sample rate. */
export const kNyquistFraction = 0.45;
/** Crossfade length that makes the buffer loop without a click, in seconds. */
export const seamSeconds = 0.25;
/** Delay lengths in samples at 44.1 kHz, scaled per preset. Schroeder's set. */
const combBase = [1557, 1617, 1491, 1422];
const allpassBase = [225, 556];
/** Size and feedback per reverb preset, matching `reverbPresetNames`. */
const presetScale = [0.35, 0.5, 0.7, 0.85, 1.0, 0.6];
const presetFeedback = [0.62, 0.7, 0.76, 0.8, 0.84, 0.72];
/** Duration in seconds, clamped so a stray value cannot allocate forever. */
export function clampDuration(seconds) {
    if (!isFinite(seconds) || seconds <= 0)
        return 1;
    return Math.min(seconds, 30);
}
function clamp(v, lo, hi) {
    if (!isFinite(v))
        return lo;
    return v < lo ? lo : v > hi ? hi : v;
}
/**
 * The bare composite signal - the sum the oscilloscope draws - with no voicing
 * applied. Kept as its own function because it is the reference the validator
 * checks against an independent evaluation.
 */
export function renderSamples(tones, seconds, rate = sampleRate, phase0 = 0) {
    const total = Math.max(1, Math.round(clampDuration(seconds) * rate));
    const out = new Array(total);
    for (let i = 0; i < total; i++) {
        const t = (i + phase0) / rate;
        let s = 0;
        for (let j = 0; j < tones.length; j++) {
            s += Math.sin(2 * Math.PI * tones[j].frequency * t) * tones[j].amplitude;
        }
        out[i] = s;
    }
    return out;
}
/** One-pole low-pass, in place. `fc` >= 0.45*rate is a no-op. */
function lowpass(buf, fc, rate) {
    const cut = clamp(fc, 20, 0.45 * rate);
    if (cut >= 0.449 * rate)
        return;
    const alpha = 1 - Math.exp(-2 * Math.PI * cut / rate);
    let y = 0;
    for (let i = 0; i < buf.length; i++) {
        y += alpha * (buf[i] - y);
        buf[i] = y;
    }
}
/** Schroeder reverb: parallel combs into series allpasses. In place. */
function reverb(l, r, mix, preset, rate) {
    const wet = clamp(mix / 100, 0, 1);
    if (wet <= 0)
        return;
    const p = Math.max(0, Math.min(presetScale.length - 1, Math.round(preset)));
    const scale = presetScale[p] * (rate / sampleRate);
    const fb = presetFeedback[p];
    const channels = [l, r];
    for (let c = 0; c < 2; c++) {
        const buf = channels[c];
        const dry = buf.slice(0);
        // A few samples of offset on the right channel keeps the tail from being
        // a mono signal panned centre.
        const skew = c === 1 ? Math.round(23 * scale) + 7 : 0;
        const wetBuf = new Array(buf.length);
        for (let i = 0; i < wetBuf.length; i++)
            wetBuf[i] = 0;
        for (let ci = 0; ci < combBase.length; ci++) {
            const delay = Math.max(1, Math.round(combBase[ci] * scale)) + skew;
            const line = new Array(delay);
            for (let i = 0; i < delay; i++)
                line[i] = 0;
            let idx = 0;
            for (let i = 0; i < dry.length; i++) {
                const delayed = line[idx];
                line[idx] = dry[i] + delayed * fb;
                wetBuf[i] += delayed * 0.25;
                idx = idx + 1 === delay ? 0 : idx + 1;
            }
        }
        for (let ai = 0; ai < allpassBase.length; ai++) {
            const delay = Math.max(1, Math.round(allpassBase[ai] * scale)) + skew;
            const line = new Array(delay);
            for (let i = 0; i < delay; i++)
                line[i] = 0;
            let idx = 0;
            for (let i = 0; i < wetBuf.length; i++) {
                const delayed = line[idx];
                const x = wetBuf[i];
                line[idx] = x + delayed * 0.5;
                wetBuf[i] = delayed - x * 0.5;
                idx = idx + 1 === delay ? 0 : idx + 1;
            }
        }
        for (let i = 0; i < buf.length; i++)
            buf[i] = dry[i] * (1 - wet) + wetBuf[i] * wet;
    }
}
/**
 * Render the shaped signal as one or two channel arrays.
 *
 * Stereo only when there is something to decorrelate: one unison voice, or a
 * width of zero, is a mono signal and shipping it as two identical channels
 * would just double the data URL.
 */
/**
 * Expand a tone bank through the voicing parameters into one oscillator per
 * (tone, unison copy, partial). This is the table the C++ kernel builds too
 * (exo::Synth::expand), and the validator compares the two entry for entry: get a
 * frequency, a gain or a pan wrong here and the two implementations diverge
 * immediately.
 */
export function expandVoices(tones, shape, rate = sampleRate) {
    const copies = clamp(Math.round(shape.unisonVoices), 1, 8);
    const spread = clamp(shape.detuneCents, 0, 100);
    const partials = clamp(Math.round(shape.partials), 0, 16);
    const enrichment = clamp(shape.enrichment, 0, 1);
    const tilt = clamp(shape.partialTilt, 0, 4);
    const width = clamp(shape.width, 0, 1);
    const stereo = copies > 1 && width > 0.001;
    const nyquist = kNyquistFraction * rate;
    const twoPi = 2 * Math.PI;
    const out = [];
    for (let ti = 0; ti < tones.length; ti++) {
        const tone = tones[ti];
        const amp = tone.amplitude / copies;
        for (let v = 0; v < copies; v++) {
            // Cents spread across the copies: -spread .. +spread.
            const offset = copies === 1 ? 0 : ((2 * v) / (copies - 1) - 1) * spread;
            const f0 = tone.frequency * Math.pow(2, offset / 1200);
            // A distinct phase per copy is what makes the copies decorrelated rather
            // than a louder single sine.
            const phase = v * 0.7;
            // Constant-power pan from the copy's position in the spread.
            const pos = copies === 1 ? 0 : ((2 * v) / (copies - 1) - 1);
            const theta = ((pos * width) + 1) * Math.PI / 4;
            for (let k = 1; k <= 1 + partials; k++) {
                const fk = f0 * k;
                // Nothing above Nyquist: an aliased partial is a frequency the chord
                // does not contain, which is the one thing this must not do.
                if (fk >= nyquist)
                    continue;
                const gain = k === 1 ? 1 : enrichment / Math.pow(k, tilt);
                if (gain <= 0)
                    continue;
                out.push({
                    frequency: fk,
                    gain: amp * gain,
                    gainL: stereo ? Math.cos(theta) : 1,
                    gainR: stereo ? Math.sin(theta) : 1,
                    phase: phase,
                    step: twoPi * fk / rate,
                });
            }
        }
    }
    return { voices: out, stereo: stereo };
}
/**
 * The pure per-frame kernel: oscillators and the voicing chain, with no seam
 * crossfade and no peak normalisation. renderChannels() wraps it; the real-time
 * C++ kernel in src/audio/exosynth.cpp implements the same thing, and
 * test/validate-realtime.mjs compares the two sample for sample.
 */
export function renderKernel(tones, shape, frames, rate = sampleRate) {
    const render = Math.max(1, Math.round(frames));
    const table = expandVoices(tones, shape, rate);
    const stereo = table.stereo;
    const tremDepth = clamp(shape.tremoloDepth, 0, 1);
    const tremRate = clamp(shape.tremoloRateHz, 0, 20);
    const left = new Array(render);
    const right = new Array(render);
    for (let i = 0; i < render; i++) {
        left[i] = 0;
        right[i] = 0;
    }
    const twoPi = 2 * Math.PI;
    for (let vi = 0; vi < table.voices.length; vi++) {
        const voice = table.voices[vi];
        const w = twoPi * voice.frequency / rate;
        for (let i = 0; i < render; i++) {
            const s = Math.sin(w * i + voice.phase) * voice.gain;
            left[i] += s * voice.gainL;
            right[i] += s * voice.gainR;
        }
    }
    if (tremRate > 0 && tremDepth > 0) {
        const w = twoPi * tremRate / rate;
        for (let i = 0; i < render; i++) {
            const g = 1 - tremDepth * (0.5 - 0.5 * Math.cos(w * i));
            left[i] *= g;
            right[i] *= g;
        }
    }
    lowpass(left, shape.lowpassHz, rate);
    lowpass(right, shape.lowpassHz, rate);
    reverb(left, right, shape.reverbMix, shape.reverbPreset, rate);
    return { left: left, right: right, stereo: stereo };
}
/**
 * The shaped signal for a whole buffer, made loopable: the tail is crossfaded
 * back into the head, then the result is peak-normalised to `headroom`.
 */
export function renderChannels(tones, shape, seconds, rate = sampleRate) {
    const seam = Math.max(1, Math.round(seamSeconds * rate));
    const total = Math.max(1, Math.round(clampDuration(seconds) * rate));
    const rendered = renderKernel(tones, shape, total + seam, rate);
    const left = rendered.left;
    const right = rendered.right;
    const stereo = rendered.stereo;
    // Crossfade the tail back into the head so the buffer loops seamlessly: the
    // first `seam` samples blend in what the signal was doing past the end.
    const fadeIn = (buf) => {
        for (let i = 0; i < seam; i++) {
            const a = i / seam;
            buf[i] = buf[i] * a + buf[total + i] * (1 - a);
        }
        buf.length = total;
    };
    fadeIn(left);
    fadeIn(right);
    let peak = 0;
    for (let i = 0; i < total; i++) {
        const a = Math.abs(left[i]);
        if (a > peak)
            peak = a;
        const b = Math.abs(right[i]);
        if (b > peak)
            peak = b;
    }
    const scale = peak > 0 ? headroom / peak : 0;
    for (let i = 0; i < total; i++) {
        left[i] *= scale;
        right[i] *= scale;
    }
    return { left, right, channels: stereo ? 2 : 1 };
}
/** Little-endian unsigned 32-bit into `bytes`. */
function writeU32(bytes, value) {
    bytes.push(value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff);
}
/** Little-endian signed 16-bit, clamped - the one place clipping could happen. */
function writeS16(bytes, value) {
    let v = Math.round(value);
    if (v > 32767)
        v = 32767;
    if (v < -32768)
        v = -32768;
    if (v < 0)
        v += 65536;
    bytes.push(v & 0xff, (v >>> 8) & 0xff);
}
function writeAscii(bytes, text) {
    for (let i = 0; i < text.length; i++)
        bytes.push(text.charCodeAt(i) & 0xff);
}
/**
 * Wrap samples as a canonical 44-byte-header RIFF/WAVE PCM file. Samples are
 * floats in [-1, 1] scaled to 16-bit here; pass interleaved frames for stereo.
 */
export function encodeWav(samples, rate = sampleRate, channels = 1) {
    const ch = channels < 1 ? 1 : channels;
    const dataBytes = samples.length * (bitsPerSample / 8);
    const bytes = [];
    writeAscii(bytes, "RIFF");
    writeU32(bytes, 36 + dataBytes);
    writeAscii(bytes, "WAVE");
    writeAscii(bytes, "fmt ");
    writeU32(bytes, 16); // PCM fmt chunk size
    bytes.push(1, 0); // format 1 = PCM
    bytes.push(ch & 0xff, (ch >>> 8) & 0xff);
    writeU32(bytes, rate);
    writeU32(bytes, rate * ch * (bitsPerSample / 8)); // byte rate
    bytes.push((ch * (bitsPerSample / 8)) & 0xff, 0); // block align
    bytes.push(bitsPerSample & 0xff, 0);
    writeAscii(bytes, "data");
    writeU32(bytes, dataBytes);
    for (let i = 0; i < samples.length; i++)
        writeS16(bytes, samples[i] * 32767);
    return bytes;
}
const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
/**
 * Base64 over a byte array. The QML JS engine has no btoa, which is why this
 * exists rather than a one-liner.
 */
export function base64(bytes) {
    let out = "";
    let i = 0;
    for (; i + 2 < bytes.length; i += 3) {
        const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
        out += B64[(n >>> 18) & 63] + B64[(n >>> 12) & 63] + B64[(n >>> 6) & 63] + B64[n & 63];
    }
    const rest = bytes.length - i;
    if (rest === 1) {
        const n = bytes[i] << 16;
        out += B64[(n >>> 18) & 63] + B64[(n >>> 12) & 63] + "==";
    }
    else if (rest === 2) {
        const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
        out += B64[(n >>> 18) & 63] + B64[(n >>> 12) & 63] + B64[(n >>> 6) & 63] + "=";
    }
    return out;
}
/**
 * The buffer plus what it actually turned out to be. The channel count matters
 * to the caller: it is the difference between a shaped, spread render and a
 * plain mono one, and it is cheap to report.
 */
export function wavPacket(tones, shape, seconds, rate = sampleRate) {
    const r = renderChannels(tones, shape, seconds, rate);
    const interleaved = r.channels === 2
        ? (() => {
            const out = new Array(r.left.length * 2);
            for (let i = 0; i < r.left.length; i++) {
                out[i * 2] = r.left[i];
                out[i * 2 + 1] = r.right[i];
            }
            return out;
        })()
        : r.left;
    return {
        url: "data:audio/wav;base64," + base64(encodeWav(interleaved, rate, r.channels)),
        channels: r.channels,
        frames: r.left.length,
    };
}
/** A `data:` URL a MediaPlayer can open without touching the filesystem. */
export function wavDataUrl(tones, shape, seconds, rate = sampleRate) {
    return wavPacket(tones, shape, seconds, rate).url;
}
