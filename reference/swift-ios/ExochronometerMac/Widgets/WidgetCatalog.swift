import SwiftUI
import ExochronometerCore

struct WidgetCatalog {
    @ViewBuilder
    static func view(for kind: WidgetKind, snapshotDate: Date?, settings: WidgetSettings) -> some View {
        switch kind {
        case .yearCircle:        LiveTimeCircleWidget(timeFrame: .year,        snapshotDate: snapshotDate)
        case .moonCircle:        LiveTimeCircleWidget(timeFrame: .moon,        snapshotDate: snapshotDate)
        case .quarterMoonCircle: LiveTimeCircleWidget(timeFrame: .quarterMoon, snapshotDate: snapshotDate)
        case .dayCircle:         LiveTimeCircleWidget(timeFrame: .day,         snapshotDate: snapshotDate)
        case .hourCircle:        LiveTimeCircleWidget(timeFrame: .hour,        snapshotDate: snapshotDate)
        case .minuteCircle:      LiveTimeCircleWidget(timeFrame: .minute,      snapshotDate: snapshotDate)
        case .spectrum:          LiveSpectrumWidget(snapshotDate: snapshotDate, settings: settings)
        case .oscilloscope:      LiveOscilloscopeWidget(snapshotDate: snapshotDate, settings: settings)
        case .phasePortrait:     LivePhasePortraitWidget(snapshotDate: snapshotDate, settings: settings)
        case .centsWheel:        LiveCentsWheelWidget(snapshotDate: snapshotDate, settings: settings)
        case .dissonance:        LiveDissonanceWidget(snapshotDate: snapshotDate, settings: settings)
        case .dissonanceGraph:   LiveCumulativeDissonanceWidget(snapshotDate: snapshotDate, settings: settings)
        case .colorMapping:      LiveColorMappingWidget(snapshotDate: snapshotDate, settings: settings)
        case .harmonicsTable:    LiveHarmonicsTableWidget(snapshotDate: snapshotDate)
        case .chladni:           LiveChladniWidget(snapshotDate: snapshotDate, settings: settings)
        case .lissajous:         LiveLissajousWidget(snapshotDate: snapshotDate, settings: settings)
        case .spectrogram:       LiveSpectrogramWidget(snapshotDate: snapshotDate, settings: settings)
        case .convergence:       LiveConvergenceWidget(snapshotDate: snapshotDate, settings: settings)
        case .convergenceSelector: LiveConvergenceSelectorWidget(snapshotDate: snapshotDate, settings: settings)
        case .calibrationResult: LiveCalibrationResultWidget(snapshotDate: snapshotDate, settings: settings)
        case .snapshotTimeline:  SnapshotTimelineWidget()
        case .synth:             SynthWidget()
        case .peakCalendar:      LivePeakCalendarWidget(snapshotDate: snapshotDate)
        }
    }
}
