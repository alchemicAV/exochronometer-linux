import SwiftUI
import SwiftData
import ExochronometerCore

struct TimelinePage: View {
    @Query(sort: \JournalNote.timestamp, order: .reverse) private var notes: [JournalNote]

    @State private var zoomIdx: Int = 2
    private let zoomLevels: [Double] = [0.25, 0.5, 1, 2, 4, 8]
    private var zoom: Double { zoomLevels[zoomIdx] }

    private let pxPerHour: Double = 12
    private let minGap: Double = 44
    private let lineX: CGFloat = 30

    var body: some View {
        ZStack(alignment: .bottom) {
            if notes.isEmpty {
                Text("NO NOTES")
                    .font(.system(size: 12, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                timelineScroll
            }

            zoomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    private var timelineScroll: some View {
        let items = displayItems()

        return ScrollView {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 1)
                    .padding(.leading, lineX)
                    .frame(maxHeight: .infinity)

                VStack(spacing: 0) {
                    ForEach(items) { item in
                        TimelineFlagRow(item: item, lineX: lineX)
                            .padding(.top, item.topPadding)
                    }
                }
            }
            .padding(.bottom, 60)
        }
    }

    private var zoomBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 10) {
                Button(action: zoomOut) {
                    zoomButtonLabel("−")
                }
                .disabled(zoomIdx == 0)
                .opacity(zoomIdx == 0 ? 0.25 : 1)

                Text(zoomLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(minWidth: 36)

                Button(action: zoomIn) {
                    zoomButtonLabel("+")
                }
                .disabled(zoomIdx == zoomLevels.count - 1)
                .opacity(zoomIdx == zoomLevels.count - 1 ? 0.25 : 1)
            }
        }
    }

    private func zoomButtonLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(0.4), lineWidth: 0.5)
            )
    }

    private var zoomLabel: String {
        zoom < 1 ? "\(zoom)x" : "\(Int(zoom))x"
    }

    private func zoomIn() { zoomIdx = min(zoomIdx + 1, zoomLevels.count - 1) }
    private func zoomOut() { zoomIdx = max(zoomIdx - 1, 0) }

    private func displayItems() -> [DisplayItem] {
        guard !notes.isEmpty else { return [] }
        let secondsPerHour: Double = 3600

        var out: [DisplayItem] = []
        for (i, note) in notes.enumerated() {
            let topPad: Double
            if i == 0 {
                topPad = 24
            } else {
                let newerAbove = notes[i - 1]
                let gapSeconds = newerAbove.timestamp.timeIntervalSince(note.timestamp)
                let gapHours = max(0, gapSeconds) / secondsPerHour
                topPad = max(minGap, gapHours * pxPerHour) * zoom
            }
            out.append(DisplayItem(
                id: note.noteID,
                topPadding: topPad,
                text: note.text,
                timestamp: note.timestamp
            ))
        }
        return out
    }
}

private struct DisplayItem: Identifiable {
    let id: UUID
    let topPadding: Double
    let text: String
    let timestamp: Date
}

private struct TimelineFlagRow: View {
    let item: DisplayItem
    let lineX: CGFloat

    private static let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .leading) {
                Color.clear.frame(width: lineX + 24, height: 1)
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .offset(x: lineX - 3, y: 4)
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 16, height: 1)
                    .offset(x: lineX + 4, y: 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.35))
                    Text(timeString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(item.text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.trailing, 20)
    }

    private var dateString: String {
        let comps = Calendar.current.dateComponents([.month, .day], from: item.timestamp)
        let m = max(1, min(12, comps.month ?? 1)) - 1
        return "\(Self.monthNames[m]) \(comps.day ?? 0)"
    }

    private var timeString: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.timestamp)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
