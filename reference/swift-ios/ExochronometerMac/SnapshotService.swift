import Foundation
import SwiftData
import ExochronometerCore

/// Single chokepoint for capturing snapshots on the Mac. Both the manual
/// toolbar button and the (future) automatic screenshot scheduler call
/// `capture(...)` so they end up writing identical records.
@MainActor
enum SnapshotService {
    @discardableResult
    static func capture(
        at date: Date = .now,
        note text: String = "",
        in context: ModelContext
    ) -> JournalNote {
        let snapshot = ExoSnapshot.capture(at: date, note: text)

        var degrees: [String: Double] = [:]
        for entry in snapshot.timeframes {
            degrees[entry.timeframe.rawValue] = entry.degree
        }
        let json = (try? snapshot.jsonString()) ?? ""

        let record = JournalNote(
            timestamp: date,
            text: text,
            degrees: degrees,
            snapshotJSON: json,
            schemaVersion: ExoSnapshot.currentVersion
        )
        context.insert(record)
        return record
    }
}
