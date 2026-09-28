import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ExochronometerCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var layout = WidgetLayoutManager()
    @StateObject private var state = ChronometerState()
    @StateObject private var audio = HarmonicAudio(assignments: ContentView.audioAssignments)
    @StateObject private var triggers = TriggerEvaluator()
    @StateObject private var recorder = CanvasRecorder()
    @StateObject private var synthPresets = SynthPresetStore()
    @AppStorage("exo.mac.recorder.quality") private var recorderQualityRaw = CanvasRecorder.Quality.small.rawValue
    @AppStorage("exo.mac.audio.volume") private var audioVolume: Double = 0.5
    @AppStorage("exo.mac.audio.fundamentalsOff") private var audioFundamentalsOff: Bool = true
    @AppStorage("exo.mac.synth.v1") private var synthData = Data()
    @State private var showingSnapshotPopover = false
    @State private var showingSavePresetSheet = false
    @State private var showingTriggersPopover = false
    @State private var showingTimeTravelPopover = false
    @State private var timeTravelTimeInput: String = ""
    @State private var newPresetName = ""
    @State private var refreshKey: Int = 0
    @State private var lassoStart: CGPoint?
    @State private var lassoCurrent: CGPoint?
    @State private var lastCaptureResult: CaptureFeedback?

    private enum CaptureFeedback: Equatable {
        case ok(URL)
        case error(String)
    }

    /// Per-timeframe scales for the audio engine. Mirrors the spectrum
    /// widget's merged assignments so audio matches what's drawn.
    static let audioAssignments: [ToneAssignment] = [
        ToneAssignment(timeframe: .hour,        scale: 23),
        ToneAssignment(timeframe: .day,         scale: 26),
        ToneAssignment(timeframe: .quarterMoon, scale: 28),
        ToneAssignment(timeframe: .moon,        scale: 29),
        ToneAssignment(timeframe: .year,        scale: 29),
    ]

    /// Belt-and-suspenders teardown of the widget canvas every 20 min so
    /// any iOS-side CoreGraphics / Canvas caches that grow over long
    /// uninterrupted sessions get a chance to release. Critical for the
    /// 24/7 auto-poster use case.
    private static let hardRefreshInterval: Duration = .seconds(1200)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            // Headless mode: the live canvas — and every TimelineView-
            // driven Canvas redraw inside it — never enters the view
            // hierarchy, so the appliance idles near zero CPU. Captures
            // are unaffected: they render StaticCanvas offscreen from
            // layout data when a trigger fires.
            if state.mode == .headless {
                HeadlessStatusView(evaluator: triggers)
            } else {
                liveCanvas
                    .id(refreshKey)

                // Invisible driver that pushes current tones to the audio
                // engine. Zero-sized + hidden so it doesn't affect layout
                // or hit testing.
                AudioDriver(
                    audio: audio,
                    snapshotDate: state.effectiveSnapshotDate,
                    fundamentalsOff: audioFundamentalsOff
                )
            }

            // Invisible driver that ticks the trigger evaluator at 1 Hz and
            // captures the canvas when rules fire. Lives at canvas level so
            // it can render the StaticCanvas on demand.
            TriggerDriver(
                evaluator: triggers,
                snapshotDate: state.effectiveSnapshotDate,
                canvasBuilder: { date in
                    // Pass a concrete date so widgets render through their
                    // static branch — TimelineViews don't fire under
                    // ImageRenderer. Use tight captureBounds so the
                    // resulting PNG isn't padded with dead space.
                    StaticCanvas(
                        widgets: layout.widgets,
                        snapshotDate: date,
                        bounds: captureBounds
                    )
                },
                canvasBounds: captureBounds,
                chordExcludeHourly: convergenceChordSettings.excludeHourly,
                chordIncludeFundamentals: convergenceChordSettings.includeFundamentals
            )
        }
        .environmentObject(layout)
        .environmentObject(state)
        .environmentObject(audio)
        // Live engine + preset store for canvas SynthWidgets. Capture renders
        // deliberately omit these so the synth widget falls back to a
        // read-only rack.
        .harmonicAudio(audio)
        .environment(\.synthPresetStore, synthPresets)
        .task {
            // v2 re-anchoring (solstice year, Metonic epoch) invalidated
            // degrees stored under earlier schemas; purge rather than
            // migrate (pre-release policy).
            JournalNote.purgeStaleSchema(in: modelContext)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hardRefreshInterval)
                if !Task.isCancelled {
                    refreshKey &+= 1
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                modePicker
                    .padding(.horizontal, 12)
            }
            ToolbarItem(placement: .principal) {
                modeStatus
                    .padding(.horizontal, 24)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                audioControl
                recordControl
                captureButton
                triggersButton
                snapshotButton
                layoutsMenu
                addMenu
            }
        }
        .onChange(of: state.mode) { _, newMode in
            handleModeChange(newMode)
        }
        .onAppear {
            audio.volume = audioVolume
            recorder.audio = audio
            // Restore the saved synth voicing so the sound is right even
            // before a Harmonic Synth widget is on the canvas.
            if let decoded = try? JSONDecoder().decode(SynthParams.self, from: synthData) {
                audio.params = decoded
            }
        }
        .onChange(of: audioVolume) { _, v in
            audio.volume = v
        }
    }

    private var liveCanvas: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: canvasBounds.width, height: canvasBounds.height)
                    .contentShape(Rectangle())
                    .gesture(lassoGesture)

                ForEach(layout.widgets) { widget in
                    WidgetHost(widget: widget) {
                        WidgetCatalog.view(
                            for: widget.kind,
                            snapshotDate: state.effectiveSnapshotDate,
                            settings: widget.settings
                        )
                    }
                }

                if let start = lassoStart, let current = lassoCurrent {
                    let rect = lassoFrame(start: start, end: current)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                        .background(Rectangle().fill(Color.white.opacity(0.08)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .padding(20)
        }
    }

    private var canvasBounds: CGSize {
        let maxX = layout.widgets.map { $0.x + $0.width }.max() ?? 1200
        let maxY = layout.widgets.map { $0.y + $0.height }.max() ?? 800
        return CGSize(width: max(1200, maxX + 200), height: max(800, maxY + 200))
    }

    /// Bounds used for capture renders. Tight — matches the visible
    /// extent of the widgets with the same 20-px margin the layout
    /// already builds in via `findSpawnLocation`. Avoids the 200-px
    /// dead space the live canvas keeps as drag-room.
    private var captureBounds: CGSize {
        let margin: CGFloat = WidgetLayoutManager.snapStep
        let maxX = layout.widgets.map { $0.x + $0.width }.max() ?? 800
        let maxY = layout.widgets.map { $0.y + $0.height }.max() ?? 600
        return CGSize(width: maxX + margin, height: maxY + margin)
    }

    private var lassoGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if lassoStart == nil { lassoStart = value.startLocation }
                lassoCurrent = value.location
            }
            .onEnded { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)
                if movedDistance < 4 {
                    // Background tap → clear selection.
                    layout.deselectAll()
                } else if let start = lassoStart, let end = lassoCurrent {
                    let rect = lassoFrame(start: start, end: end)
                    let touchedIDs = layout.widgets
                        .filter { rect.intersects(CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
                        .map(\.id)
                    layout.setSelection(Set(touchedIDs))
                }
                lassoStart = nil
                lassoCurrent = nil
            }
    }

    private func lassoFrame(start: CGPoint, end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private var modePicker: some View {
        Picker("Mode", selection: $state.mode) {
            Text("Live").tag(ChronometerState.Mode.live)
            Text("Snapshot").tag(ChronometerState.Mode.snapshot)
            Text("Time Travel").tag(ChronometerState.Mode.timeTravel)
            Text("Headless").tag(ChronometerState.Mode.headless)
        }
        .pickerStyle(.segmented)
        .frame(width: 370)
    }

    @ViewBuilder
    private var modeStatus: some View {
        switch state.mode {
        case .live:
            Text("LIVE")
                .font(.system(size: 11, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.4))
        case .headless:
            Text("HEADLESS · TRIGGERS ARMED")
                .font(.system(size: 11, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.4))
        case .snapshot:
            if let date = state.selectedSnapshotDate {
                Text(snapshotStatusText("SNAPSHOT", date: date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            } else if let frozen = state.pendingSnapshotDate {
                Text(snapshotStatusText("FROZEN", date: frozen))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("SELECT A SNAPSHOT")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        case .timeTravel:
            Button {
                showingTimeTravelPopover.toggle()
            } label: {
                if let date = state.timeTravelDate {
                    Text(snapshotStatusText("⏱ TIME TRAVEL", date: date))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("⏱ SET DATE")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .help("Click to edit the time-travel date")
            .popover(isPresented: $showingTimeTravelPopover, arrowEdge: .bottom) {
                timeTravelEditor
            }
        }
    }

    private var timeTravelEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Travel")
                .font(.system(size: 13, weight: .medium))
            DatePicker(
                "Moment",
                selection: Binding(
                    get: { state.timeTravelDate ?? Date() },
                    set: { state.timeTravelDate = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack(spacing: 6) {
                Text("TIME")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                TextField("HH:MM", text: $timeTravelTimeInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { applyTimeTravelTimeInput() }
                Text("24-hour · press return to apply")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Button("Now") {
                    state.timeTravelDate = Date()
                }
                .controlSize(.small)
                Button("−1 day") {
                    state.timeTravelDate = (state.timeTravelDate ?? Date()).addingTimeInterval(-86400)
                }
                .controlSize(.small)
                Button("+1 day") {
                    state.timeTravelDate = (state.timeTravelDate ?? Date()).addingTimeInterval(86400)
                }
                .controlSize(.small)
                Spacer()
                Button("Done") {
                    showingTimeTravelPopover = false
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
            }
            Text("All widgets render at this instant. Triggers paused until you switch back to Live.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            timeTravelTimeInput = formatTimeTravelTime()
        }
        .onChange(of: state.timeTravelDate) { _, _ in
            timeTravelTimeInput = formatTimeTravelTime()
        }
    }

    private func formatTimeTravelTime() -> String {
        guard let date = state.timeTravelDate else { return "" }
        // Local: this is user input, the user types/reads what they see
        // on their wall clock. Captions, triggers, and indicator math
        // still operate on the absolute Date — they convert to UTC at
        // their own boundaries.
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    /// Parse `HH:MM` (24-hour, local) and write the result back into the
    /// date component-by-component so the calendar half stays untouched.
    /// Bad input reverts the field to the current valid value rather
    /// than blanking out.
    private func applyTimeTravelTimeInput() {
        let parts = timeTravelTimeInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            timeTravelTimeInput = formatTimeTravelTime()
            return
        }
        let cal = Calendar.current
        let base = state.timeTravelDate ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let new = cal.date(from: comps) {
            state.timeTravelDate = new
        } else {
            timeTravelTimeInput = formatTimeTravelTime()
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(WidgetKind.allCases) { kind in
                Button(kind.displayName) { layout.add(kind) }
            }
        } label: {
            Label("Add Widget", systemImage: "plus")
        }
        .help("Add a widget")
    }

    private var layoutsMenu: some View {
        Menu {
            Button {
                newPresetName = defaultPresetName()
                showingSavePresetSheet = true
            } label: {
                Label("Save Current Layout…", systemImage: "square.and.arrow.down")
            }

            if !layout.presets.isEmpty {
                Divider()
                Section("Load") {
                    ForEach(layout.presets) { preset in
                        Button {
                            layout.loadPreset(preset)
                        } label: {
                            Text(preset.name)
                        }
                    }
                }
                Divider()
                Menu {
                    ForEach(layout.presets) { preset in
                        Button(role: .destructive) {
                            layout.deletePreset(preset)
                        } label: {
                            Text(preset.name)
                        }
                    }
                } label: {
                    Label("Delete Preset", systemImage: "trash")
                }
            }

            Divider()
            Button {
                exportLayoutToFile()
            } label: {
                Label("Export Layout File…", systemImage: "square.and.arrow.up.on.square")
            }
            Button {
                importLayoutFromFile()
            } label: {
                Label("Import Layout File…", systemImage: "square.and.arrow.down.on.square")
            }
        } label: {
            Label("Layouts", systemImage: "rectangle.3.group")
        }
        .help("Save / load layout presets, or move the whole layout between machines as a JSON file")
        .sheet(isPresented: $showingSavePresetSheet) {
            savePresetSheet
        }
    }

    /// Write the current canvas + all presets to a JSON file — the
    /// machine-to-machine transfer path (UserDefaults doesn't travel).
    private func exportLayoutToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "exo-layout-\(formatter.string(from: Date())).json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(layout.exportLayout())
                try data.write(to: url)
            } catch {
                NSLog("Export layout failed: \(error)")
            }
        }
    }

    private func importLayoutFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let export = try decoder.decode(WidgetLayoutManager.LayoutExport.self, from: data)
                layout.importLayout(export)
            } catch {
                NSLog("Import layout failed: \(error)")
            }
        }
    }

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Layout Preset")
                .font(.system(size: 13, weight: .medium))
            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
                .onSubmit { commitSavePreset() }
            if layout.presets.contains(where: { $0.name == newPresetName.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                Text("A preset with this name exists — it will be overwritten.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { showingSavePresetSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { commitSavePreset() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func commitSavePreset() {
        layout.savePreset(name: newPresetName)
        showingSavePresetSheet = false
    }

    private func defaultPresetName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return "Layout " + formatter.string(from: Date())
    }

    private var snapshotButton: some View {
        Button {
            showingSnapshotPopover.toggle()
        } label: {
            Label("Take Snapshot", systemImage: "camera.aperture")
        }
        .help("Take a snapshot of the current state")
        .popover(isPresented: $showingSnapshotPopover, arrowEdge: .top) {
            SnapshotPopover()
        }
    }

    private func handleModeChange(_ newMode: ChronometerState.Mode) {
        switch newMode {
        case .snapshot:
            if !layout.contains(kind: .snapshotTimeline) {
                let result = layout.addAtTop(.snapshotTimeline)
                state.autoAddedTimelineID = result.id
                state.autoAddedShift = result.shift
            }
            if state.selectedSnapshotDate == nil {
                state.pendingSnapshotDate = Date()
            }

        case .live, .timeTravel, .headless:
            // Remove the auto-added snapshot timeline if it was added on
            // entering snapshot mode, and reverse the displacement so
            // existing widgets return to their original positions.
            if let id = state.autoAddedTimelineID {
                layout.remove(id)
                if state.autoAddedShift > 0 {
                    layout.shiftAllVertically(by: -state.autoAddedShift)
                }
                state.autoAddedTimelineID = nil
                state.autoAddedShift = 0
            }
            state.pendingSnapshotDate = nil

            if newMode == .timeTravel {
                // Seed the picker with "now" the first time the user
                // enters time-travel mode, and pop the editor so they
                // can immediately pick a moment.
                if state.timeTravelDate == nil {
                    state.timeTravelDate = Date()
                }
                showingTimeTravelPopover = true
            }
        }
    }

    private func snapshotStatusText(_ prefix: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d yyyy  ·  HH:mm"
        return "\(prefix)  ·  \(formatter.string(from: date).uppercased())"
    }

    private var triggersButton: some View {
        Button {
            showingTriggersPopover.toggle()
        } label: {
            let enabledCount = triggers.rules.filter(\.enabled).count
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.fill")
                if enabledCount > 0 {
                    Text("\(enabledCount)")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundStyle(triggers.rules.contains(where: \.enabled)
                             ? Color.accentColor
                             : Color.primary)
        }
        .help("Snapshot triggers (all off by default)")
        .popover(isPresented: $showingTriggersPopover, arrowEdge: .top) {
            // Popovers don't inherit ancestor environmentObjects on macOS,
            // so re-inject the layout manager. TriggerSettingsView's
            // "Pin to widget" button reads from it.
            TriggerSettingsView(evaluator: triggers)
                .environmentObject(layout)
        }
    }

    private var captureButton: some View {
        Button {
            captureCanvas()
        } label: {
            switch lastCaptureResult {
            case .ok:
                Label("Captured", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Label("Capture failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case nil:
                Label("Capture", systemImage: "camera.fill")
            }
        }
        .help(captureHelpText)
    }

    private var captureHelpText: String {
        switch lastCaptureResult {
        case .ok(let url):       return "Saved to \(url.path)"
        case .error(let msg):    return "Capture failed: \(msg)"
        case nil:                return "Capture the full canvas as PNG + caption .txt"
        }
    }

    /// The convergence widget's chord-filter settings (or defaults when no
    /// convergence widget is on the canvas), so posted/saved chord lists
    /// match what that widget's NOW section shows. If multiple convergence
    /// widgets exist, the first one wins.
    private var convergenceChordSettings: (excludeHourly: Bool, includeFundamentals: Bool) {
        let s = layout.widgets.first(where: { $0.kind == .convergence })?.settings
        return (s?.excludeHourly ?? true, s?.showFundamentals ?? false)
    }

    private func captureCanvas() {
        // Always pin a concrete date for the render. Passing nil here
        // would put widgets into their TimelineView branch — and
        // ImageRenderer doesn't drive TimelineViews, so widgets like the
        // color mapping and convergence selectors would render empty.
        let date = state.effectiveSnapshotDate ?? Date()
        let cs = convergenceChordSettings
        let stats = SnapshotStats(
            at: date,
            chordExcludeHourly: cs.excludeHourly,
            chordIncludeFundamentals: cs.includeFundamentals
        )
        let bounds = captureBounds
        let content = StaticCanvas(
            widgets: layout.widgets,
            snapshotDate: date,
            bounds: bounds
        )
        do {
            let artifact = try SnapshotEngine.shared.capture(
                content: content,
                renderSize: bounds,
                trigger: .manual,
                stats: stats
            )
            lastCaptureResult = .ok(artifact.imageURL)
            NSWorkspace.shared.activateFileViewerSelecting([artifact.imageURL])
        } catch {
            lastCaptureResult = .error(error.localizedDescription)
        }
        // Revert button state after a moment so it's ready for the next capture.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            lastCaptureResult = nil
        }
    }

    private var audioControl: some View {
        Button {
            if audio.isRunning { audio.stop() } else { audio.start() }
        } label: {
            Image(systemName: audio.isRunning ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(audio.isRunning ? Color.accentColor : Color.primary)
        }
        .help(audio.isRunning ? "Stop audio — full controls in the Harmonic Synth widget" : "Start audio — add a Harmonic Synth widget for full controls")
    }

    private var recordControl: some View {
        Menu {
            Picker("Quality", selection: Binding(
                get: { CanvasRecorder.Quality(rawValue: recorderQualityRaw) ?? .small },
                set: { recorderQualityRaw = $0.rawValue; recorder.quality = $0 }
            )) {
                ForEach(CanvasRecorder.Quality.allCases) { q in
                    Text(q.label).tag(q)
                }
            }
            .disabled(recorder.isRecording)

            if let url = recorder.lastURL, !recorder.isRecording {
                Divider()
                Button("Reveal Last Recording") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            if let msg = recorder.statusMessage {
                Divider()
                Text(msg)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .foregroundStyle(recorder.isRecording ? Color.red : Color.primary)
                if recorder.isRecording {
                    Text(recordingTimeString(recorder.elapsed))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        } primaryAction: {
            recorder.quality = CanvasRecorder.Quality(rawValue: recorderQualityRaw) ?? .small
            recorder.toggle(window: NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first)
        }
        .help(recorder.isRecording
            ? "Stop recording"
            : "Record the canvas + audio to a compressed video")
    }

    private func recordingTimeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A pure-render copy of the canvas used by `ImageRenderer`. Skips the
/// scrolling chrome, lasso overlay, and resize/drag affordances that the
/// live UI needs but the saved image doesn't. Widgets render at their
/// configured positions/sizes against a solid black background.
private struct StaticCanvas: View {
    let widgets: [WidgetInstance]
    let snapshotDate: Date?
    let bounds: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
                .frame(width: bounds.width, height: bounds.height)
            ForEach(widgets) { widget in
                WidgetCatalog.view(
                    for: widget.kind,
                    snapshotDate: snapshotDate,
                    settings: widget.settings
                )
                // Top-leading alignment so content that overflows the
                // widget frame (e.g. the 40-item upcoming chord list in
                // Convergence) gets clipped from the BOTTOM rather than
                // the default center — i.e. the "NOW" section stays
                // visible and the long tail falls off.
                .frame(width: widget.width, height: widget.height, alignment: .topLeading)
                .clipped()
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .offset(x: widget.x, y: widget.y)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        // Tells ScrollView-wrapping widgets to unwrap to a plain container
        // for this render. ImageRenderer doesn't drive ScrollViews.
        .environment(\.exoCaptureMode, true)
    }
}

/// Invisible view that drives the audio engine off either a TimelineView
/// (live) or a fixed snapshot date. Pushes amplitudes ~30 Hz.
private struct AudioDriver: View {
    @ObservedObject var audio: HarmonicAudio
    let snapshotDate: Date?
    let fundamentalsOff: Bool

    var body: some View {
        Group {
            if let date = snapshotDate {
                Color.clear
                    .onAppear { push(at: date) }
                    .onChange(of: date) { _, newDate in push(at: newDate) }
                    .onChange(of: fundamentalsOff) { _, _ in push(at: date) }
            } else {
                SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
                    Color.clear
                        .onAppear { push(at: ctx.date) }
                        .onChange(of: ctx.date) { _, newDate in push(at: newDate) }
                }
            }
        }
        .frame(width: 0, height: 0)
        .hidden()
        .allowsHitTesting(false)
    }

    private func push(at date: Date) {
        guard audio.isRunning else { return }
        let raw = HarmonicAnalysis.activeTones(at: date, assignments: ContentView.audioAssignments)
        var amps: [ToneID: Double] = [:]
        for tone in raw {
            if fundamentalsOff && tone.isFundamental { continue }
            let id = ToneID(timeframe: tone.timeframe, divisions: tone.divisions, skip: tone.skip, octaves: tone.scaling)
            amps[id] = tone.amplitude
        }
        audio.update(amplitudes: amps)
    }
}

/// UTC timestamp for the journal note that mirrors each X post.
/// (File-scope because `TriggerDriver` is generic and can't hold
/// static stored properties.)
private let xPostNoteStamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

/// Minimal status panel shown instead of the widget canvas in Headless
/// mode. Everything here updates only when an @Published value changes —
/// no TimelineViews, no Canvas — so the appliance idles near zero CPU
/// while the trigger engine keeps ticking.
private struct HeadlessStatusView: View {
    @ObservedObject var evaluator: TriggerEvaluator
    @ObservedObject private var xAuth = XAuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HEADLESS")
                .font(.system(size: 14, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.8))
            Text("Rendering paused · trigger engine armed · captures render offscreen when rules fire")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 14) {
                statusChip("DRY RUN", on: evaluator.dryRun, onColor: .orange)
                statusChip("POST TO X", on: evaluator.postToX, onColor: .green)
                statusChip(xLabel, on: xSignedIn, onColor: .green)
                statusChip("RULES \(evaluator.rules.filter(\.enabled).count)", on: true, onColor: .white)
            }

            Text("24H FIRINGS · \(evaluator.firingsLast24h)")
                .font(.system(size: 10, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(evaluator.firingLog.prefix(8)) { record in
                    HStack(spacing: 8) {
                        Image(systemName: record.wroteToDisk ? "photo.fill" : "eye")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(record.trigger.displayName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                if evaluator.firingLog.isEmpty {
                    Text("no firings yet")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var xSignedIn: Bool {
        if case .signedIn = xAuth.authState { return true }
        return false
    }

    private var xLabel: String {
        if case .signedIn(let user) = xAuth.authState { return "X @\(user)" }
        return "X SIGNED OUT"
    }

    private func statusChip(_ label: String, on: Bool, onColor: Color) -> some View {
        Text(label)
            .font(.system(size: 9, design: .monospaced))
            .tracking(1.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(on ? onColor : .white.opacity(0.3))
            .overlay(
                Capsule().stroke((on ? onColor : Color.white).opacity(0.35), lineWidth: 0.5)
            )
    }
}

/// Invisible 1Hz tick that runs the trigger engine. When rules fire, it
/// builds the static canvas and routes through SnapshotEngine — unless
/// dryRun is on, in which case it records the firing without writing.
/// Every successful X post also writes a journal snapshot of the posted
/// moment, so the journal is a durable index of everything published.
private struct TriggerDriver<Canvas: View>: View {
    @ObservedObject var evaluator: TriggerEvaluator
    @Environment(\.modelContext) private var modelContext
    let snapshotDate: Date?
    let canvasBuilder: (Date) -> Canvas
    let canvasBounds: CGSize
    // Convergence widget's chord-filter settings, resolved by the parent
    // so the posted chord list matches that widget's NOW section.
    let chordExcludeHourly: Bool
    let chordIncludeFundamentals: Bool

    var body: some View {
        Group {
            if snapshotDate != nil {
                // Frozen snapshot mode: no live triggers.
                Color.clear
            } else {
                // Plain async 1 Hz loop instead of a TimelineView: rendering-
                // driven updates are throttled or paused by App Nap when the
                // window is occluded or the display sleeps, which would
                // silently stop trigger evaluation on an unattended machine.
                // While the engine is armed we also hold a ProcessInfo
                // activity assertion — .userInitiated opts out of App Nap,
                // .idleSystemSleepDisabled keeps the Mac awake regardless of
                // pmset/display settings. Released automatically when the
                // driver leaves live mode or the window closes.
                Color.clear
                    .task {
                        let activity = ProcessInfo.processInfo.beginActivity(
                            options: [.userInitiated, .idleSystemSleepDisabled],
                            reason: "Exochronometer trigger engine armed"
                        )
                        defer { ProcessInfo.processInfo.endActivity(activity) }
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1))
                            if Task.isCancelled { break }
                            tick(at: Date())
                        }
                    }
            }
        }
        .frame(width: 0, height: 0)
        .hidden()
        .allowsHitTesting(false)
    }

    private func tick(at date: Date) {
        let stats = SnapshotStats(
            at: date,
            chordExcludeHourly: chordExcludeHourly,
            chordIncludeFundamentals: chordIncludeFundamentals
        )
        let fired = evaluator.evaluate(stats: stats)
        for fire in fired {
            handleFire(fire: fire, tickStats: stats, tickDate: date)
        }
    }

    private func handleFire(fire: FiredTrigger, tickStats: SnapshotStats, tickDate: Date) {
        let trigger = fire.kind
        let captureDate = fire.captureDate
        if evaluator.dryRun {
            evaluator.recordFiring(trigger, at: captureDate, imageURL: nil, wroteToDisk: false)
            return
        }
        // Reconstruct the instant the trigger depicts. Usually that's the
        // tick itself (reuse tickStats); for extreme peak/fallback fires the
        // capture date is the episode apex a few ticks back, so rebuild stats
        // there. The render pipeline is a pure function of the date, so this
        // recreates the true apex frame rather than the fire tick (which, for
        // the fallback path, is already back outside the extreme band).
        let stats = captureDate == tickDate
            ? tickStats
            : SnapshotStats(
                at: captureDate,
                chordExcludeHourly: chordExcludeHourly,
                chordIncludeFundamentals: chordIncludeFundamentals
              )
        let content = canvasBuilder(captureDate)
        let caption = stats.formatCaption(trigger: trigger)
        let captionHadURL = TriggerDriver.containsURL(caption)
        // When chords are active, their detail goes in a threaded reply
        // (text-only) so the main caption stays uncrowded.
        let chordDetail = stats.currentChords.isEmpty ? nil : stats.formatChordDetail()
        do {
            let artifact = try SnapshotEngine.shared.capture(
                content: content,
                renderSize: canvasBounds,
                trigger: trigger,
                stats: stats
            )
            // Disk write succeeded; now attempt X post if enabled.
            if evaluator.postToX {
                Task { @MainActor in
                    let xState = await Self.postToX(
                        imageURL: artifact.imageURL,
                        caption: caption,
                        chordDetail: chordDetail
                    )
                    evaluator.recordFiring(
                        trigger,
                        at: captureDate,
                        imageURL: artifact.imageURL,
                        wroteToDisk: true,
                        xPostState: xState,
                        captionHadURL: captionHadURL
                    )
                    // Mirror every successful post into the journal: a
                    // snapshot of the posted moment, noted with its
                    // date/time, trigger, and tweet URL.
                    if case .posted(let tweetURL) = xState {
                        let note = "X post · \(stats.triggerLabel(for: trigger)) · \(xPostNoteStamp.string(from: captureDate))"
                            + "\n\(tweetURL.absoluteString)"
                        SnapshotService.capture(at: captureDate, note: note, in: modelContext)
                    }
                }
            } else {
                evaluator.recordFiring(
                    trigger,
                    at: captureDate,
                    imageURL: artifact.imageURL,
                    wroteToDisk: true,
                    captionHadURL: captionHadURL
                )
            }
        } catch {
            evaluator.recordFiring(
                trigger,
                at: captureDate,
                imageURL: nil,
                wroteToDisk: false,
                captionHadURL: captionHadURL
            )
        }
    }

    /// Caption URL detection. Posts containing URLs are charged at
    /// $0.20/post by X vs. $0.015 for plain — surfacing this lets the
    /// user see if their caption format accidentally introduces URLs.
    static func containsURL(_ text: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"\bhttps?://\S+"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Read the PNG, upload it to X, post the tweet. Returns the
    /// resulting `XPostState` for the firing log.
    @MainActor
    private static func postToX(
        imageURL: URL,
        caption: String,
        chordDetail: String?
    ) async -> TriggerEvaluator.XPostState {
        guard case .signedIn = XAuthService.shared.authState else {
            return .failed(message: "Not signed in to X")
        }
        guard let png = try? Data(contentsOf: imageURL) else {
            return .failed(message: "Could not read PNG at \(imageURL.lastPathComponent)")
        }
        do {
            let result = try await XAPIClient.shared.postTweet(text: caption, imagePNG: png)
            // Threaded chord-detail reply (text-only). Best-effort: the
            // main post + image already succeeded, so a failed reply must
            // not flip the firing to failed — just log it.
            if let chordDetail, !chordDetail.isEmpty {
                do {
                    _ = try await XAPIClient.shared.postTweet(
                        text: chordDetail,
                        imagePNG: nil,
                        replyToID: result.tweetID
                    )
                } catch {
                    print("[X] chord-detail reply failed: \(error.localizedDescription)")
                }
            }
            return .posted(tweetURL: result.tweetURL)
        } catch let XError.http(message) where message.contains("rate") || message.contains("429") {
            return .rateLimited(retryAfter: nil)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}
