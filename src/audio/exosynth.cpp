#include "exosynth.h"

#include <algorithm>
#include <cmath>

namespace exo {

namespace {
constexpr double kTwoPi = 6.283185307179586;
constexpr int kCombBase[4] = {1557, 1617, 1491, 1422};
constexpr int kAllpassBase[2] = {225, 556};
constexpr double kPresetScale[6] = {0.35, 0.5, 0.7, 0.85, 1.0, 0.6};
constexpr double kPresetFeedback[6] = {0.62, 0.7, 0.76, 0.8, 0.84, 0.72};

double clampd(double v, double lo, double hi) {
    if (!std::isfinite(v)) return lo;
    return v < lo ? lo : v > hi ? hi : v;
}

// Auto-gain: the offline renderer normalises its whole buffer to the headroom,
// which a stream cannot know in advance. This tracks the peak instead, slowly
// enough not to pump, so a dense bank still cannot clip the device.
constexpr double kAgcAttackSeconds = 0.2;
constexpr double kAgcReleaseSeconds = 1.0;
constexpr double kAgcMin = 0.05;
constexpr double kAgcMax = 4.0;
} // namespace

void Synth::setSampleRate(double rate) {
    if (rate <= 0.0) return;
    m_rate = rate;
    m_builtRate = -1;      // delay lengths depend on the rate
}

void Synth::setTones(const std::vector<Tone> &tones) {
    m_pending = tones;
    m_dirty = true;
}

void Synth::setShape(const Shape &shape) {
    if (shape.reverbPreset != m_shape.reverbPreset) m_builtPreset = -1;
    m_shape = shape;
    // A shape change moves the targets; expand() recomputes them from the bank.
    m_dirty = true;
}

void Synth::start() {
    m_running = true;
    m_stopping = false;
    m_peak = 0.0;
}

void Synth::requestStop() {
    m_stopping = true;         // targets drop in the next expand()
    m_dirty = true;
}

bool Synth::isSilent() const {
    for (const Voice &v : m_voices) {
        if (v.gain > 1e-5 || v.target > 1e-5) return false;
    }
    return true;
}

void Synth::expand(const std::vector<Tone> &tones) {
    const Shape &s = m_shape;
    const int voicesPerTone = std::max(1, std::min(8, s.unisonVoices));
    const int partialCount = std::max(0, std::min(16, s.partials));
    const double spread = clampd(s.detuneCents, 0.0, 100.0);
    const double enrichment = clampd(s.enrichment, 0.0, 1.0);
    const double tilt = clampd(s.partialTilt, 0.0, 4.0);
    const double width = clampd(s.width, 0.0, 1.0);
    m_stereo = voicesPerTone > 1 && width > 0.001;

    // Everything currently sounding becomes a candidate to fade out; anything
    // the new bank still asks for is matched below and keeps its phase.
    for (Voice &v : m_voices) v.target = 0.0;
    // Each existing voice may be claimed at most ONCE. Two different partials can
    // land on the same frequency - 220 x 3 and 330 x 2 are both 660 Hz - and
    // those have to SUM, not overwrite each other. Matching by frequency alone
    // silently merged them: 14 voices where 16 were asked for, at half level.
    std::vector<char> claimed(m_voices.size(), 0);

    if (!m_stopping) {
        for (const Tone &tone : tones) {
            const double amp = tone.amplitude / voicesPerTone;
            for (int v = 0; v < voicesPerTone; ++v) {
                const double offset = voicesPerTone == 1
                    ? 0.0
                    : ((2.0 * v) / (voicesPerTone - 1) - 1.0) * spread;
                const double f0 = tone.frequency * std::pow(2.0, offset / 1200.0);
                const double pos = voicesPerTone == 1
                    ? 0.0
                    : ((2.0 * v) / (voicesPerTone - 1) - 1.0);
                const double theta = ((pos * width) + 1.0) * M_PI / 4.0;
                const double gl = m_stereo ? std::cos(theta) : 1.0;
                const double gr = m_stereo ? std::sin(theta) : 1.0;
                // (m_stereo is false for a single copy or a zero width, in which
                // case both channels carry the same signal.)

                for (int k = 1; k <= 1 + partialCount; ++k) {
                    const double fk = f0 * k;
                    // Nothing above Nyquist - an aliased partial is a frequency
                    // the chord does not contain.
                    if (fk >= kNyquistFraction * m_rate) continue;
                    const double g = (k == 1) ? 1.0 : enrichment / std::pow(double(k), tilt);
                    if (g <= 0.0) continue;
                    const double target = amp * g;

                    // Retune the NEAREST unclaimed voice within a tolerance
                    // rather than demanding an exact frequency. The bank is
                    // rebuilt from a MOVING geometry, so every voice comes back
                    // slightly differently tuned; an exact (0.01 Hz) match
                    // rejected all of them and treated each rebuild as a whole
                    // new bank. Measured consequence: a 72-voice bank grew to 504
                    // voices, each rebuild re-swelled from zero, and the envelope
                    // swung 3.5x peak-to-trough at exactly the rebuild rate -
                    // the choppy, pumping artefact.
                    //
                    // 2% of the frequency is far looser than any drift between
                    // two rebuilds and far tighter than the spacing between
                    // distinct partials, so a drift glides and a new partial
                    // still gets its own voice.
                    const double tolerance = fk * 0.02;
                    std::size_t best = m_voices.size();
                    double bestDistance = tolerance;
                    for (std::size_t ei = 0; ei < m_voices.size(); ++ei) {
                        if (claimed[ei]) continue;
                        const double distance = std::fabs(m_voices[ei].frequency - fk);
                        if (distance < bestDistance) {
                            bestDistance = distance;
                            best = ei;
                        }
                    }

                    bool matched = false;
                    if (best < m_voices.size()) {
                        Voice &existing = m_voices[best];
                        // Retune in place: the phase carries on, so the pitch
                        // glides to the new value instead of clicking.
                        existing.frequency = fk;
                        existing.step = kTwoPi * fk / m_rate;
                        existing.target = target;
                        existing.gainL = gl;
                        existing.gainR = gr;
                        claimed[best] = 1;
                        matched = true;
                    }
                    if (matched) continue;

                    Voice voice;
                    voice.frequency = fk;
                    voice.step = kTwoPi * fk / m_rate;
                    voice.target = target;
                    // Start silent so a new tone swells in rather than clicking.
                    voice.gain = 0.0;
                    // A distinct phase per copy is what makes the copies
                    // decorrelated instead of a louder single sine.
                    voice.phase = std::fmod(v * 0.7, kTwoPi);
                    voice.gainL = gl;
                    voice.gainR = gr;
                    m_voices.push_back(voice);
                    // keep `claimed` the same length as m_voices: indexing it must
                    // stay in range while voices are being appended
                    claimed.push_back(1);
                }
            }
        }
    }

    // Retire what is no longer wanted AND has finished fading, every rebuild -
    // not only once the table passes a cap. A voice with a target of zero still
    // has to finish its release, so the gain test is what keeps the fade intact;
    // but leaving the corpse behind afterwards is what let the table accumulate
    // several rebuilds' worth of dead oscillators.
    if (!m_stopping) {
        std::size_t keep = 0;
        for (std::size_t i = 0; i < m_voices.size(); ++i) {
            if (m_voices[i].target > 0.0 || m_voices[i].gain > 1e-5) {
                if (keep != i) m_voices[keep] = m_voices[i];
                ++keep;
            }
        }
        m_voices.resize(keep);
    }

    // Runaway guard only: reaching this means the matching above failed to
    // identify voices that were really the same, which is a bug, not a state.
    if (m_voices.size() > 512) {
        std::vector<Voice> kept;
        kept.reserve(m_voices.size());
        for (const Voice &v : m_voices) {
            if (v.target > 0.0 || v.gain > 1e-5) kept.push_back(v);
        }
        m_voices.swap(kept);
    }
}

void Synth::rebuildReverb() {
    const int preset = std::max(0, std::min(5, m_shape.reverbPreset));
    const double scale = kPresetScale[preset] * (m_rate / 44100.0);

    m_combL.clear(); m_combR.clear(); m_apL.clear(); m_apR.clear();
    for (int i = 0; i < 4; ++i) {
        m_combL.push_back(Delay());
        m_combR.push_back(Delay());
        m_combL.back().line.assign(std::max<std::size_t>(1, std::size_t(kCombBase[i] * scale)), 0.0);
        m_combR.back().line.assign(std::max<std::size_t>(1, std::size_t(kCombBase[i] * scale) + std::size_t(23 * scale) + 7), 0.0);
    }
    for (int i = 0; i < 2; ++i) {
        m_apL.push_back(Delay());
        m_apR.push_back(Delay());
        m_apL.back().line.assign(std::max<std::size_t>(1, std::size_t(kAllpassBase[i] * scale)), 0.0);
        m_apR.back().line.assign(std::max<std::size_t>(1, std::size_t(kAllpassBase[i] * scale) + std::size_t(23 * scale) + 7), 0.0);
    }
    m_builtPreset = preset;
    m_builtRate = int(m_rate);
}

// All of the DSP below reads and writes the INTERLEAVED buffer directly. Nothing
// here allocates: this runs on the audio thread, where a malloc is a dropout.
void Synth::applyLowpass(float *out, int frames, int channels, int channel) {
    const double fc = clampd(m_shape.lowpassHz, 20.0, 0.45 * m_rate);
    if (fc >= 0.449 * m_rate) return;                 // effectively open
    const double alpha = 1.0 - std::exp(-kTwoPi * fc / m_rate);
    double state = (channel == 0) ? m_lpL : m_lpR;
    for (int i = 0; i < frames; ++i) {
        const int at = i * channels + channel;
        state += alpha * (double(out[at]) - state);
        out[at] = float(state);
    }
    if (channel == 0) m_lpL = state; else m_lpR = state;
}

void Synth::applyReverb(float *out, int frames, int channels) {
    const double wet = clampd(m_shape.reverbMix / 100.0, 0.0, 1.0);
    if (wet <= 0.0) return;
    if (m_builtPreset != m_shape.reverbPreset || m_builtRate != int(m_rate)) rebuildReverb();

    const int preset = std::max(0, std::min(5, m_shape.reverbPreset));
    const double fb = kPresetFeedback[preset];

    // One sample at a time across all combs, then all allpasses, then the blend -
    // the same order the offline renderer uses, with the delay lines as state
    // instead of a buffer pass.
    for (int c = 0; c < channels; ++c) {
        std::vector<Delay> &combs = (c == 0) ? m_combL : m_combR;
        std::vector<Delay> &aps = (c == 0) ? m_apL : m_apR;

        for (int i = 0; i < frames; ++i) {
            const int at = i * channels + c;
            const double dry = double(out[at]);
            double acc = 0.0;

            for (Delay &d : combs) {
                const double delayed = d.line[d.index];
                d.line[d.index] = dry + delayed * fb;
                acc += delayed * 0.25;
                d.index = (d.index + 1 == d.length()) ? 0 : d.index + 1;
            }
            for (Delay &d : aps) {
                const double delayed = d.line[d.index];
                d.line[d.index] = acc + delayed * 0.5;
                acc = delayed - acc * 0.5;
                d.index = (d.index + 1 == d.length()) ? 0 : d.index + 1;
            }
            out[at] = float(dry * (1.0 - wet) + acc * wet);
        }
    }
}

void Synth::render(float *out, int frames) {
    if (frames <= 0) return;
    if (m_dirty) {
        expand(m_pending);
        m_dirty = false;
    }

    // Always stereo: the device format is chosen once at start, and a width
    // change mid-stream must not change the channel count. With no spread the two
    // channels are simply identical.
    const int channels = 2;
    for (int i = 0; i < frames * channels; ++i) out[i] = 0.0f;
    if (m_voices.empty()) return;

    // Gain slew, once per block: the original's per-tone amplitude slew, which
    // is what turns note on/off into a swell and mutes a bank change.
    const double blockSeconds = double(frames) / m_rate;
    for (Voice &v : m_voices) {
        if (v.gain == v.target) continue;
        const double ms = (v.target > v.gain) ? m_shape.attackMs : m_shape.releaseMs;
        if (ms <= 0.0) {
            v.gain = v.target;
            continue;
        }
        const double stepAmount = blockSeconds / (ms / 1000.0);
        v.gain = (v.gain < v.target) ? std::min(v.target, v.gain + stepAmount)
                                     : std::max(v.target, v.gain - stepAmount);
    }

    const bool tremolo = m_shape.tremoloRateHz > 0.0 && m_shape.tremoloDepth > 0.0;
    const double tremStep = kTwoPi * clampd(m_shape.tremoloRateHz, 0.0, 20.0) / m_rate;
    const double tremDepth = clampd(m_shape.tremoloDepth, 0.0, 1.0);

    for (int i = 0; i < frames; ++i) {
        double l = 0.0, r = 0.0;
        for (Voice &v : m_voices) {
            if (v.gain > 0.0) {
                const double s = std::sin(v.phase) * v.gain;
                l += s * v.gainL;
                r += s * v.gainR;
            }
            v.phase += v.step;
            if (v.phase > kTwoPi) v.phase -= kTwoPi;
        }

        if (tremolo) {
            const double g = 1.0 - tremDepth * (0.5 - 0.5 * std::cos(m_tremPhase));
            l *= g;
            r *= g;
            m_tremPhase += tremStep;
            if (m_tremPhase > kTwoPi) m_tremPhase -= kTwoPi;
        }

        out[i * channels] = float(l);
        out[i * channels + 1] = float(r);
    }

    applyLowpass(out, frames, channels, 0);
    applyLowpass(out, frames, channels, 1);
    applyReverb(out, frames, channels);

    // Auto-gain toward the headroom (see the note in the anonymous namespace).
    double blockPeak = 0.0;
    for (int i = 0; i < frames * channels; ++i) {
        const double a = std::fabs(double(out[i]));
        if (a > blockPeak) blockPeak = a;
    }
    const double tau = (blockPeak > m_peak) ? kAgcAttackSeconds : kAgcReleaseSeconds;
    const double k = 1.0 - std::exp(-blockSeconds / tau);
    m_peak += (blockPeak - m_peak) * k;

    double gain = 1.0;
    if (m_autoGain && m_peak > 1e-6) gain = clampd(kHeadroom / m_peak, kAgcMin, kAgcMax);
    m_lastAgcGain = gain;
    double after = 0.0;
    for (int i = 0; i < frames * channels; ++i) {
        const float v = float(out[i] * gain);
        out[i] = v;
        const double a = std::fabs(double(v));
        if (a > after) after = a;
    }
    m_postPeak = std::max(m_postPeak, after);
}

void Synth::settle() {
    // Apply any pending bank first, so the table is final before it is levelled.
    if (m_dirty) {
        expand(m_pending);
        m_dirty = false;
    }
    for (Voice &v : m_voices) v.gain = v.target;
}

double Synth::takePeak() {
    const double out = m_postPeak;
    m_postPeak = 0.0;
    return out;
}

} // namespace exo