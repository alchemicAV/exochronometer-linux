import AppIntents
import WidgetKit

/// Forces an immediate timeline reload for the home-screen widget.
/// Wired to a Button(intent:) wrapping the whole widget face — tapping
/// it re-renders the widget with the current moment instead of opening
/// the app.
struct RefreshChronometerIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Exochronometer"
    static var description = IntentDescription("Re-render the widget with the current moment.")

    /// Keep the system from launching the host app to satisfy the intent.
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "HomeChronometerWidget")
        return .result()
    }
}
