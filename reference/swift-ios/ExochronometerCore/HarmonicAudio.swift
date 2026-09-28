import AVFoundation
import Foundation

public struct ToneID: Hashable, Sendable {
    public let timeframe: TimeFrame
    public let divisions: Int
    public let skip: Int
    public let octaves: Int

    public init(timeframe: TimeFrame, divisions: Int, skip: Int = 1, octaves: Int) {
        self.timeframe = timeframe
        self.divisions = divisions
        self.skip = skip
        self.octaves = octaves
    }
}

/// Sums oscillators on the audio thread. UI updates each tone's amplitude per
/// frame; the engine fills buffers continuously.
///
/// The tone *bank* is the instrument's information and is never altered here —
/// every frequency on the bus is a cycle fundamental or a polygon harmonic.
/// A `SynthParams` voicing layer shapes only how that fixed set is rendered:
/// envelope slew, unison/stereo width, optional detune and harmonic
/// enrichment (per-voice, in the render block), plus a global low-pass and
/// reverb (AVAudioUnits in the engine graph). See `SynthParams` for the
/// information-safe vs. information-trading split.
///
/// Cross-platform: uses AVAudioEngine on both iOS and macOS. The iOS
/// AVAudioSession setup is wrapped in `#if os(iOS)` — macOS doesn't
/// need a session.
public final class HarmonicAudio: ObservableObject {
    @Published public private(set) var isRunning: Bool = false

    /// Voicing parameters. Published so SwiftUI controls can bind to it; the
    /// render thread reads a lock-guarded snapshot (`_renderParams`) instead,
    /// and the EQ/reverb units are reconfigured on the main thread.
    @Published public var params: SynthParams = SynthParams() {
        didSet {
            lock.lock(); _renderParams = params; lock.unlock()
            applyEffectParams()
        }
    }

    private static let maxUnison = 3

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()
    private var effectsAttached = false
    private var lastReverbPreset = -1
    private var sampleRate: Double = 44_100

    /// Tremolo phase lives only on the render thread.
    private var tremoloPhase: Double = 0

    /// Flat value type — no heap storage — so copying the bank to the render
    /// thread each block costs one contiguous buffer copy, with no per-tone
    /// ARC/copy-on-write churn on the audio thread.
    private struct Tone {
        let id: ToneID
        let frequency: Double
        var targetAmp: Double = 0
        var smoothedAmp: Double = 0
        // One phase accumulator per unison sub-voice (maxUnison == 3).
        var p0: Double = 0
        var p1: Double = 0
        var p2: Double = 0

        @inline(__always) func phase(_ v: Int) -> Double {
            v == 0 ? p0 : (v == 1 ? p1 : p2)
        }
        @inline(__always) mutating func setPhase(_ v: Int, _ value: Double) {
            if v == 0 { p0 = value } else if v == 1 { p1 = value } else { p2 = value }
        }
    }

    private var tones: [Tone] = []
    private var _volume: Double = 0.5
    private var _renderParams = SynthParams()
    private let lock = NSLock()

    public var volume: Double {
        get { lock.lock(); defer { lock.unlock() }; return _volume }
        set { lock.lock(); _volume = newValue; lock.unlock() }
    }

    public init(scales: [Int] = [23]) {
        let assignments = scales.flatMap { sc in
            TimeFrame.allCases
                .filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: sc) }
        }
        rebuild(assignments: assignments)
    }

    public init(assignments: [ToneAssignment]) {
        rebuild(assignments: assignments)
    }

    public func start() {
        guard !engine.isRunning else { return }
        configureSession()

        let format = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        if !effectsAttached {
            engine.attach(eq)
            engine.attach(reverb)
            effectsAttached = true
        }

        let src = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            return self.fill(buffer: audioBufferList, frameCount: Int(frameCount))
        }
        engine.attach(src)
        // src -> low-pass -> reverb -> mixer. The effects add no pitch class;
        // they soften the timbre and add space.
        engine.connect(src, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        sourceNode = src
        applyEffectParams()

        do {
            try engine.start()
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            print("HarmonicAudio start failed: \(error)")
        }
    }

    public func stop() {
        engine.stop()
        if let src = sourceNode {
            engine.detach(src)
            sourceNode = nil
        }
        DispatchQueue.main.async { self.isRunning = false }
    }

    public func update(amplitudes: [ToneID: Double]) {
        lock.lock()
        for i in 0..<tones.count {
            tones[i].targetAmp = amplitudes[tones[i].id] ?? 0
        }
        lock.unlock()
    }

    /// Rebuild the oscillator bank for a uniform scale set across all
    /// non-minute timeframes. Kept for callers that don't care about
    /// per-timeframe scaling.
    public func reconfigure(scales: [Int]) {
        let assignments = scales.flatMap { sc in
            TimeFrame.allCases
                .filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: sc) }
        }
        rebuild(assignments: assignments)
    }

    /// Rebuild the oscillator bank from an explicit list of per-timeframe
    /// scale assignments. Preserves each tone's amplitude and phase across
    /// the change so audio keeps playing without a click.
    public func reconfigure(assignments: [ToneAssignment]) {
        rebuild(assignments: assignments)
    }

    private func rebuild(assignments: [ToneAssignment]) {
        lock.lock()
        var prior: [ToneID: Tone] = [:]
        for t in tones { prior[t.id] = t }

        let twoPi = 2 * Double.pi
        func make(_ id: ToneID, _ frequency: Double) -> Tone {
            if let old = prior[id] {
                return Tone(
                    id: id, frequency: frequency,
                    targetAmp: old.targetAmp, smoothedAmp: old.smoothedAmp,
                    p0: old.p0, p1: old.p1, p2: old.p2
                )
            }
            // Decorrelated initial phases so unison voices spread in stereo
            // even at detune 0 (golden-ratio offsets avoid re-aligning).
            return Tone(
                id: id, frequency: frequency,
                p0: 0,
                p1: (0.6180339887 * twoPi).truncatingRemainder(dividingBy: twoPi),
                p2: (1.2360679774 * twoPi).truncatingRemainder(dividingBy: twoPi)
            )
        }

        var rebuilt: [Tone] = []
        for entry in assignments {
            let tf = entry.timeframe
            let sc = entry.scale
            let factor = pow(2.0, Double(sc))
            let fundamental = (1.0 / tf.cycleDuration) * factor
            rebuilt.append(make(ToneID(timeframe: tf, divisions: 1, octaves: sc), fundamental))
            for div in 3...8 {
                rebuilt.append(make(
                    ToneID(timeframe: tf, divisions: div, octaves: sc),
                    fundamental * Double(div)
                ))
            }
            // Winding tones ({7/3}, {8/3}) — distinct pitch classes at
            // (n/k)·f, sounded when their path-visit windows arise.
            for shape in GeometryMath.defaultShapes where GeometryMath.oddPart(shape.skip) > 1 {
                rebuilt.append(make(
                    ToneID(timeframe: tf, divisions: shape.divisions, skip: shape.skip, octaves: sc),
                    fundamental * Double(shape.divisions) / Double(shape.skip)
                ))
            }
        }
        tones = rebuilt
        lock.unlock()
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    /// Apply the global (graph) effects from the current params. Main thread.
    private func applyEffectParams() {
        let p = params
        let band = eq.bands[0]
        band.filterType = .lowPass
        band.frequency = Float(min(max(p.lowpassHz, 200), 20_000))
        band.bandwidth = 0.5
        band.bypass = false
        eq.globalGain = 0

        if p.reverbPreset != lastReverbPreset {
            reverb.loadFactoryPreset(Self.reverbPreset(p.reverbPreset))
            lastReverbPreset = p.reverbPreset
        }
        reverb.wetDryMix = Float(min(max(p.reverbMix, 0), 100))
    }

    private static func reverbPreset(_ index: Int) -> AVAudioUnitReverbPreset {
        switch index {
        case 0:  return .smallRoom
        case 1:  return .mediumRoom
        case 2:  return .mediumHall
        case 3:  return .largeHall2
        case 4:  return .cathedral
        default: return .plate
        }
    }

    private func fill(buffer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(buffer)

        lock.lock()
        var localTones = tones
        let localVolume = Float(_volume)
        let p = _renderParams
        lock.unlock()

        let twoPi = 2.0 * Double.pi
        let twoPiOverSR = twoPi / sampleRate
        let nyquist = sampleRate * 0.5

        // ---- Per-block voicing constants -------------------------------
        let voices = min(max(p.unisonVoices, 1), Self.maxUnison)
        let voiceNorm = sqrt(Double(voices))

        // Unison detune (ratio) and equal-power pan per voice.
        var detuneRatio = [Double](repeating: 1, count: voices)
        var panL = [Double](repeating: 0.7071, count: voices)
        var panR = [Double](repeating: 0.7071, count: voices)
        for v in 0..<voices {
            let spread = voices > 1 ? (2.0 * Double(v) / Double(voices - 1) - 1.0) : 0
            let cents = p.detuneCents * spread * 0.5
            detuneRatio[v] = pow(2.0, cents / 1200.0)
            let pan = spread * p.width                     // -width…+width
            let angle = (pan + 1.0) * Double.pi / 4.0      // 0…π/2
            panL[v] = cos(angle)
            panR[v] = sin(angle)
        }

        // Harmonic enrichment partial gains: gain(k) = enrichment / k^tilt.
        let enrichOn = p.enrichment > 0.001
        let maxK = enrichOn ? min(max(p.partials, 1) + 1, 8) : 1
        var partialGain = [Double](repeating: 0, count: maxK + 1)
        if enrichOn {
            for k in 2...maxK {
                partialGain[k] = p.enrichment / pow(Double(k), max(p.partialTilt, 0.1))
            }
        }

        // Envelope slew coefficients (one-pole, per sample).
        let attackCoeff = slewCoeff(ms: p.attackMs)
        let releaseCoeff = slewCoeff(ms: p.releaseMs)

        // Tremolo.
        let tremInc = twoPi * max(p.tremoloRateHz, 0) / sampleRate
        let tremDepth = min(max(p.tremoloDepth, 0), 1)

        let baseGain: Double = localTones.count > 40 ? 0.03 : 0.05
        let gain = Float(baseGain) * localVolume / Float(voiceNorm)

        let isStereo = ablPointer.count >= 2
        let ch0 = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
        let ch1 = isStereo ? ablPointer[1].mData!.assumingMemoryBound(to: Float.self) : ch0

        for frame in 0..<frameCount {
            tremoloPhase += tremInc
            if tremoloPhase > twoPi { tremoloPhase -= twoPi }
            let trem = Float(1.0 - tremDepth * (0.5 - 0.5 * cos(tremoloPhase)))

            var left: Double = 0
            var right: Double = 0

            for i in 0..<localTones.count {
                // Slew toward the geometry target; release carries the tail.
                let target = localTones[i].targetAmp
                var amp = localTones[i].smoothedAmp
                let coeff = target > amp ? attackCoeff : releaseCoeff
                amp += (target - amp) * coeff
                localTones[i].smoothedAmp = amp
                if amp < 0.0003 { continue }

                let freq = localTones[i].frequency
                let baseInc = twoPiOverSR * freq
                for v in 0..<voices {
                    var ph = localTones[i].phase(v)
                    let s1 = sin(ph)
                    var osc = s1
                    if enrichOn {
                        // Partials by Chebyshev recurrence rather than a sin()
                        // per harmonic: sin(kθ) = 2·cosθ·sin((k-1)θ) − sin((k-2)θ).
                        // One cos() per voice regardless of partial count, vs.
                        // up to seven sin() calls — that per-sample blowup is
                        // what overran the render deadline when enrichment was
                        // raised on a full chord. Exact, not an approximation.
                        let c1 = cos(ph)
                        var sPrev = 0.0          // sin(0·θ)
                        var sCurr = s1           // sin(1·θ)
                        var k = 2
                        while k <= maxK {
                            // Don't synthesize partials above Nyquist — they
                            // fold back as inharmonic grit (aliasing). Tones
                            // are sorted by ascending k, so break, not skip.
                            if Double(k) * freq >= nyquist { break }
                            let sK = 2.0 * c1 * sCurr - sPrev   // sin(k·θ)
                            osc += partialGain[k] * sK
                            sPrev = sCurr
                            sCurr = sK
                            k += 1
                        }
                    }
                    let s = osc * amp
                    left += s * panL[v]
                    right += s * panR[v]
                    ph += baseInc * detuneRatio[v]
                    if ph > twoPi { ph -= twoPi }
                    localTones[i].setPhase(v, ph)
                }
            }

            let lOut = max(-1, min(1, Float(left) * gain * trem))
            let rOut = max(-1, min(1, Float(right) * gain * trem))
            if isStereo {
                ch0[frame] = lOut
                ch1[frame] = rOut
            } else {
                ch0[frame] = (lOut + rOut) * 0.5
            }
        }

        // Write phase + smoothed amplitude back. Common case: the bank is
        // unchanged, so write by index (allocation-free). If reconfigure()
        // rebuilt the bank mid-fill the counts/order differ — the id guard
        // skips mismatches, and rebuild() already carried phase across, so a
        // single dropped block is inaudible.
        lock.lock()
        if tones.count == localTones.count {
            for i in 0..<tones.count where tones[i].id == localTones[i].id {
                tones[i].p0 = localTones[i].p0
                tones[i].p1 = localTones[i].p1
                tones[i].p2 = localTones[i].p2
                tones[i].smoothedAmp = localTones[i].smoothedAmp
            }
        }
        lock.unlock()

        return noErr
    }

    /// One-pole slew coefficient for a target reached in `ms` milliseconds.
    private func slewCoeff(ms: Double) -> Double {
        let tau = max(ms, 0) / 1000.0
        if tau <= 0 { return 1 }
        return 1 - exp(-1.0 / (tau * sampleRate))
    }
}
