import SwiftData
import SwiftUI
import ExochronometerCore

struct SnapshotPopover: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TAKE SNAPSHOT")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))

            Text("Captures the full state at this instant. Note is optional.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(2...5)
                .focused($focused)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("CANCEL") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
                Button("CAPTURE") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(2)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { focused = true }
    }

    private func submit() {
        SnapshotService.capture(
            note: text.trimmingCharacters(in: .whitespacesAndNewlines),
            in: ctx
        )
        text = ""
        dismiss()
    }
}
