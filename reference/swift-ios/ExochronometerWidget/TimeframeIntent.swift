import AppIntents
import ExochronometerCore

public enum WidgetTimeframe: String, AppEnum, CaseIterable {
    case year
    case moon
    case quarterMoon
    case day
    case hour

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Timeframe"
    public static var caseDisplayRepresentations: [WidgetTimeframe: DisplayRepresentation] = [
        .year:        "One Year",
        .moon:        "Moon Cycle",
        .quarterMoon: "Quarter Moon",
        .day:         "One Day",
        .hour:        "One Hour",
    ]

    public var timeFrame: TimeFrame {
        switch self {
        case .year:        return .year
        case .moon:        return .moon
        case .quarterMoon: return .quarterMoon
        case .day:         return .day
        case .hour:        return .hour
        }
    }
}

public struct TimeframeConfigurationIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource = "Choose Timeframe"
    public static var description = IntentDescription("Pick which time cycle this widget displays.")

    @Parameter(title: "Timeframe", default: .day)
    public var timeframe: WidgetTimeframe

    public static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$timeframe)")
    }

    public init() {}
}
