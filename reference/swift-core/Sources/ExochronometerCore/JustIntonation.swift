import Foundation

/// 5-limit just intonation pitches relative to A = 432 Hz.
public enum JustIntonation {
    public static let referenceA: Double = 432.0

    public static let ratios: [(name: String, ratio: Double)] = [
        ("A",  1.0),
        ("A♯", 16.0 / 15.0),
        ("B",  9.0 / 8.0),
        ("C",  6.0 / 5.0),
        ("C♯", 5.0 / 4.0),
        ("D",  4.0 / 3.0),
        ("D♯", 45.0 / 32.0),
        ("E",  3.0 / 2.0),
        ("F",  8.0 / 5.0),
        ("F♯", 5.0 / 3.0),
        ("G",  16.0 / 9.0),
        ("G♯", 15.0 / 8.0),
    ]

    /// Each note's cents-from-A position. Used by the cents wheel to
    /// place its 12 labels at their JI positions instead of at the
    /// equal-tempered 30° intervals.
    public static let labels: [(name: String, cents: Double)] = ratios.map {
        ($0.name, 1200 * log2($0.ratio))
    }

    public struct Match: Codable, Sendable, Equatable {
        public let noteName: String
        public let centsDelta: Double

        public init(noteName: String, centsDelta: Double) {
            self.noteName = noteName
            self.centsDelta = centsDelta
        }
    }

    /// Octave-reduces `frequency` into [referenceA, 2·referenceA), then picks
    /// the JI note nearest in cents. Also probes the next-octave A so a
    /// just-below-octave frequency snaps to A above instead of G♯ way below.
    public static func closestNote(frequency: Double) -> Match {
        guard frequency > 0, frequency.isFinite else {
            return Match(noteName: "—", centsDelta: 0)
        }
        var f = frequency
        while f < referenceA { f *= 2 }
        while f >= 2 * referenceA { f /= 2 }

        var bestName = "A"
        var bestAbsCents = Double.infinity
        var bestSigned = 0.0
        for (name, ratio) in ratios {
            let pitch = ratio * referenceA
            let cents = 1200 * log2(f / pitch)
            if abs(cents) < bestAbsCents {
                bestAbsCents = abs(cents)
                bestSigned = cents
                bestName = name
            }
        }
        let centsToHighA = 1200 * log2(f / (2 * referenceA))
        if abs(centsToHighA) < bestAbsCents {
            bestAbsCents = abs(centsToHighA)
            bestSigned = centsToHighA
            bestName = "A"
        }
        return Match(noteName: bestName, centsDelta: bestSigned)
    }
}
