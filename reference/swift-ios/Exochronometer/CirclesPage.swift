import SwiftUI
import SwiftData
import ExochronometerCore

struct CirclesPage: View {
    @Query(sort: \JournalNote.timestamp, order: .reverse) private var notes: [JournalNote]
    @State private var refreshKey: Int = 0
    @AppStorage("circlesPage.useSelectors") private var useSelectors: Bool = false

    /// Tear down and rebuild the canvas tree this often. Belt-and-suspenders
    /// against any iOS-side cache growth (CoreGraphics / Canvas internals)
    /// that doesn't release between frames. Trivial on phone where sessions
    /// are short; load-bearing for the planned macOS companion that'll run
    /// 24/7 for the auto-screenshot feature.
    private static let hardRefreshInterval: Duration = .seconds(1200)

    var body: some View {
        let snapshots = notes.map(\.snapshot)
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.noteID, $0) })
        let lookup: (UUID) -> JournalNote? = { byID[$0] }

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    modeToggle
                    ForEach(TimeFrame.allCases) { frame in
                        SwiftUI.TimelineView(
                            .animation(
                                minimumInterval: Self.refreshInterval(for: frame),
                                paused: false
                            )
                        ) { context in
                            if useSelectors {
                                selectorPanel(for: frame, date: context.date)
                            } else {
                                TimeCircleView(
                                    timeFrame: frame,
                                    date: context.date,
                                    noteSnapshots: snapshots,
                                    noteLookup: lookup
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .id(refreshKey)

            JournalInput()
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hardRefreshInterval)
                if !Task.isCancelled {
                    refreshKey &+= 1
                }
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 8) {
            modeChip(label: "CIRCLES", active: !useSelectors) { useSelectors = false }
            modeChip(label: "SELECTORS", active: useSelectors) { useSelectors = true }
            Spacer()
        }
    }

    private func modeChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(active ? .black : .white.opacity(0.6))
                .background(Capsule().fill(active ? Color.white : .clear))
                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
        }
    }

    private func selectorPanel(for frame: TimeFrame, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(timeframeLabel(frame))  ·  CONVERGENCE")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))
            ConvergenceSelectorChart(date: date, selectedTimeframe: frame)
                .aspectRatio(0.94, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    private func timeframeLabel(_ tf: TimeFrame) -> String {
        switch tf {
        case .year:        return "YEAR"
        case .moon:        return "MOON"
        case .quarterMoon: return "QUARTER MOON"
        case .day:         return "DAY"
        case .hour:        return "HOUR"
        case .minute:      return "MINUTE"
        }
    }

    /// Indicator angular speed per timeframe varies by ~6 orders of
    /// magnitude. Match the redraw rate to the speed so slow circles
    /// don't waste 30 frames/sec rendering imperceptible motion.
    private static func refreshInterval(for frame: TimeFrame) -> Double {
        switch frame {
        case .minute:      return 1.0 / 15.0   // 15 Hz · 0.4° per frame
        case .hour:        return 1.0 / 2.0    // 2 Hz  · 0.05° per frame
        case .day:         return 2.0          // 0.5 Hz · 0.008° per frame
        case .quarterMoon: return 5.0          // 0.2 Hz
        case .moon:        return 10.0         // 0.1 Hz
        case .year:        return 30.0         // 0.033 Hz
        }
    }
}
