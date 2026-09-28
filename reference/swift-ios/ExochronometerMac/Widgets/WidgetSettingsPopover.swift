import SwiftUI
import ExochronometerCore

struct WidgetSettingsPopover: View {
    let kind: WidgetKind
    @Binding var settings: WidgetSettings

    private let orderedTimeframes: [TimeFrame] = [.hour, .day, .quarterMoon, .moon, .year]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(kind.displayName.uppercased())")
                .font(.system(size: 9, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.55))

            if showsFundamentalsToggle {
                Toggle("Show Fundamentals", isOn: $settings.showFundamentals)
                    .toggleStyle(.switch)
                    .font(.system(size: 11, design: .monospaced))
            }

            if kind == .phasePortrait {
                Toggle("Normalize per timeframe", isOn: $settings.normalized)
                    .toggleStyle(.switch)
                    .font(.system(size: 11, design: .monospaced))
            }

            if kind == .convergence {
                Toggle("Exclude hourly", isOn: $settings.excludeHourly)
                    .toggleStyle(.switch)
                    .font(.system(size: 11, design: .monospaced))
            }

            if kind == .spectrum {
                Toggle("Logarithmic frequency axis", isOn: $settings.useLogScale)
                    .toggleStyle(.switch)
                    .font(.system(size: 11, design: .monospaced))

                VStack(alignment: .leading, spacing: 4) {
                    Text("OCTAVE SCALE")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                    Picker("", selection: $settings.spectrumScaleMode) {
                        ForEach(SpectrumScaleMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if kind == .convergenceSelector {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIMEFRAME")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                    selectorTimeframeRow
                }
            }

            if kind == .dissonanceGraph {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME RANGE")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                    Picker("", selection: $settings.dissonanceGraphRange) {
                        ForEach(DissonanceGraphRange.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if showsTimeframeFilter {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXCLUDE TIMEFRAMES")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                    timeframeRow
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var selectorTimeframeRow: some View {
        HStack(spacing: 6) {
            selectorChip(label: "ALL", isActive: settings.selectorTimeframe == nil) {
                settings.selectorTimeframe = nil
            }
            ForEach(orderedTimeframes, id: \.self) { tf in
                selectorChip(label: shortLabel(tf), isActive: settings.selectorTimeframe == tf) {
                    settings.selectorTimeframe = tf
                }
            }
        }
    }

    private func selectorChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(isActive ? .white : .white.opacity(0.4))
                .background(Capsule().fill(isActive ? Color.white.opacity(0.18) : Color.clear))
                .overlay(Capsule().stroke(.white.opacity(isActive ? 0.7 : 0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var timeframeRow: some View {
        HStack(spacing: 6) {
            ForEach(orderedTimeframes, id: \.self) { tf in
                let excluded = settings.excludedTimeframes.contains(tf)
                Button {
                    if excluded {
                        settings.excludedTimeframes.remove(tf)
                    } else {
                        settings.excludedTimeframes.insert(tf)
                    }
                } label: {
                    Text(shortLabel(tf))
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(excluded ? .white.opacity(0.25) : .white.opacity(0.85))
                        .background(Capsule().fill(.clear))
                        .overlay(Capsule().stroke(.white.opacity(excluded ? 0.12 : 0.45), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var showsFundamentalsToggle: Bool {
        switch kind {
        case .spectrum, .oscilloscope, .phasePortrait, .centsWheel,
             .dissonance, .colorMapping, .chladni, .lissajous, .spectrogram,
             .convergence:
            return true
        default:
            return false
        }
    }

    private var showsTimeframeFilter: Bool {
        switch kind {
        case .spectrum, .oscilloscope, .phasePortrait, .centsWheel,
             .dissonance, .colorMapping, .lissajous:
            return true
        default:
            return false
        }
    }

    private func shortLabel(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON"
        case .quarterMoon: return "QTR"
        case .day:         return "DAY"
        case .hour:        return "HOUR"
        case .minute:      return "MIN"
        }
    }
}
