import SwiftUI
import ExochronometerCore

struct NotePanel: View {
    let notes: [JournalNote]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(notes.count) NOTE\(notes.count == 1 ? "" : "S")")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                        .contentShape(Rectangle())
                }
            }

            ForEach(notes.sorted(by: { $0.timestamp > $1.timestamp })) { note in
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(note.timestamp.formatted(.dateTime.month().day().hour().minute()))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2), lineWidth: 0.5))
    }
}
