import SwiftData
import SwiftUI
import ExochronometerCore

/// Horizontal scroll of snapshot cards. In Snapshot mode, clicking a card
/// pins every other widget to that snapshot's timestamp. In Live mode,
/// cards are read-only history.
struct SnapshotTimelineWidget: View {
    @Query(sort: \JournalNote.timestamp, order: .reverse) private var notes: [JournalNote]
    @EnvironmentObject var state: ChronometerState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if notes.isEmpty {
                emptyState
            } else {
                CaptureAwareScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(notes) { note in
                            card(for: note)
                        }
                    }
                    .padding(.trailing, 12)
                }
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack {
            Text("SNAPSHOTS")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(state.mode == .snapshot ? "TAP TO PIN" : "LIVE  ·  READ-ONLY")
                .font(.system(size: 8, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Text("NO SNAPSHOTS YET")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.4))
                Text("take one from iOS to start populating")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func card(for note: JournalNote) -> some View {
        let selected = state.selectedSnapshotID == note.noteID && state.mode == .snapshot
        Button {
            guard state.mode == .snapshot else { return }
            state.selectSnapshot(note)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateString(note.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(selected ? 0.95 : 0.5))
                Text(timeString(note.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(selected ? 0.95 : 0.7))
                if !note.text.isEmpty {
                    Text(note.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(selected ? 0.9 : 0.65))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                } else {
                    Text("—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(10)
            .frame(width: 180, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? Color.white.opacity(0.18) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(selected ? 0.5 : 0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(state.mode != .snapshot)
    }

    private static let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]

    private func dateString(_ d: Date) -> String {
        let comps = Calendar.current.dateComponents([.month, .day, .year], from: d)
        let m = max(1, min(12, comps.month ?? 1)) - 1
        return "\(Self.monthNames[m]) \(comps.day ?? 0) \(comps.year ?? 0)"
    }

    private func timeString(_ d: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
