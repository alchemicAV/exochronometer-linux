// ExoSynth - the real-time synthesis kernel.
//
// This is the sample generator behind the QAudioSink path: it is pulled by the
// audio thread and fills blocks on demand, so playback never ends, never loops
// and never waits for a render.
//
// Division of labour, which is what keeps this from being a second source of
// truth for the instrument's maths:
//
//   * JavaScript computes the TONE BANK - which frequencies sound and at what
//     amplitude - from the Swift-validated core, once per display tick.
//   * This file only turns that bank into audio: it expands the bank through the
//     voicing parameters and oscillates it at the device rate.
//
// The expansion and the DSP here deliberately mirror core/wavRender.ts step for
// step, because the offline renderer is the one the port's validators cover.
// test/validate-realtime.mjs pulls both kernels through the same inputs and
// compares them sample for sample, so the two cannot drift apart unnoticed.
//
// No Qt types beyond the stdlib: the selftest links this without Qt at all.

#pragma once

#include <cstddef>
#include <vector>

namespace exo {

struct Tone {
    double frequency = 0.0;
    double amplitude = 0.0;
};

// The subset of SynthParams the renderer consumes. Field names and ranges match
// the TS interface; see src/core/synthParams.ts.
struct Shape {
    double attackMs = 150.0;
    double releaseMs = 800.0;
    double lowpassHz = 2700.0;
    double reverbMix = 80.0;
    int reverbPreset = 4;
    double tremoloRateHz = 0.0;
    double tremoloDepth = 0.0;
    double width = 0.35;
    int unisonVoices = 2;
    double detuneCents = 2.2;
    double enrichment = 0.8;
    int partials = 3;
    double partialTilt = 0.0;
};

// One oscillator: a (tone, unison copy, partial) triple with its own phase.
struct Voice {
    double frequency = 0.0;
    double gain = 0.0;      // current, slewed toward `target`
    double target = 0.0;    // what the bank currently asks for
    double phase = 0.0;     // radians, advanced per sample
    double step = 0.0;      // 2*pi*f/sampleRate
    double gainL = 1.0;
    double gainR = 1.0;
};

/// The same constants the offline renderer uses.
constexpr double kHeadroom = 0.9;
constexpr double kNyquistFraction = 0.45;

class Synth {
public:
    void setSampleRate(double rate);
    double sampleRate() const { return m_rate; }
    bool stereo() const { return m_stereo; }

    /// Replace the bank. Voices whose frequency already exists keep their phase,
    /// so a bank change is heard as tones swelling in and out rather than as a
    /// click; anything that is no longer asked for is slewed to silence.
    void setTones(const std::vector<Tone> &tones);

    /// Voicing parameters. Takes effect on the next block.
    void setShape(const Shape &shape);
    Shape shape() const { return m_shape; }

    /// Begin/end. stop() slews every voice to silence over releaseMs and reports
    /// false until the tail has decayed - the caller keeps the device open until
    /// then, so the release is actually heard.
    void start();
    void requestStop();
    bool isSilent() const;

    /// Fill `frames` interleaved STEREO frames. Always stereo, so the device
    /// format never has to be renegotiated when the shape changes.
    void render(float *out, int frames);

    /// The expanded table, for the cross-validation test and for diagnostics.
    const std::vector<Voice> &voices() const { return m_voices; }

    // The two hooks below exist for test/validate-realtime.mjs, which compares
    // this kernel against the JS one sample for sample. Live audio needs neither:
    // gains slew in over attackMs, and the auto-gain tracks the headroom.
    //
    /// Put every voice at its target immediately (skip the swell).
    void settle();
    /// Disable the auto-gain, so the kernel emits its raw sum.
    void setAutoGain(bool on) { m_autoGain = on; }

    /// Peak of the last rendered block, for a level readout. Resets on read.
    double takePeak();

    /// The auto-gain currently applied. Exposed because a gain that swings is
    /// audible as pumping and is invisible in every other readout.
    double agcGain() const { return m_lastAgcGain; }

private:
    void expand(const std::vector<Tone> &tones);
    // Both work on the interleaved buffer in place - see the note in the .cpp
    // about not allocating on the audio thread.
    void applyLowpass(float *out, int frames, int channels, int channel);
    void applyReverb(float *out, int frames, int channels);
    void rebuildReverb();

    double m_rate = 44100.0;
    Shape m_shape;
    bool m_stereo = true;
    bool m_running = false;

    std::vector<Voice> m_voices;
    std::vector<Tone> m_pending;      // bank handed in by setTones
    bool m_dirty = false;
    bool m_stopping = false;

    // per-channel one-pole low-pass state
    double m_lpL = 0.0;
    double m_lpR = 0.0;

    // tremolo
    double m_tremPhase = 0.0;

    // reverb: parallel combs then series allpasses, per channel
    struct Delay {
        std::vector<double> line;
        std::size_t index = 0;
        std::size_t length() const { return line.size(); }
    };
    std::vector<Delay> m_combL, m_combR, m_apL, m_apR;
    int m_builtPreset = -1;
    int m_builtRate = -1;

    bool m_autoGain = true;
    double m_peak = 0.0;
    double m_lastAgcGain = 1.0;        // smoothed peak, for the auto-gain
    double m_postPeak = 0.0;    // peak of the last rendered block, post-gain
};

} // namespace exo