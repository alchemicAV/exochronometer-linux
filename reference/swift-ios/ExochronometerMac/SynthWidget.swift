import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ExochronometerCore

// MARK: - Engine handoff

/// Optional references threaded through the environment. Using custom
/// `EnvironmentValue`s (not `@EnvironmentObject`) means they default to `nil`
/// and never trap — so the widget renders a safe, read-only rack in the
/// headless `StaticCanvas`/`ImageRenderer` capture path, where nothing is
/// injected.
private struct HarmonicAudioKey: EnvironmentKey {
    static let defaultValue: HarmonicAudio? = nil
}

private struct SynthPresetStoreKey: EnvironmentKey {
    static let defaultValue: SynthPresetStore? = nil
}

extension EnvironmentValues {
    var harmonicAudio: HarmonicAudio? {
        get { self[HarmonicAudioKey.self] }
        set { self[HarmonicAudioKey.self] = newValue }
    }
    var synthPresetStore: SynthPresetStore? {
        get { self[SynthPresetStoreKey.self] }
        set { self[SynthPresetStoreKey.self] = newValue }
    }
}

// MARK: - Catalog entry

/// The synth control surface as a canvas widget. Live on the board it drives
/// the engine; in a capture render it falls back to a disabled rack showing
/// the persisted settings, so a snapshot still depicts the current sound.
struct SynthWidget: View {
    @Environment(\.harmonicAudio) private var audio

    var body: some View {
        if let audio {
            SynthWidgetControls(audio: audio)
        } else {
            SynthWidgetStatic()
        }
    }
}

/// Live host — observes the engine and binds the rack to `audio.params`.
private struct SynthWidgetControls: View {
    @ObservedObject var audio: HarmonicAudio
    @Environment(\.synthPresetStore) private var presetStore
    @AppStorage("exo.mac.audio.volume") private var volume = 0.5
    @AppStorage("exo.mac.audio.fundamentalsOff") private var fundamentalsOff = true
    @AppStorage("exo.mac.synth.v1") private var synthData = Data()
    @State private var showingSaveSheet = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 0) {
            if let presetStore {
                presetBar(presetStore)
                Divider()
            }
            SynthRack(
                params: $audio.params,
                volume: $volume,
                fundamentalsOff: $fundamentalsOff,
                isRunning: audio.isRunning,
                onToggleAudio: { on in if on { audio.start() } else { audio.stop() } }
            )
        }
        .onChange(of: volume) { _, v in audio.volume = v }
        .onChange(of: audio.params) { _, p in
            if let data = try? JSONEncoder().encode(p) { synthData = data }
        }
        .sheet(isPresented: $showingSaveSheet) { saveSheet }
    }

    @ViewBuilder
    private func presetBar(_ store: SynthPresetStore) -> some View {
        HStack(spacing: 6) {
            Menu {
                Button("Save Current…") {
                    presetName = defaultPresetName()
                    showingSaveSheet = true
                }
                if !store.presets.isEmpty {
                    Divider()
                    Section("Load") {
                        ForEach(store.presets) { preset in
                            Button(preset.name) { audio.params = preset.params }
                        }
                    }
                    Menu("Delete") {
                        ForEach(store.presets) { preset in
                            Button(preset.name, role: .destructive) { store.delete(preset) }
                        }
                    }
                }
                Divider()
                Button("Export Presets File…") { exportPresets(store) }
                Button("Import Presets File…") { importPresets(store) }
            } label: {
                Label("Presets", systemImage: "slider.horizontal.below.square.filled.and.square")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Synth Preset")
                .font(.system(size: 13, weight: .medium))
            TextField("Preset name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
                .onSubmit(commitSave)
            if let store = presetStore,
               store.presets.contains(where: { $0.name == presetName.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                Text("A preset with this name exists — it will be overwritten.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { showingSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commitSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func commitSave() {
        presetStore?.save(name: presetName, params: audio.params)
        showingSaveSheet = false
    }

    private func defaultPresetName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d HH:mm"
        return "Synth " + fmt.string(from: Date())
    }

    private func exportPresets(_ store: SynthPresetStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "exo-synth-presets-\(fmt.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store.makeExport()) {
            try? data.write(to: url)
        }
    }

    private func importPresets(_ store: SynthPresetStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let export = try? decoder.decode(SynthPresetStore.Export.self, from: data) {
            store.importPresets(export)
        }
    }
}

/// Capture-safe host — no engine. Shows the persisted params, disabled.
private struct SynthWidgetStatic: View {
    @AppStorage("exo.mac.audio.volume") private var volume = 0.5
    @AppStorage("exo.mac.audio.fundamentalsOff") private var fundamentalsOff = true
    @AppStorage("exo.mac.synth.v1") private var synthData = Data()
    @State private var params = SynthParams()

    var body: some View {
        SynthRack(
            params: $params,
            volume: $volume,
            fundamentalsOff: $fundamentalsOff,
            isRunning: false,
            onToggleAudio: { _ in },
            enabled: false
        )
        .onAppear {
            if let decoded = try? JSONDecoder().decode(SynthParams.self, from: synthData) {
                params = decoded
            }
        }
    }
}

// MARK: - The rack

/// The full control surface, reused by the live and capture hosts. Pure
/// bindings in, so it doesn't care where the state lives.
struct SynthRack: View {
    @Binding var params: SynthParams
    @Binding var volume: Double
    @Binding var fundamentalsOff: Bool
    let isRunning: Bool
    let onToggleAudio: (Bool) -> Void
    var enabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                masterSection
                Divider()
                section("Envelope") {
                    paramSlider("Attack", $params.attackMs, 0...1000, unit: "ms")
                    paramSlider("Release", $params.releaseMs, 0...3000, unit: "ms")
                }
                section("Tone") {
                    paramSlider("Low-pass", $params.lowpassHz, 500...20000, format: freqLabel)
                }
                section("Space") {
                    HStack {
                        Text("Reverb").frame(width: labelWidth, alignment: .leading)
                        Picker("", selection: $params.reverbPreset) {
                            ForEach(0..<SynthParams.reverbPresetNames.count, id: \.self) { i in
                                Text(SynthParams.reverbPresetNames[i]).tag(i)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    paramSlider("Mix", $params.reverbMix, 0...100, unit: "%")
                }
                section("Movement") {
                    paramSlider("Tremolo", $params.tremoloRateHz, 0...4, unit: "Hz", decimals: 2)
                    paramSlider("Depth", $params.tremoloDepth, 0...1, format: pctLabel)
                    paramSlider("Width", $params.width, 0...1, format: pctLabel)
                }
                timbreSection
            }
            .padding(14)
        }
        .disabled(!enabled)
    }

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HARMONIC SYNTH")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isRunning },
                    set: { onToggleAudio($0) }
                ))
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Toggle("Include fundamentals", isOn: Binding(
                get: { !fundamentalsOff },
                set: { fundamentalsOff = !$0 }
            ))
            .font(.system(size: 11))
        }
    }

    private var timbreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timbre — alters the chord")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Reset") { params.resetTimbre() }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
            }
            Text("These add or blur frequencies the chord didn't contain — the day's 3rd partial lands on the hour. Default-neutral; move them to hear the trade.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: $params.unisonVoices, in: 1...3) {
                Text("Unison voices: \(params.unisonVoices)\(params.unisonVoices > 1 && params.detuneCents == 0 ? "  (safe doubling)" : "")")
                    .font(.system(size: 11))
            }
            paramSlider("Detune", $params.detuneCents, 0...25, unit: "¢", decimals: 1)
            paramSlider("Enrichment", $params.enrichment, 0...1, format: pctLabel)
            Stepper(value: $params.partials, in: 2...6) {
                Text("Partials: \(params.partials)").font(.system(size: 11))
            }
            paramSlider("Tilt", $params.partialTilt, 0.5...3, decimals: 1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private let labelWidth: CGFloat = 74

    private func paramSlider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        unit: String = "",
        decimals: Int = 0,
        format: ((Double) -> String)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: labelWidth, alignment: .leading)
            Slider(value: value, in: range)
            Text(format?(value.wrappedValue) ?? defaultLabel(value.wrappedValue, unit: unit, decimals: decimals))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func defaultLabel(_ v: Double, unit: String, decimals: Int) -> String {
        let n = String(format: "%.\(decimals)f", v)
        return unit.isEmpty ? n : "\(n)\(unit)"
    }

    private func freqLabel(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%.1fk", hz / 1000) : "\(Int(hz))Hz"
    }

    private func pctLabel(_ v: Double) -> String { "\(Int(v * 100))%" }
}

// MARK: - Live-canvas injection

extension View {
    /// Make the live audio engine available to `SynthWidget`s on the canvas.
    /// Capture paths deliberately omit this so the widget renders read-only.
    func harmonicAudio(_ audio: HarmonicAudio) -> some View {
        environment(\.harmonicAudio, audio)
    }
}
