import Foundation
import SwiftUI
import ExochronometerCore

@MainActor
final class ChronometerState: ObservableObject {
    enum Mode: String, Codable { case live, snapshot, timeTravel, headless }

    private static let modeKey = "exo.mac.chronometer.mode"
    private static let selectedSnapshotIDKey = "exo.mac.chronometer.selectedSnapshotID"
    private static let selectedSnapshotDateKey = "exo.mac.chronometer.selectedSnapshotDate"
    private static let timeTravelDateKey = "exo.mac.chronometer.timeTravelDate"

    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    @Published var selectedSnapshotID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedSnapshotID?.uuidString, forKey: Self.selectedSnapshotIDKey)
        }
    }

    @Published var selectedSnapshotDate: Date? {
        didSet { UserDefaults.standard.set(selectedSnapshotDate, forKey: Self.selectedSnapshotDateKey) }
    }

    /// User-picked moment for time-travel mode. Widgets render against
    /// this exact instant. Persisted so the chosen date survives
    /// launches, just like the selected snapshot date.
    @Published var timeTravelDate: Date? {
        didSet { UserDefaults.standard.set(timeTravelDate, forKey: Self.timeTravelDateKey) }
    }

    /// When snapshot mode is entered without a stored snapshot selected,
    /// widgets freeze at this date (set to the moment of mode toggle) so
    /// they don't keep ticking like they're in live mode.
    @Published var pendingSnapshotDate: Date?

    /// Tracks the timeline widget the app auto-spawned when entering
    /// snapshot mode. Set so we can remove it again when leaving snapshot
    /// mode IF the user didn't manually add their own.
    @Published var autoAddedTimelineID: UUID?

    /// Amount the rest of the canvas was shifted down when auto-adding
    /// the timeline widget. We reverse this shift on auto-remove so
    /// other widgets return to their original positions.
    @Published var autoAddedShift: CGFloat = 0

    /// The date widgets should render at. Nil means "drive yourselves
    /// off TimelineView" — i.e. live mode.
    var effectiveSnapshotDate: Date? {
        switch mode {
        case .live:        return nil
        case .snapshot:    return selectedSnapshotDate ?? pendingSnapshotDate
        case .timeTravel:  return timeTravelDate
        // Headless is live time with rendering suppressed — triggers
        // keep evaluating against "now".
        case .headless:    return nil
        }
    }

    init() {
        // Restore mode
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let m = Mode(rawValue: raw) {
            self.mode = m
        } else {
            self.mode = .live
        }
        // Restore selected snapshot (both id and date so widgets can pin
        // immediately on launch without needing to re-query SwiftData).
        if let uuidStr = UserDefaults.standard.string(forKey: Self.selectedSnapshotIDKey),
           let uuid = UUID(uuidString: uuidStr) {
            self.selectedSnapshotID = uuid
        }
        if let date = UserDefaults.standard.object(forKey: Self.selectedSnapshotDateKey) as? Date {
            self.selectedSnapshotDate = date
        }
        if let date = UserDefaults.standard.object(forKey: Self.timeTravelDateKey) as? Date {
            self.timeTravelDate = date
        }
    }

    func selectSnapshot(_ note: JournalNote) {
        selectedSnapshotID = note.noteID
        selectedSnapshotDate = note.timestamp
        pendingSnapshotDate = nil
    }

    func clearSnapshot() {
        selectedSnapshotID = nil
        selectedSnapshotDate = nil
    }
}
