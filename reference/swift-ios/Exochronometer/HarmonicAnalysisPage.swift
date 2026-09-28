import SwiftUI
import ExochronometerCore

enum ScaleMode: String {
    case lo
    case hi
    case merged

    /// Per-timeframe scale assignments. In merged mode each timeframe gets
    /// the smallest scale that puts its fundamental + overtones inside
    /// audible — hour can stay at 23, day/qtr need 26, moon/year need 29.
    var assignments: [ToneAssignment] {
        switch self {
        case .lo:
            return TimeFrame.allCases
                .filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: 23) }
        case .hi:
            return TimeFrame.allCases
                .filter { $0 != .minute }
                .map { ToneAssignment(timeframe: $0, scale: 26) }
        case .merged:
            return [
                ToneAssignment(timeframe: .hour,        scale: 23),
                ToneAssignment(timeframe: .day,         scale: 26),
                ToneAssignment(timeframe: .quarterMoon, scale: 28),
                ToneAssignment(timeframe: .moon,        scale: 29),
                ToneAssignment(timeframe: .year,        scale: 29),
            ]
        }
    }

    var label: String {
        switch self {
        case .lo:     return "2^23"
        case .hi:     return "2^26"
        case .merged: return "MERGED"
        }
    }

    var isActive: Bool { self != .lo }
    var isMerged: Bool { self == .merged }

    var next: ScaleMode {
        switch self {
        case .lo:     return .hi
        case .hi:     return .merged
        case .merged: return .lo
        }
    }

    var minFreqHz: Double {
        switch self {
        case .lo:     return 0.1
        case .hi:     return 1
        case .merged: return 15   // year fundamental ~17 Hz; cut empty sub-15 Hz band
        }
    }

    var maxFreqHz: Double {
        switch self {
        case .lo:     return 50_000
        case .hi:     return 200_000
        case .merged: return 50_000
        }
    }
}

struct HarmonicAnalysisPage: View {
    @StateObject private var audio = HarmonicAudio(assignments: ScaleMode.merged.assignments)
    @AppStorage("globalFundamentalsOff") private var fundamentalsOff: Bool = true
    @AppStorage("exo.ios.synth.v1") private var synthData = Data()
    @State private var scaleMode: ScaleMode = .merged
    @State private var volume: Double = 0.5
    @State private var excludedTimeframes: Set<TimeFrame> = []
    @State private var useLogScale: Bool = true
    @State private var showSynthOptions: Bool = false

    private let orderedTimeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]

    var body: some View {
        VStack(spacing: 10) {
            header
            controlsRow
                .padding(.horizontal, 20)
            timeframeFilterRow
                .padding(.horizontal, 20)
            volumeRow
                .padding(.horizontal, 20)

            // Synth options take the spectrum's place when toggled on; the
            // composite waveform below stays put in both modes.
            if showSynthOptions {
                SynthOptionsView(params: $audio.params)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
            }

            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let allActive = activeTones(at: context.date)
                let active = allActive.filter { !excludedTimeframes.contains($0.timeframe) }
                let displayedTones = fundamentalsOff
                    ? active.filter { $0.divisions != 1 }
                    : active

                VStack(spacing: 8) {
                    if !showSynthOptions {
                        VerticalSpectrum(
                            tones: displayedTones,
                            minFreqHz: scaleMode.minFreqHz,
                            maxFreqHz: scaleMode.maxFreqHz,
                            showScaleSuffix: scaleMode.isMerged,
                            useLogScale: useLogScale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                    }

                    OscilloscopeView(tones: displayedTones)
                        .frame(height: 90)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .onChange(of: context.date) { _, _ in
                    pushAudio(active: active)
                }
                .onAppear {
                    pushAudio(active: active)
                    audio.volume = volume
                }
            }
        }
        .padding(.top, 8)
        .onAppear {
            // Restore the saved synth voicing before any audio plays.
            if let decoded = try? JSONDecoder().decode(SynthParams.self, from: synthData) {
                audio.params = decoded
            }
        }
        .onChange(of: audio.params) { _, p in
            if let data = try? JSONEncoder().encode(p) { synthData = data }
        }
        .onDisappear {
            audio.stop()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HARMONIC SPECTRUM")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
            Text(headerSubtitle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var headerSubtitle: String {
        let scaleText: String
        switch scaleMode {
        case .lo:     scaleText = "× 2^23"
        case .hi:     scaleText = "× 2^26"
        case .merged: scaleText = "HR:23 · DY:26 · QM:28 · MN/YR:29"
        }
        return "\(scaleText)  ·  minute excluded"
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            toggleButton(
                label: audio.isRunning ? "AUDIO ON" : "AUDIO OFF",
                active: audio.isRunning
            ) {
                if audio.isRunning {
                    audio.stop()
                } else {
                    audio.start()
                }
            }

            toggleButton(
                label: scaleMode.label,
                active: scaleMode.isActive
            ) {
                scaleMode = scaleMode.next
                audio.reconfigure(assignments: scaleMode.assignments)
            }

            toggleButton(
                label: useLogScale ? "LOG" : "LINEAR",
                active: !useLogScale
            ) {
                useLogScale.toggle()
            }

            toggleButton(
                label: "SYNTH",
                active: showSynthOptions
            ) {
                showSynthOptions.toggle()
            }

            Spacer()
        }
    }

    private var timeframeFilterRow: some View {
        HStack(spacing: 6) {
            ForEach(orderedTimeframes, id: \.self) { tf in
                let isExcluded = excludedTimeframes.contains(tf)
                Button {
                    if isExcluded {
                        excludedTimeframes.remove(tf)
                    } else {
                        excludedTimeframes.insert(tf)
                    }
                } label: {
                    Text(shortTimeframeLabel(tf))
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white.opacity(isExcluded ? 0.25 : 0.8))
                        .background(Capsule().fill(.clear))
                        .overlay(
                            Capsule().stroke(.white.opacity(isExcluded ? 0.12 : 0.4), lineWidth: 0.5)
                        )
                }
            }
            Spacer()
        }
    }

    private func shortTimeframeLabel(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON"
        case .quarterMoon: return "QTR"
        case .day:         return "DAY"
        case .hour:        return "HOUR"
        case .minute:      return "MIN"
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Text("VOL")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            MiniSlider(value: $volume, range: 0...1)
                .onChange(of: volume) { _, new in
                    audio.volume = new
                }
            Text("\(Int(volume * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func toggleButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(active ? .black : .white.opacity(0.7))
                .background(
                    Capsule().fill(active ? Color.white : .clear)
                )
                .overlay(
                    Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5)
                )
        }
    }

    private func activeTones(at date: Date) -> [SpectrumTone] {
        var out: [SpectrumTone] = []
        for entry in scaleMode.assignments {
            let tf = entry.timeframe
            let sc = entry.scale
            let factor = pow(2.0, Double(sc))
            let fundamental = (1.0 / tf.cycleDuration) * factor
            let degree = tf.degree(at: date)
            let nextDegree = degree + 1.0

            out.append(SpectrumTone(
                timeframe: tf,
                divisions: 1,
                octaves: sc,
                frequency: fundamental,
                amplitude: 1.0,
                state: .peak
            ))

            for div in 3...8 {
                let amp = FadeMath.shapeOpacity(currentDegree: degree, divisions: div)
                if amp > 0.01 {
                    let nextAmp = FadeMath.shapeOpacity(currentDegree: nextDegree, divisions: div)
                    out.append(SpectrumTone(
                        timeframe: tf,
                        divisions: div,
                        octaves: sc,
                        frequency: fundamental * Double(div),
                        amplitude: amp,
                        state: toneState(amp: amp, nextAmp: nextAmp)
                    ))
                }
            }

            // Winding tones ({7/3}, {8/3}) — distinct pitch classes with
            // winding-aware activation (see HarmonicAnalysis.activeTones).
            let state = FadeMath.TimeframeState(timeframe: tf, date: date)
            let nextDate = date.addingTimeInterval(tf.cycleDuration / 360.0)
            let nextState = FadeMath.TimeframeState(timeframe: tf, date: nextDate)
            for shape in GeometryMath.defaultShapes where GeometryMath.oddPart(shape.skip) > 1 {
                var amp = 0.0
                var nextAmp = 0.0
                for vertex in 0..<shape.divisions {
                    amp = max(amp, FadeMath.nodeActivation(shape: shape, vertexIndex: vertex, state: state))
                    nextAmp = max(nextAmp, FadeMath.nodeActivation(shape: shape, vertexIndex: vertex, state: nextState))
                }
                if amp > 0.01 {
                    out.append(SpectrumTone(
                        timeframe: tf,
                        divisions: shape.divisions,
                        skip: shape.skip,
                        octaves: sc,
                        frequency: fundamental * Double(shape.divisions) / Double(shape.skip),
                        amplitude: amp,
                        state: toneState(amp: amp, nextAmp: nextAmp)
                    ))
                }
            }
        }
        return out
    }

    private func toneState(amp: Double, nextAmp: Double) -> ToneState {
        if amp > 0.95 && abs(nextAmp - amp) < 0.02 {
            return .peak
        } else if nextAmp > amp {
            return .waxing
        } else if nextAmp < amp {
            return .waning
        } else {
            return .peak
        }
    }

    private func pushAudio(active: [SpectrumTone]) {
        guard audio.isRunning else { return }
        var amps: [ToneID: Double] = [:]
        for tone in active {
            if fundamentalsOff && tone.divisions == 1 { continue }
            let id = ToneID(timeframe: tone.timeframe, divisions: tone.divisions, skip: tone.skip, octaves: tone.octaves)
            amps[id] = tone.amplitude
        }
        audio.update(amplitudes: amps)
    }
}

enum ToneState {
    case waxing, peak, waning

    var label: String {
        switch self {
        case .waxing: return "WAXING"
        case .peak:   return "PEAK"
        case .waning: return "WANING"
        }
    }
}

struct SpectrumTone: Identifiable {
    let timeframe: TimeFrame
    let divisions: Int
    var skip: Int = 1
    let octaves: Int
    let frequency: Double
    let amplitude: Double
    let state: ToneState

    var id: String { "\(timeframe.rawValue)-\(divisions)/\(skip)-\(octaves)" }
    var isFundamental: Bool { divisions == 1 }
    /// "7" for integer harmonics, "7/3" for winding tones.
    var divisionLabel: String { skip == 1 ? "\(divisions)" : "\(divisions)/\(skip)" }
}

private func compactTimeframeName(_ tf: TimeFrame) -> String {
    switch tf {
    case .year:        return "YEAR"
    case .moon:        return "MOON"
    case .quarterMoon: return "QTR"
    case .day:         return "DAY"
    case .hour:        return "HOUR"
    case .minute:      return "MIN"
    }
}

private func decadeValues(min: Double, max: Double) -> [Double] {
    let hi = log10(max)
    var values: [Double] = []
    var n = Int(floor(log10(min)))
    while pow(10.0, Double(n)) < min - 1e-12 { n += 1 }
    while Double(n) <= hi + 1e-12 {
        values.append(pow(10.0, Double(n)))
        n += 1
    }
    return values
}

private func decadeLabel(_ value: Double) -> String {
    if value >= 1_000_000 { return "\(Int(value / 1_000_000))M" }
    if value >= 1_000     { return "\(Int(value / 1_000))k" }
    if value >= 1         { return "\(Int(value))" }
    return String(format: "%g", value)
}

private struct MiniSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let thumbSize: CGFloat = 12
    private let trackHeight: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let halfThumb = thumbSize / 2
            let usable = max(0, width - thumbSize)
            let span = range.upperBound - range.lowerBound
            let normalized = span == 0 ? 0 : (value - range.lowerBound) / span
            let thumbCenter = halfThumb + CGFloat(normalized) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(width: thumbCenter, height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbCenter - halfThumb)
            }
            .frame(width: width, height: thumbSize, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = max(halfThumb, min(width - halfThumb, drag.location.x))
                        let pct = usable > 0 ? (x - halfThumb) / usable : 0
                        value = range.lowerBound + Double(pct) * span
                    }
            )
        }
        .frame(height: thumbSize)
    }
}

private struct VerticalSpectrum: View {
    let tones: [SpectrumTone]
    let minFreqHz: Double
    let maxFreqHz: Double
    let showScaleSuffix: Bool
    let useLogScale: Bool

    /// In linear mode the 20k-200k range eats most of the chart and
    /// shows nothing — clip to the audible ceiling.
    private var effectiveMaxFreqHz: Double {
        useLogScale ? maxFreqHz : min(maxFreqHz, 20_000)
    }

    var body: some View {
        Canvas { ctx, size in
            drawAll(in: &ctx, size: size)
        }
    }

    private func drawAll(in ctx: inout GraphicsContext, size: CGSize) {
        let logRange = log10(effectiveMaxFreqHz) - log10(minFreqHz)
        let linearRange = effectiveMaxFreqHz - minFreqHz
        let activeRange = useLogScale ? logRange : linearRange
        guard activeRange > 0 else { return }

        let axisWidth: CGFloat = 38
        let baselineX: CGFloat = axisWidth + 6
        let labelX: CGFloat = axisWidth + 6 + 140 + 8
        let maxBarWidth: CGFloat = 140
        let ticks = useLogScale
            ? decadeValues(min: minFreqHz, max: effectiveMaxFreqHz)
            : linearTickValues(min: minFreqHz, max: effectiveMaxFreqHz, count: 6)

        drawAudibleBand(in: &ctx, size: size, baselineX: baselineX)
        drawGrid(in: &ctx, size: size, baselineX: baselineX, ticks: ticks)
        drawAxisLabels(in: &ctx, size: size, ticks: ticks)
        drawTones(
            in: &ctx,
            size: size,
            baselineX: baselineX,
            maxBarWidth: maxBarWidth,
            labelX: labelX
        )
    }

    private func mapY(_ freq: Double, height: CGFloat) -> CGFloat {
        if useLogScale {
            let frac = (log10(freq) - log10(minFreqHz)) / (log10(effectiveMaxFreqHz) - log10(minFreqHz))
            return height * (1.0 - CGFloat(frac))
        } else {
            let frac = (freq - minFreqHz) / (effectiveMaxFreqHz - minFreqHz)
            return height * (1.0 - CGFloat(frac))
        }
    }

    private func drawAudibleBand(in ctx: inout GraphicsContext, size: CGSize, baselineX: CGFloat) {
        let yLo = mapY(20, height: size.height)
        let yHi = mapY(20_000, height: size.height)
        let band = CGRect(x: baselineX, y: yHi, width: size.width - baselineX, height: yLo - yHi)
        ctx.fill(Path(band), with: .color(.white.opacity(0.04)))
    }

    private func drawGrid(in ctx: inout GraphicsContext, size: CGSize, baselineX: CGFloat, ticks: [Double]) {
        for d in ticks {
            let y = mapY(d, height: size.height)
            var p = Path()
            p.move(to: CGPoint(x: baselineX, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
        }
        var spine = Path()
        spine.move(to: CGPoint(x: baselineX, y: 0))
        spine.addLine(to: CGPoint(x: baselineX, y: size.height))
        ctx.stroke(spine, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
    }

    private func drawAxisLabels(in ctx: inout GraphicsContext, size: CGSize, ticks: [Double]) {
        for (i, d) in ticks.enumerated() {
            let y = mapY(d, height: size.height)
            let label = i == 0 ? "\(decadeLabel(d)) Hz" : decadeLabel(d)
            let text = Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            ctx.draw(text, at: CGPoint(x: 18, y: y), anchor: .center)
        }
    }

    private func linearTickValues(min: Double, max: Double, count: Int) -> [Double] {
        let n = Swift.max(2, count)
        let step = (max - min) / Double(n - 1)
        return (0..<n).map { min + Double($0) * step }
    }

    private func drawTones(
        in ctx: inout GraphicsContext,
        size: CGSize,
        baselineX: CGFloat,
        maxBarWidth: CGFloat,
        labelX: CGFloat
    ) {
        for tone in tones {
            guard tone.frequency >= minFreqHz, tone.frequency <= effectiveMaxFreqHz else { continue }
            let y = mapY(tone.frequency, height: size.height)
            let length = maxBarWidth * CGFloat(tone.amplitude)

            var bar = Path()
            bar.move(to: CGPoint(x: baselineX, y: y))
            bar.addLine(to: CGPoint(x: baselineX + length, y: y))

            let color: Color = tone.isFundamental ? .white : .white.opacity(0.85)
            let lineWidth: CGFloat = tone.isFundamental ? 1.5 : 0.8
            ctx.stroke(bar, with: .color(color), lineWidth: lineWidth)

            let dotR = 1.5 + tone.amplitude * 2.0
            let dot = CGRect(
                x: baselineX + length - dotR,
                y: y - dotR,
                width: dotR * 2,
                height: dotR * 2
            )
            ctx.fill(Path(ellipseIn: dot), with: .color(color))

            let name = compactTimeframeName(tone.timeframe)
            let prefix = tone.isFundamental ? name : "\(name)×\(tone.divisionLabel)"
            let scaleSuffix = showScaleSuffix ? " @\(tone.octaves)" : ""
            let freqLabel = FrequencyMath.format(tone.frequency)
            let stateSuffix = tone.isFundamental ? "" : "  ·  \(tone.state.label)"
            let label = Text("\(prefix)\(scaleSuffix)  ·  \(freqLabel)\(stateSuffix)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(tone.isFundamental ? 0.75 : 0.55))
            ctx.draw(label, at: CGPoint(x: labelX, y: y), anchor: .leading)
        }
    }
}

private struct OscilloscopeView: View {
    let tones: [SpectrumTone]
    private let windowSeconds: Double = 0.030

    var body: some View {
        Canvas { ctx, size in
            drawScope(in: &ctx, size: size)
        }
        .overlay(alignment: .topLeading) {
            Text("COMPOSITE WAVEFORM")
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 4)
                .padding(.top, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func drawScope(in ctx: inout GraphicsContext, size: CGSize) {
        var center = Path()
        center.move(to: CGPoint(x: 0, y: size.height / 2))
        center.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.stroke(center, with: .color(.white.opacity(0.1)), lineWidth: 0.5)

        guard !tones.isEmpty else { return }

        let samples = Int(size.width)
        var values: [Double] = Array(repeating: 0, count: samples)
        var peak: Double = 0

        for i in 0..<samples {
            let t = Double(i) / Double(samples) * windowSeconds
            var s: Double = 0
            for tone in tones {
                s += sin(2.0 * .pi * tone.frequency * t) * tone.amplitude
            }
            values[i] = s
            if abs(s) > peak { peak = abs(s) }
        }

        guard peak > 0 else { return }
        let scale = (size.height / 2 - 4) / peak

        var wave = Path()
        for i in 0..<samples {
            let x = CGFloat(i)
            let y = size.height / 2 - CGFloat(values[i] * scale)
            if i == 0 {
                wave.move(to: CGPoint(x: x, y: y))
            } else {
                wave.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(wave, with: .color(.white.opacity(0.85)), lineWidth: 1)
    }
}

/// Harmonic-synth voicing controls, shown in place of the spectrum graph
/// when SYNTH is toggled on. Binds straight to the live engine's `params`
/// (`HarmonicAudio` applies them on the audio thread), so edits are heard
/// immediately and the composite-waveform scope below keeps updating.
private struct SynthOptionsView: View {
    @Binding var params: SynthParams

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("ENVELOPE") {
                    slider("ATTACK", $params.attackMs, 0...1000) { "\(Int($0))ms" }
                    slider("RELEASE", $params.releaseMs, 0...3000) { "\(Int($0))ms" }
                }
                section("TONE") {
                    slider("LOW-PASS", $params.lowpassHz, 500...20000) { freqLabel($0) }
                }
                section("SPACE") {
                    reverbRow
                    slider("MIX", $params.reverbMix, 0...100) { "\(Int($0))%" }
                }
                section("MOVEMENT") {
                    slider("TREMOLO", $params.tremoloRateHz, 0...4) { String(format: "%.2fHz", $0) }
                    slider("DEPTH", $params.tremoloDepth, 0...1) { "\(Int($0 * 100))%" }
                    slider("WIDTH", $params.width, 0...1) { "\(Int($0 * 100))%" }
                }
                timbreSection
            }
            .padding(.vertical, 4)
        }
    }

    /// The information-trading knobs — detune/enrichment add or blur pitch
    /// classes the chord didn't contain. Boxed + orange to flag the trade.
    private var timbreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TIMBRE · ALTERS THE CHORD")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.orange.opacity(0.9))
                Spacer()
                Button {
                    params.resetTimbre()
                } label: {
                    Text("RESET")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.orange)
                }
            }
            stepper("UNISON", value: $params.unisonVoices, in: 1...3)
            slider("DETUNE", $params.detuneCents, 0...25) { String(format: "%.1f¢", $0) }
            slider("ENRICH", $params.enrichment, 0...1) { "\(Int($0 * 100))%" }
            stepper("PARTIALS", value: $params.partials, in: 2...6)
            slider("TILT", $params.partialTilt, 0...3) { String(format: "%.1f", $0) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.22), lineWidth: 0.5))
    }

    private var reverbRow: some View {
        HStack(spacing: 10) {
            rowLabel("REVERB")
            Spacer()
            Menu {
                ForEach(0..<SynthParams.reverbPresetNames.count, id: \.self) { i in
                    Button(SynthParams.reverbPresetNames[i]) { params.reverbPreset = i }
                }
            } label: {
                Text(reverbName.uppercased())
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
            }
        }
    }

    private var reverbName: String {
        let i = min(max(params.reverbPreset, 0), SynthParams.reverbPresetNames.count - 1)
        return SynthParams.reverbPresetNames[i]
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
            content()
        }
    }

    private func slider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        _ display: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 10) {
            rowLabel(label)
            MiniSlider(value: value, range: range)
            Text(display(value.wrappedValue))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func stepper(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            rowLabel(label)
            Spacer()
            stepButton("−") {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 }
            }
            Text("\(value.wrappedValue)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22)
            stepButton("+") {
                if value.wrappedValue < range.upperBound { value.wrappedValue += 1 }
            }
        }
    }

    private func stepButton(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, height: 24)
                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
        }
    }

    private func rowLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, design: .monospaced))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 72, alignment: .leading)
    }

    private func freqLabel(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%.1fk", hz / 1000) : "\(Int(hz))Hz"
    }
}
