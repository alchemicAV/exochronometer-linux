import SwiftUI
import ExochronometerCore

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case yearCircle
    case moonCircle
    case quarterMoonCircle
    case dayCircle
    case hourCircle
    case minuteCircle
    case spectrum
    case oscilloscope
    case phasePortrait
    case centsWheel
    case dissonance
    case dissonanceGraph
    case colorMapping
    case harmonicsTable
    case chladni
    case lissajous
    case spectrogram
    case convergence
    case convergenceSelector
    case calibrationResult
    case snapshotTimeline
    case synth
    case peakCalendar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yearCircle:        return "Year Circle"
        case .moonCircle:        return "Moon Circle"
        case .quarterMoonCircle: return "Quarter Moon Circle"
        case .dayCircle:         return "Day Circle"
        case .hourCircle:        return "Hour Circle"
        case .minuteCircle:      return "Minute Circle"
        case .spectrum:          return "Harmonic Spectrum"
        case .oscilloscope:      return "Composite Waveform"
        case .phasePortrait:     return "Phase Portrait"
        case .centsWheel:        return "Cents Wheel"
        case .dissonance:        return "Dissonance Meters"
        case .dissonanceGraph:   return "Dissonance Graph"
        case .colorMapping:      return "Color Mapping"
        case .harmonicsTable:    return "Harmonics Table"
        case .chladni:           return "Chladni"
        case .lissajous:         return "Lissajous"
        case .spectrogram:       return "Spectrogram"
        case .convergence:       return "Convergence"
        case .convergenceSelector: return "Convergence Square"
        case .calibrationResult: return "Calibration Result"
        case .snapshotTimeline:  return "Snapshot Timeline"
        case .synth:             return "Harmonic Synth"
        case .peakCalendar:      return "Peak Calendar"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .yearCircle, .moonCircle, .quarterMoonCircle,
             .dayCircle, .hourCircle, .minuteCircle:
            return CGSize(width: 340, height: 380)
        case .spectrum:         return CGSize(width: 380, height: 540)
        case .oscilloscope:     return CGSize(width: 420, height: 160)
        case .phasePortrait:    return CGSize(width: 360, height: 360)
        case .centsWheel:       return CGSize(width: 360, height: 360)
        case .dissonance:       return CGSize(width: 320, height: 360)
        case .dissonanceGraph:  return CGSize(width: 540, height: 360)
        case .colorMapping:     return CGSize(width: 320, height: 360)
        case .harmonicsTable:   return CGSize(width: 420, height: 540)
        case .chladni:          return CGSize(width: 380, height: 420)
        case .lissajous:        return CGSize(width: 380, height: 540)
        case .spectrogram:      return CGSize(width: 540, height: 320)
        case .convergence:      return CGSize(width: 380, height: 540)
        case .convergenceSelector: return CGSize(width: 460, height: 540)
        case .calibrationResult: return CGSize(width: 360, height: 480)
        case .snapshotTimeline: return CGSize(width: 800, height: 180)
        case .synth:            return CGSize(width: 320, height: 620)
        // 11 columns × 2 rows — the whole 22-month year, Initia top-left.
        case .peakCalendar:     return CGSize(width: 2104, height: 424)
        }
    }

    var minSize: CGSize {
        switch self {
        case .yearCircle, .moonCircle, .quarterMoonCircle,
             .dayCircle, .hourCircle, .minuteCircle:
            return CGSize(width: 220, height: 260)
        case .spectrum:         return CGSize(width: 260, height: 320)
        case .oscilloscope:     return CGSize(width: 240, height: 120)
        case .phasePortrait:    return CGSize(width: 220, height: 220)
        case .centsWheel:       return CGSize(width: 240, height: 240)
        case .dissonance:       return CGSize(width: 220, height: 260)
        case .dissonanceGraph:  return CGSize(width: 360, height: 240)
        case .colorMapping:     return CGSize(width: 220, height: 220)
        case .harmonicsTable:   return CGSize(width: 280, height: 280)
        case .chladni:          return CGSize(width: 240, height: 240)
        case .lissajous:        return CGSize(width: 260, height: 320)
        case .spectrogram:      return CGSize(width: 360, height: 220)
        case .convergence:      return CGSize(width: 260, height: 320)
        case .convergenceSelector: return CGSize(width: 320, height: 360)
        case .calibrationResult: return CGSize(width: 280, height: 320)
        case .snapshotTimeline: return CGSize(width: 360, height: 140)
        case .synth:            return CGSize(width: 280, height: 300)
        // One month cell — the minimum shows just the current month.
        case .peakCalendar:     return CGSize(width: 208, height: 232)
        }
    }

    var hasSettings: Bool {
        switch self {
        case .spectrum, .oscilloscope, .phasePortrait, .centsWheel,
             .dissonance, .dissonanceGraph, .colorMapping, .chladni,
             .lissajous, .spectrogram, .convergence, .convergenceSelector:
            return true
        default:
            return false
        }
    }
}

/// Per-widget configurable settings. Fields are universally applicable;
/// each widget reads only the ones relevant to it. New widget options
/// can be added here without breaking persisted layouts because of
/// the Codable defaults.
struct WidgetSettings: Codable, Equatable {
    var showFundamentals: Bool = false
    var normalized: Bool = false   // PhasePortrait
    var excludedTimeframes: Set<TimeFrame> = []
    var excludeHourly: Bool = true // Convergence — hour overtones make 1-3 min events
    var dissonanceGraphRange: DissonanceGraphRange = .oneDay
    var useLogScale: Bool = true   // Spectrum frequency axis
    var spectrumScaleMode: SpectrumScaleMode = .merged   // Spectrum octave scaling
    /// Convergence Selector: nil = combined view across all (non-excluded)
    /// timeframes; otherwise a single timeframe is rendered solo.
    var selectorTimeframe: TimeFrame? = nil
    /// Frozen TriggerCalibrationResult baked into a CalibrationResultWidget
    /// instance when the user clicks "Save to widget" in the trigger
    /// settings popover. Lets the user spawn multiple result widgets and
    /// compare different simulation runs side-by-side.
    var pinnedCalibration: TriggerCalibrationResult? = nil
    /// Optional label so the user can name the run (e.g. "30 days, no chords").
    var pinnedCalibrationLabel: String? = nil

    private enum CodingKeys: String, CodingKey {
        case showFundamentals, normalized, excludedTimeframes, excludeHourly,
             dissonanceGraphRange, useLogScale, spectrumScaleMode, selectorTimeframe,
             pinnedCalibration, pinnedCalibrationLabel
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.showFundamentals    = (try? c.decode(Bool.self, forKey: .showFundamentals)) ?? false
        self.normalized          = (try? c.decode(Bool.self, forKey: .normalized)) ?? false
        self.excludedTimeframes  = (try? c.decode(Set<TimeFrame>.self, forKey: .excludedTimeframes)) ?? []
        self.excludeHourly       = (try? c.decode(Bool.self, forKey: .excludeHourly)) ?? true
        self.dissonanceGraphRange = (try? c.decode(DissonanceGraphRange.self, forKey: .dissonanceGraphRange)) ?? .oneDay
        self.useLogScale         = (try? c.decode(Bool.self, forKey: .useLogScale)) ?? true
        self.spectrumScaleMode   = (try? c.decode(SpectrumScaleMode.self, forKey: .spectrumScaleMode)) ?? .merged
        self.selectorTimeframe   = (try? c.decode(TimeFrame.self, forKey: .selectorTimeframe))
        self.pinnedCalibration   = (try? c.decode(TriggerCalibrationResult.self, forKey: .pinnedCalibration))
        self.pinnedCalibrationLabel = (try? c.decode(String.self, forKey: .pinnedCalibrationLabel))
    }
}

struct WidgetInstance: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: WidgetKind
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var settings: WidgetSettings

    init(
        id: UUID = UUID(),
        kind: WidgetKind,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        settings: WidgetSettings = WidgetSettings()
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, width, height, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        width = try c.decode(CGFloat.self, forKey: .width)
        height = try c.decode(CGFloat.self, forKey: .height)
        settings = (try? c.decode(WidgetSettings.self, forKey: .settings)) ?? WidgetSettings()
    }
}

/// A named, persisted snapshot of widget positions/sizes/settings.
struct LayoutPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var widgets: [WidgetInstance]
    var savedAt: Date

    init(id: UUID = UUID(), name: String, widgets: [WidgetInstance], savedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.savedAt = savedAt
    }
}

@MainActor
final class WidgetLayoutManager: ObservableObject {
    @Published var widgets: [WidgetInstance]

    /// Named layouts the user has saved. Quick swap between configurations
    /// (e.g. "Performance", "Analysis", "Minimal") and a backstop in case
    /// the live layout ever gets corrupted.
    @Published private(set) var presets: [LayoutPreset] = []

    /// Current multi-selection. Drag any selected widget → all selected
    /// move together. Lasso replaces this set.
    @Published var selectedIDs: Set<UUID> = []

    /// While a selected widget is being group-dragged, the leader's
    /// translation lives here so other selected widgets can follow.
    @Published var groupDragOffset: CGSize = .zero
    @Published var groupDragSourceID: UUID?

    private let storageKey: String
    private let presetsKey: String
    static let snapStep: CGFloat = 20

    init(storageKey: String = "exo.mac.layout.default") {
        self.storageKey = storageKey
        self.presetsKey = storageKey + ".presets"
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WidgetInstance].self, from: data) {
            self.widgets = decoded
        } else {
            self.widgets = Self.makeDefaultLayout()
        }
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([LayoutPreset].self, from: data) {
            self.presets = decoded
        }
    }

    func update(id: UUID, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].x = x
        widgets[index].y = y
        widgets[index].width = width
        widgets[index].height = height
        save()
    }

    func bringToFront(_ id: UUID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }),
              index != widgets.count - 1 else { return }
        let w = widgets.remove(at: index)
        widgets.append(w)
        save()
    }

    @discardableResult
    func add(_ kind: WidgetKind) -> UUID {
        let size = kind.defaultSize
        let position = findSpawnLocation(for: size)
        let instance = WidgetInstance(
            kind: kind,
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
        widgets.append(instance)
        save()
        return instance.id
    }

    /// Pin a calibration result into a fresh CalibrationResult widget.
    /// Used by the trigger settings popover's "Pin to widget" button so
    /// the user can build up a board of saved sim results to compare.
    @discardableResult
    func addCalibrationResult(_ result: TriggerCalibrationResult, label: String? = nil) -> UUID {
        let kind: WidgetKind = .calibrationResult
        let size = kind.defaultSize
        let position = findSpawnLocation(for: size)
        var settings = WidgetSettings()
        settings.pinnedCalibration = result
        settings.pinnedCalibrationLabel = label
        let instance = WidgetInstance(
            kind: kind,
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height,
            settings: settings
        )
        widgets.append(instance)
        save()
        return instance.id
    }

    /// Insert a widget at the top of the canvas, pushing every other
    /// widget down by its height + a gap so nothing overlaps. Returns
    /// the new widget's id AND the shift amount, so the caller can
    /// reverse the displacement if it later auto-removes the widget.
    @discardableResult
    func addAtTop(_ kind: WidgetKind) -> (id: UUID, shift: CGFloat) {
        let size = kind.defaultSize
        let gap = Self.snapStep
        let shift = size.height + gap
        for i in widgets.indices {
            widgets[i].y += shift
        }
        let instance = WidgetInstance(
            kind: kind,
            x: gap,
            y: gap,
            width: size.width,
            height: size.height
        )
        widgets.append(instance)
        save()
        return (instance.id, shift)
    }

    /// Shift every widget vertically. Used to undo an `addAtTop` when
    /// the displaced widget is being auto-removed.
    func shiftAllVertically(by deltaY: CGFloat) {
        for i in widgets.indices {
            widgets[i].y = max(0, widgets[i].y + deltaY)
        }
        save()
    }

    func setSelection(_ ids: Set<UUID>) {
        selectedIDs = ids
    }

    func deselectAll() {
        selectedIDs = []
    }

    /// Apply a delta to every currently-selected widget. Used when a
    /// group drag commits on `onEnded`. The delta is clamped to whatever
    /// the leftmost/topmost selected widget can absorb so the group
    /// stays cohesive at the edge.
    func moveSelected(by delta: CGSize) {
        let clamped = clampedDelta(delta)
        for i in widgets.indices where selectedIDs.contains(widgets[i].id) {
            widgets[i].x += clamped.width
            widgets[i].y += clamped.height
        }
        save()
    }

    /// Limits a proposed translation so no selected widget would cross
    /// x < 0 or y < 0. Used for both the committed move and the live
    /// group-drag preview offset.
    func clampedDelta(_ delta: CGSize) -> CGSize {
        let selected = widgets.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return delta }
        let minX = selected.map(\.x).min() ?? 0
        let minY = selected.map(\.y).min() ?? 0
        return CGSize(
            width: max(delta.width, -minX),
            height: max(delta.height, -minY)
        )
    }

    func remove(_ id: UUID) {
        widgets.removeAll { $0.id == id }
        save()
    }

    func contains(kind: WidgetKind) -> Bool {
        widgets.contains { $0.kind == kind }
    }

    func settingsBinding(for id: UUID) -> Binding<WidgetSettings> {
        Binding(
            get: { [weak self] in
                self?.widgets.first(where: { $0.id == id })?.settings ?? WidgetSettings()
            },
            set: { [weak self] newValue in
                guard let self else { return }
                guard let index = self.widgets.firstIndex(where: { $0.id == id }) else { return }
                self.widgets[index].settings = newValue
                self.save()
            }
        )
    }

    private func findSpawnLocation(for size: CGSize) -> CGPoint {
        let gap: CGFloat = WidgetLayoutManager.snapStep
        if widgets.isEmpty {
            return CGPoint(x: gap, y: gap)
        }
        let maxX = widgets.map { $0.x + $0.width }.max() ?? 0
        let topY = widgets.map { $0.y }.min() ?? gap
        return CGPoint(x: maxX + gap, y: topY)
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
        }
    }

    /// Capture the current layout under a name. If a preset with the same
    /// name already exists, it's overwritten in place (keeps its id).
    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[idx].widgets = widgets
            presets[idx].savedAt = Date()
        } else {
            presets.append(LayoutPreset(name: trimmed, widgets: widgets))
        }
        savePresets()
    }

    /// Replace the current layout with a saved preset. Drops any in-flight
    /// selection / group drag so we don't reference stale ids.
    func loadPreset(_ preset: LayoutPreset) {
        selectedIDs = []
        groupDragOffset = .zero
        groupDragSourceID = nil
        widgets = preset.widgets
        save()
    }

    func deletePreset(_ preset: LayoutPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    /// Versioned file payload for moving a layout between machines —
    /// the current canvas plus every saved preset. Mirrors the trigger
    /// profile export/import in TriggerSettingsView.
    struct LayoutExport: Codable {
        var version: Int = 1
        var widgets: [WidgetInstance]
        var presets: [LayoutPreset]
    }

    func exportLayout() -> LayoutExport {
        LayoutExport(widgets: widgets, presets: presets)
    }

    /// Replace the live canvas with the imported one and merge presets
    /// (imported presets win on name collision). Drops any in-flight
    /// selection so we don't reference stale ids.
    func importLayout(_ export: LayoutExport) {
        selectedIDs = []
        groupDragOffset = .zero
        groupDragSourceID = nil
        widgets = export.widgets
        save()
        for preset in export.presets {
            if let idx = presets.firstIndex(where: { $0.name == preset.name }) {
                presets[idx] = preset
            } else {
                presets.append(preset)
            }
        }
        savePresets()
    }

    func renamePreset(_ preset: LayoutPreset, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].name = trimmed
        savePresets()
    }

    static func snap(_ value: CGFloat) -> CGFloat {
        (value / snapStep).rounded() * snapStep
    }

    static func makeDefaultLayout() -> [WidgetInstance] {
        let cellWidth: CGFloat = 340
        let cellHeight: CGFloat = 380
        let gap: CGFloat = 20
        let kinds: [WidgetKind] = [
            .yearCircle, .moonCircle, .quarterMoonCircle,
            .dayCircle, .hourCircle, .minuteCircle,
        ]
        return kinds.enumerated().map { i, kind in
            let col = i % 3
            let row = i / 3
            return WidgetInstance(
                kind: kind,
                x: gap + CGFloat(col) * (cellWidth + gap),
                y: gap + CGFloat(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            )
        }
    }
}

struct WidgetHost<Content: View>: View {
    @EnvironmentObject var manager: WidgetLayoutManager
    let widget: WidgetInstance
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero
    @State private var hovering: Bool = false
    @State private var showingSettings: Bool = false

    private var isSelected: Bool { manager.selectedIDs.contains(widget.id) }

    /// Offset to apply to position during render. If a group drag is
    /// in progress AND this widget is part of the selection (leader or
    /// follower), use the shared groupDragOffset so the whole group
    /// moves in lock-step. Otherwise use our own local drag.
    private var effectiveDragOffset: CGSize {
        if isSelected, manager.groupDragSourceID != nil {
            return manager.groupDragOffset
        }
        return dragOffset
    }

    private var liveX: CGFloat { widget.x + effectiveDragOffset.width }
    private var liveY: CGFloat { widget.y + effectiveDragOffset.height }
    private var liveWidth: CGFloat {
        max(widget.kind.minSize.width, (widget.width + resizeOffset.width).rounded())
    }
    private var liveHeight: CGFloat {
        max(widget.kind.minSize.height, (widget.height + resizeOffset.height).rounded())
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .frame(width: liveWidth, height: liveHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected
                                ? Color.white.opacity(0.85)
                                : Color.white.opacity(hovering ? 0.25 : 0.12),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )

            if hovering || showingSettings {
                HStack(spacing: 6) {
                    if widget.kind.hasSettings { settingsButton }
                    Spacer()
                    closeButton
                }
                .padding(8)
            }

            resizeHandle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: liveWidth, height: liveHeight, alignment: .topLeading)
        .offset(x: liveX, y: liveY)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if isSelected {
                        if manager.groupDragSourceID == nil {
                            manager.groupDragSourceID = widget.id
                        }
                        if manager.groupDragSourceID == widget.id {
                            manager.groupDragOffset = manager.clampedDelta(value.translation)
                        }
                    } else {
                        dragOffset = value.translation
                    }
                }
                .onEnded { _ in
                    if isSelected && manager.groupDragSourceID == widget.id {
                        let delta = CGSize(
                            width: WidgetLayoutManager.snap(manager.groupDragOffset.width),
                            height: WidgetLayoutManager.snap(manager.groupDragOffset.height)
                        )
                        manager.groupDragOffset = .zero
                        manager.groupDragSourceID = nil
                        manager.moveSelected(by: delta)
                    } else if !isSelected {
                        let newX = WidgetLayoutManager.snap(widget.x + dragOffset.width)
                        let newY = WidgetLayoutManager.snap(widget.y + dragOffset.height)
                        dragOffset = .zero
                        manager.update(
                            id: widget.id,
                            x: max(0, newX),
                            y: max(0, newY),
                            width: widget.width,
                            height: widget.height
                        )
                    }
                }
        )
        .onHover { isHovering in
            hovering = isHovering
            if isHovering { manager.bringToFront(widget.id) }
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black.opacity(0.6), Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("\(widget.kind.displayName) settings")
        .popover(isPresented: $showingSettings, arrowEdge: .top) {
            WidgetSettingsPopover(
                kind: widget.kind,
                settings: manager.settingsBinding(for: widget.id)
            )
        }
    }

    private var closeButton: some View {
        Button {
            manager.remove(widget.id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black.opacity(0.6), Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("Remove \(widget.kind.displayName)")
    }

    private var resizeHandle: some View {
        ResizeGripShape()
            .stroke(Color.white.opacity(hovering ? 0.55 : 0.3), lineWidth: 1)
            .frame(width: 14, height: 14)
            .padding(4)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Round to integer pixels to avoid subpixel shimmer
                        // and use highPriority so the body's move-drag never
                        // briefly competes during the same gesture.
                        resizeOffset = CGSize(
                            width: value.translation.width.rounded(),
                            height: value.translation.height.rounded()
                        )
                    }
                    .onEnded { _ in
                        let snappedW = WidgetLayoutManager.snap(widget.width + resizeOffset.width)
                        let snappedH = WidgetLayoutManager.snap(widget.height + resizeOffset.height)
                        let newW = max(widget.kind.minSize.width, snappedW)
                        let newH = max(widget.kind.minSize.height, snappedH)
                        resizeOffset = .zero
                        manager.update(
                            id: widget.id,
                            x: widget.x,
                            y: widget.y,
                            width: newW,
                            height: newH
                        )
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

private struct ResizeGripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 4
        for offset in stride(from: step, through: rect.width, by: step) {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - offset))
            path.addLine(to: CGPoint(x: rect.maxX - offset, y: rect.maxY))
        }
        return path
    }
}
