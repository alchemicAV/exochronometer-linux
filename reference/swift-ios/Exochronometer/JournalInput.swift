import SwiftUI
import SwiftData
import ExochronometerCore

struct JournalInput: View {
    @Environment(\.modelContext) private var ctx
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $text,
                prompt: Text("SNAPSHOT NOTE  ·  OPTIONAL")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white)
            .tint(.white)
            .submitLabel(.send)
            .focused($focused)
            .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let snapshot = ExoSnapshot.capture(at: now, note: trimmed)

        var degrees: [String: Double] = [:]
        for entry in snapshot.timeframes {
            degrees[entry.timeframe.rawValue] = entry.degree
        }
        let snapshotJSON = (try? snapshot.jsonString()) ?? ""

        ctx.insert(JournalNote(
            timestamp: now,
            text: trimmed,
            degrees: degrees,
            snapshotJSON: snapshotJSON,
            schemaVersion: ExoSnapshot.currentVersion
        ))
        text = ""
    }
}
