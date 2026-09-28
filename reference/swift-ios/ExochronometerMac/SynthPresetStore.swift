import Foundation
import ExochronometerCore

/// Persisted library of named synth voicings. Mirrors `WidgetLayoutManager`'s
/// preset pattern: UserDefaults for the live library, plus a versioned file
/// payload for moving sounds between machines or backing them up.
@MainActor
final class SynthPresetStore: ObservableObject {
    @Published private(set) var presets: [SynthPreset] = []

    private let key = "exo.mac.synth.presets"

    init() { load() }

    /// Save under `name`, overwriting any existing preset with that name in
    /// place (keeps its id) so re-saving a tweak doesn't pile up duplicates.
    func save(name: String, params: SynthParams) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[idx].params = params
            presets[idx].savedAt = Date()
        } else {
            presets.append(SynthPreset(name: trimmed, params: params))
        }
        persist()
    }

    func delete(_ preset: SynthPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    // MARK: File transfer

    struct Export: Codable {
        var version = 1
        var presets: [SynthPreset]
    }

    func makeExport() -> Export { Export(presets: presets) }

    /// Merge imported presets (imported wins on name collision).
    func importPresets(_ export: Export) {
        for preset in export.presets {
            if let idx = presets.firstIndex(where: { $0.name == preset.name }) {
                presets[idx] = preset
            } else {
                presets.append(preset)
            }
        }
        persist()
    }

    // MARK: Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SynthPreset].self, from: data) {
            presets = decoded
        }
    }
}
