// Selftest / cross-validation harness for the synthesis kernel.
//
// Links exosynth.cpp with NO Qt at all, so it runs anywhere - no audio device, no
// display, no session. It prints the expanded voice table and the first 512
// frames of each case as JSON; test/validate-realtime.mjs recomputes the same
// cases with the JS kernel (core/wavRender.ts, the one the port's validators
// already cover) and compares them.
//
// Two independent implementations of the same DSP agreeing sample for sample is
// what keeps the real-time path from becoming an unverified second source of
// truth. Auto-gain is off and gains are settled so the comparison is of the
// maths, not of the slew.

#include <cstdio>
#include <string>
#include <vector>

#include "exosynth.h"

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <string>

namespace {

constexpr double kRate = 44100.0;
constexpr int kFrames = 512;

struct Case {
    const char *name;
    std::vector<exo::Tone> tones;
    exo::Shape shape;
};

std::vector<exo::Tone> tones(std::initializer_list<exo::Tone> list) {
    return std::vector<exo::Tone>(list);
}

void printCase(const Case &c, bool first) {
    exo::Synth synth;
    synth.setSampleRate(kRate);
    synth.setAutoGain(false);
    synth.setShape(c.shape);
    synth.setTones(c.tones);
    synth.settle();
    // Snapshot the table BEFORE rendering: rendering advances the phases, so
    // printing afterwards compares a table against a later point in time.
    const std::vector<exo::Voice> voices = synth.voices();

    std::vector<float> buf(std::size_t(kFrames) * 2, 0.0f);
    synth.render(buf.data(), kFrames);

    if (!first) std::printf(",");
    // Emit the inputs too, so the JS side is data-driven rather than repeating
    // these cases by hand and drifting from them.
    std::printf("\n  {\"name\":\"%s\",\n   \"tones\":[", c.name);
    for (std::size_t i = 0; i < c.tones.size(); ++i) {
        std::printf("%s[%.9g,%.9g]", i ? "," : "", c.tones[i].frequency, c.tones[i].amplitude);
    }
    std::printf("],\n   \"shape\":{\"attackMs\":%.9g,\"releaseMs\":%.9g,\"lowpassHz\":%.9g,"
                "\"reverbMix\":%.9g,\"reverbPreset\":%d,\"tremoloRateHz\":%.9g,"
                "\"tremoloDepth\":%.9g,\"width\":%.9g,\"unisonVoices\":%d,"
                "\"detuneCents\":%.9g,\"enrichment\":%.9g,\"partials\":%d,"
                "\"partialTilt\":%.9g}",
                c.shape.attackMs, c.shape.releaseMs, c.shape.lowpassHz, c.shape.reverbMix,
                c.shape.reverbPreset, c.shape.tremoloRateHz, c.shape.tremoloDepth, c.shape.width,
                c.shape.unisonVoices, c.shape.detuneCents, c.shape.enrichment, c.shape.partials,
                c.shape.partialTilt);
    std::printf(",\n   \"voices\":[");
    for (std::size_t i = 0; i < voices.size(); ++i) {
        const exo::Voice &v = voices[i];
        // 15 digits: the voice table is compared numerically, and %.9g truncated
        // it enough to look like a mismatch.
        std::printf("%s\n     {\"f\":%.15g,\"target\":%.15g,\"gl\":%.15g,\"gr\":%.15g,\"phase\":%.15g}",
                    i ? "," : "", v.frequency, v.target, v.gainL, v.gainR, v.phase);
    }
    std::printf("],\n   \"left\":[");
    for (int i = 0; i < kFrames; ++i) {
        std::printf("%s%.9g", i ? "," : "", double(buf[std::size_t(i) * 2]));
    }
    std::printf("],\n   \"right\":[");
    for (int i = 0; i < kFrames; ++i) {
        std::printf("%s%.9g", i ? "," : "", double(buf[std::size_t(i) * 2 + 1]));
    }
    std::printf("]}\n");
}

} // namespace

// ---------------------------------------------------------------------------
// Drift reproduction.
//
// The app does not call the kernel once with a fixed bank: it REBUILDS the bank
// every 500 ms from a geometry that is moving, and plays it through blocks the
// device chooses. This runs exactly that, with the auto-gain on, and prints a
// windowed envelope - so "choppy" becomes a series of numbers that either dips at
// the rebuild rate or does not.
// ---------------------------------------------------------------------------

static std::vector<exo::Tone> bankAt(double t) {
    // A moving instrument: the fundamental sweeps, so each rebuilt bank asks for
    // frequencies slightly different from the one before it.
    const double drift = 1.0 + 0.002 * std::sin(2.0 * M_PI * t / 60.0);
    std::vector<exo::Tone> b;
    for (int i = 0; i < 9; ++i) {
        exo::Tone tone;
        tone.frequency = 110.0 * std::pow(2.0, i / 12.0) * drift;
        tone.amplitude = 1.0 / (1.0 + 0.35 * i);
        b.push_back(tone);
    }
    return b;
}

static int runDrift(int blockFrames, double rebuildSeconds) {
    const double rate = 44100.0;
    exo::Shape s;
    s.attackMs = 150.0; s.releaseMs = 800.0; s.lowpassHz = 2700.0;
    s.reverbMix = 80.0; s.reverbPreset = 4;
    s.tremoloRateHz = 0.0; s.tremoloDepth = 0.0; s.width = 0.35;
    s.unisonVoices = 2; s.detuneCents = 2.2;
    s.enrichment = 0.8; s.partials = 3; s.partialTilt = 0.0;

    exo::Synth synth;
    synth.setSampleRate(rate);
    synth.setShape(s);
    synth.start();
    synth.setTones(bankAt(0.0));

    std::vector<float> buf(std::size_t(blockFrames) * 2, 0.0f);
    const int winFrames = int(rate / 40.0);          // 25 ms windows
    const int total = int(6.0 * rate);
    double nextRebuild = rebuildSeconds;

    std::printf("{\"rate\":%.9g,\"blockFrames\":%d,\"rebuildMs\":%.9g,\"windows\":[",
                rate, blockFrames, rebuildSeconds * 1000.0);
    double acc = 0.0;
    int accN = 0;
    bool first = true;
    for (int done = 0; done < total; done += blockFrames) {
        const double t = double(done) / rate;
        if (t >= nextRebuild) { synth.setTones(bankAt(t)); nextRebuild += rebuildSeconds; }
        synth.render(buf.data(), blockFrames);
        for (int i = 0; i < blockFrames; ++i) {
            const double m = (double(buf[i * 2]) + double(buf[i * 2 + 1])) * 0.5;
            acc += m * m;
            if (++accN >= winFrames) {
                std::printf("%s{\"t\":%.4f,\"rms\":%.6f,\"voices\":%d,\"gain\":%.6f}",
                            first ? "" : ",", t, std::sqrt(acc / accN),
                            int(synth.voices().size()), synth.agcGain());
                first = false;
                acc = 0.0;
                accN = 0;
            }
        }
    }
    std::printf("]}\n");
    return 0;
}

// ---------------------------------------------------------------------------
// Bench: how long does the kernel take to synthesise one second of audio?
//
// This is the number that decides whether a pull-based sink can be fed in time.
// If it exceeds 1.0, readData returns late, the device plays silence while it
// waits, and the result is periodic dropouts - which sound like buffering but are
// actually the synthesis failing to keep up.
// ---------------------------------------------------------------------------
static int runBench(int voiceCount, bool reverb, int blockFrames) {
    const double rate = 44100.0;
    exo::Shape s;
    s.attackMs = 150.0; s.releaseMs = 800.0;
    s.lowpassHz = (reverb ? 2700.0 : 20000.0);
    s.reverbMix = reverb ? 80.0 : 0.0; s.reverbPreset = 4;
    s.tremoloRateHz = 0.0; s.tremoloDepth = 0.0; s.width = 0.35;
    s.unisonVoices = 1; s.detuneCents = 2.2;
    s.enrichment = 0.0; s.partials = 0; s.partialTilt = 0.0;

    std::vector<exo::Tone> tones;
    for (int i = 0; i < voiceCount; ++i) {
        exo::Tone t;
        t.frequency = 110.0 * std::pow(2.0, (i % 36) / 12.0);
        t.amplitude = 1.0 / (1.0 + 0.05 * i);
        tones.push_back(t);
    }

    exo::Synth synth;
    synth.setSampleRate(rate);
    synth.setShape(s);
    synth.start();
    synth.setTones(tones);
    synth.settle();

    std::vector<float> buf(std::size_t(blockFrames) * 2, 0.0f);
    const int totalFrames = int(rate);          // exactly one second
    const auto t0 = std::chrono::steady_clock::now();
    for (int done = 0; done < totalFrames; done += blockFrames) {
        synth.render(buf.data(), blockFrames);
    }
    const auto t1 = std::chrono::steady_clock::now();
    const double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    std::printf("{\"voices\":%d,\"reverb\":%s,\"blockFrames\":%d,\"msPerSecond\":%.1f,\"realTimeFactor\":%.3f,\"voicesCarried\":%d}\n",
                voiceCount, reverb ? "true" : "false", blockFrames, ms, ms / 1000.0,
                int(synth.voices().size()));
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && std::string(argv[1]) == "bench") {
        const bool reverb = argc > 3 && std::string(argv[3]) == "reverb";
        const int block = argc > 4 ? std::atoi(argv[4]) : 512;
        std::printf("[\n");
        for (int v : {1, 4, 16, 72}) {
            std::printf("  ");
            runBench(v, reverb, block);
        }
        std::printf("]\n");
        return 0;
    }
    if (argc > 1 && std::string(argv[1]) == "drift") {
        const int block = argc > 2 ? std::atoi(argv[2]) : 512;
        const double rebuild = argc > 3 ? std::atof(argv[3]) : 0.5;
        return runDrift(block, rebuild);
    }
    std::vector<Case> cases;

    // Bare oscillator: no voicing at all, so this checks the sum itself.
    {
        Case c;
        c.name = "pure";
        c.tones = tones({{220.0, 1.0}});
        exo::Shape s;
        s.unisonVoices = 1;
        s.partials = 0;
        s.enrichment = 0.0;
        s.lowpassHz = 20000.0;
        s.reverbMix = 0.0;
        s.tremoloRateHz = 0.0;
        s.tremoloDepth = 0.0;
        s.width = 0.0;
        c.shape = s;
        cases.push_back(c);
    }

    // The default voicing: unison detune, partials, stereo width, low-pass.
    {
        Case c;
        c.name = "pad";
        c.tones = tones({{220.0, 1.0}, {330.0, 0.5}});
        c.shape = exo::Shape();      // the documented defaults
        c.shape.reverbMix = 0.0;     // reverb is its own case below
        cases.push_back(c);
    }

    // Reverb alone, so its network is compared on its own.
    {
        Case c;
        c.name = "space";
        c.tones = tones({{220.0, 1.0}});
        exo::Shape s;
        s.unisonVoices = 1;
        s.partials = 0;
        s.enrichment = 0.0;
        s.lowpassHz = 20000.0;
        s.reverbMix = 80.0;
        s.reverbPreset = 4;          // Cathedral, matching the defaults
        s.tremoloRateHz = 0.0;
        s.tremoloDepth = 0.0;
        s.width = 0.0;
        c.shape = s;
        cases.push_back(c);
    }

    // Movement: the LFO.
    {
        Case c;
        c.name = "tremolo";
        c.tones = tones({{220.0, 1.0}});
        exo::Shape s;
        s.unisonVoices = 1;
        s.partials = 0;
        s.enrichment = 0.0;
        s.lowpassHz = 20000.0;
        s.reverbMix = 0.0;
        s.tremoloRateHz = 4.0;
        s.tremoloDepth = 1.0;
        s.width = 0.0;
        c.shape = s;
        cases.push_back(c);
    }

    std::printf("{\"rate\":%.9g,\"frames\":%d,\"cases\":[", kRate, kFrames);
    for (std::size_t i = 0; i < cases.size(); ++i) printCase(cases[i], i == 0);
    std::printf("]}\n");
    return 0;
}