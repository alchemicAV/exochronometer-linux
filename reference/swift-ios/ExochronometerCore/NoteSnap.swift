import Foundation

public struct NoteSnapshot: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let degrees: [String: Double]

    public init(id: UUID, timestamp: Date, degrees: [String: Double]) {
        self.id = id
        self.timestamp = timestamp
        self.degrees = degrees
    }

    public func degree(for frame: TimeFrame) -> Double? {
        degrees[frame.rawValue]
    }
}

public enum NoteSnap {
    public struct Node: Identifiable, Sendable, Equatable {
        public let degree: Double
        public let noteIDs: [UUID]
        public var id: Int { Int(degree.rounded()) }
    }

    /// Snap each note to the nearest geometry node for each shape, within
    /// (360 / divisions) / 4 of that node. A single note can light up
    /// multiple nodes across different shapes. Filtered to the lookback
    /// window (`lookbackCycles * circle.cycleDuration`).
    public static func snap(
        notes: [NoteSnapshot],
        circle: TimeFrame,
        shapes: [GeometryMath.Shape] = GeometryMath.defaultShapes,
        lookbackCycles: Int = 6,
        now: Date = .now
    ) -> [Node] {
        guard !notes.isEmpty, !shapes.isEmpty else { return [] }
        let lookback = Double(lookbackCycles) * circle.cycleDuration
        let recent = notes.filter { now.timeIntervalSince($0.timestamp) <= lookback }
        guard !recent.isEmpty else { return [] }

        var map: [Int: (degree: Double, ids: [UUID])] = [:]

        for shape in shapes {
            let nodeDegrees = GeometryMath.nodeDegrees(divisions: shape.divisions)
            let maxSnap = (360.0 / Double(shape.divisions)) / 4

            for note in recent {
                guard let noteDeg = note.degree(for: circle) else { continue }
                var bestNode = nodeDegrees[0]
                var bestDist = Double.infinity
                for nd in nodeDegrees {
                    var d = abs(noteDeg - nd)
                    if d > 180 { d = 360 - d }
                    if d < bestDist {
                        bestDist = d
                        bestNode = nd
                    }
                }
                if bestDist > maxSnap { continue }

                let key = Int(bestNode.rounded())
                if var existing = map[key] {
                    if !existing.ids.contains(note.id) {
                        existing.ids.append(note.id)
                        map[key] = existing
                    }
                } else {
                    map[key] = (bestNode, [note.id])
                }
            }
        }

        return map.values.map { Node(degree: $0.degree, noteIDs: $0.ids) }
    }

    /// Breathing opacity for a snapped node: max across all shapes that
    /// have a vertex within 1° of this node degree.
    public static func nodeOpacity(
        nodeDegree: Double,
        currentDegree: Double,
        shapes: [GeometryMath.Shape] = GeometryMath.defaultShapes,
        fadeFraction: Double = 0.03
    ) -> Double {
        var best = 0.0
        for shape in shapes {
            let nodeDegrees = GeometryMath.nodeDegrees(divisions: shape.divisions)
            for nd in nodeDegrees {
                var d = abs(nodeDegree - nd)
                if d > 180 { d = 360 - d }
                if d < 1 {
                    let op = FadeMath.shapeOpacity(
                        currentDegree: currentDegree,
                        divisions: shape.divisions,
                        fadeFraction: fadeFraction
                    )
                    if op > best { best = op }
                    break
                }
            }
        }
        return best
    }
}
