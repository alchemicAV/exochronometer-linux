import Foundation
import SwiftData

@Model
public final class JournalNote {
    public var noteID: UUID = UUID()
    public var timestamp: Date = Date()
    public var text: String = ""
    public var degrees: [String: Double] = [:]
    public var snapshotJSON: String = ""
    public var schemaVersion: Int = 0

    public init(
        timestamp: Date = .now,
        text: String,
        degrees: [String: Double],
        snapshotJSON: String = "",
        schemaVersion: Int = 0
    ) {
        self.noteID = UUID()
        self.timestamp = timestamp
        self.text = text
        self.degrees = degrees
        self.snapshotJSON = snapshotJSON
        self.schemaVersion = schemaVersion
    }

    public var snapshot: NoteSnapshot {
        NoteSnapshot(id: noteID, timestamp: timestamp, degrees: degrees)
    }

    public var exoSnapshot: ExoSnapshot? {
        guard !snapshotJSON.isEmpty else { return nil }
        return try? ExoSnapshot.decode(from: snapshotJSON)
    }

    /// Delete notes written under an older snapshot schema. Stored degrees
    /// are pure functions of timestamp + the phase constants of their era;
    /// after a re-anchoring (epoch / year-phase change) they no longer
    /// match freshly computed positions. Per project policy pre-release
    /// notes are purged rather than migrated.
    @MainActor
    public static func purgeStaleSchema(in context: ModelContext) {
        let current = ExoSnapshot.currentVersion
        let descriptor = FetchDescriptor<JournalNote>(
            predicate: #Predicate { $0.schemaVersion < current }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        for note in stale { context.delete(note) }
        try? context.save()
    }
}
