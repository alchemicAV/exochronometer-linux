import Foundation

/// JSON payload that captures the full universal state at a moment in time.
/// Designed to be the same on iOS and the macOS companion so a snapshot
/// taken on phone can be opened on the Mac and vice versa.
///
/// v1 captures everything that's a pure function of `timestamp` (timeframes,
/// moon, geometry harmonics with JI mapping). Per-page UI state (exclusions,
/// scale modes, etc.) is intentionally NOT in v1 — those are user
/// preferences, not state of the moment, and the companion can re-derive
/// any computed view from this raw data.
///
/// v2 (2026-06): year phase re-anchored to the December solstice with the
/// mean tropical year, and the universal epoch moved to the 2014-12-22
/// solstice new moon. Degrees recorded under v1 are not comparable to v2.
public struct ExoSnapshot: Codable, Sendable, Identifiable {
    public static let currentVersion: Int = 2

    public let version: Int
    public let id: UUID
    public let timestamp: Date
    public let timezoneIdentifier: String
    public let note: String
    public let timeframes: [TimeframeSnapshot]
    public let moon: MoonSnapshot
    public let harmonics: [GeometryHarmonicSnapshot]

    public init(
        version: Int = ExoSnapshot.currentVersion,
        id: UUID = UUID(),
        timestamp: Date,
        timezoneIdentifier: String,
        note: String = "",
        timeframes: [TimeframeSnapshot],
        moon: MoonSnapshot,
        harmonics: [GeometryHarmonicSnapshot]
    ) {
        self.version = version
        self.id = id
        self.timestamp = timestamp
        self.timezoneIdentifier = timezoneIdentifier
        self.note = note
        self.timeframes = timeframes
        self.moon = moon
        self.harmonics = harmonics
    }

    /// Capture the moment. Pure — derives everything from `date` + epoch
    /// constants. Safe to call on the main thread.
    public static func capture(at date: Date = .now, note: String = "") -> ExoSnapshot {
        let tzID = TimeZone.current.identifier

        let timeframes = TimeFrame.allCases.map { tf in
            TimeframeSnapshot(
                timeframe: tf,
                degree: tf.degree(at: date),
                cycleDurationSeconds: tf.cycleDuration,
                traditionalLabel: tf.traditionalLabel(at: date)
            )
        }

        let phase = MoonPhase.phase(at: date)
        let moon = MoonSnapshot(
            phase: phase,
            phaseName: MoonPhase.phaseName(forPhase: phase),
            moonDegree: MoonPhase.moonDegree(at: date),
            quarterMoonDegree: MoonPhase.quarterMoonDegree(at: date)
        )

        var harmonics: [GeometryHarmonicSnapshot] = []
        harmonics.reserveCapacity(TimeFrame.allCases.count * GeometryMath.defaultShapes.count)
        for tf in TimeFrame.allCases {
            for shape in GeometryMath.defaultShapes {
                let period = tf.cycleDuration * Double(shape.skip) / Double(shape.divisions)
                let frequency = period > 0 ? 1.0 / period : 0
                let ji = JustIntonation.closestNote(frequency: frequency)
                harmonics.append(GeometryHarmonicSnapshot(
                    timeframe: tf,
                    divisions: shape.divisions,
                    skip: shape.skip,
                    periodSeconds: period,
                    frequencyHz: frequency,
                    jiNoteName: ji.noteName,
                    centsDeltaFromA432: ji.centsDelta
                ))
            }
        }

        return ExoSnapshot(
            timestamp: date,
            timezoneIdentifier: tzID,
            note: note,
            timeframes: timeframes,
            moon: moon,
            harmonics: harmonics
        )
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(from jsonString: String) throws -> ExoSnapshot {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Snapshot JSON is not valid UTF-8"
            ))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExoSnapshot.self, from: data)
    }
}

public struct TimeframeSnapshot: Codable, Sendable {
    public let timeframe: TimeFrame
    public let degree: Double
    public let cycleDurationSeconds: TimeInterval
    public let traditionalLabel: String

    public init(timeframe: TimeFrame, degree: Double, cycleDurationSeconds: TimeInterval, traditionalLabel: String) {
        self.timeframe = timeframe
        self.degree = degree
        self.cycleDurationSeconds = cycleDurationSeconds
        self.traditionalLabel = traditionalLabel
    }
}

public struct MoonSnapshot: Codable, Sendable {
    public let phase: Double
    public let phaseName: String
    public let moonDegree: Double
    public let quarterMoonDegree: Double

    public init(phase: Double, phaseName: String, moonDegree: Double, quarterMoonDegree: Double) {
        self.phase = phase
        self.phaseName = phaseName
        self.moonDegree = moonDegree
        self.quarterMoonDegree = quarterMoonDegree
    }
}

public struct GeometryHarmonicSnapshot: Codable, Sendable {
    public let timeframe: TimeFrame
    public let divisions: Int
    public let skip: Int
    public let periodSeconds: TimeInterval
    public let frequencyHz: Double
    public let jiNoteName: String
    public let centsDeltaFromA432: Double

    public init(
        timeframe: TimeFrame,
        divisions: Int,
        skip: Int,
        periodSeconds: TimeInterval,
        frequencyHz: Double,
        jiNoteName: String,
        centsDeltaFromA432: Double
    ) {
        self.timeframe = timeframe
        self.divisions = divisions
        self.skip = skip
        self.periodSeconds = periodSeconds
        self.frequencyHz = frequencyHz
        self.jiNoteName = jiNoteName
        self.centsDeltaFromA432 = centsDeltaFromA432
    }
}
