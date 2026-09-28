import Foundation

public enum FadeMath {
    /// Returns the shortest angular distance between two angles, in [0, 180].
    public static func circularDistance(_ a: Double, _ b: Double) -> Double {
        var diff = a - b
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return abs(diff)
    }

    /// Cosine-eased opacity centered on `targetDegree`. fadeFraction is the
    /// half-window expressed as a fraction of 360° (0.03 = 10.8° window).
    public static func opacity(
        currentDegree: Double,
        targetDegree: Double,
        fadeFraction: Double = 0.03
    ) -> Double {
        let fadeWindow = fadeFraction * 360
        let dist = circularDistance(currentDegree, targetDegree)
        if dist > fadeWindow { return 0 }
        return cos((dist / fadeWindow) * (.pi / 2))
    }

    /// Best opacity across all `divisions` evenly-spaced nodes.
    public static func shapeOpacity(
        currentDegree: Double,
        divisions: Int,
        fadeFraction: Double = 0.03
    ) -> Double {
        var best = 0.0
        for i in 0..<divisions {
            let nodeDeg = Double(i) * 360.0 / Double(divisions)
            let op = opacity(
                currentDegree: currentDegree,
                targetDegree: nodeDeg,
                fadeFraction: fadeFraction
            )
            if op > best { best = op }
        }
        return best
    }

    /// Seconds until an overtone (timeframe + divisions, optionally with a
    /// winding skip) exits its current fade window. Returns nil when the
    /// tone isn't inside any fade window right now (i.e. it's not active).
    /// For fundamentals (divisions == 1) returns nil since they never fade
    /// out. For winding tones (skip with an odd factor) the active window
    /// is the path-visit of the {n/k} traversal, not bare node proximity.
    public static func timeUntilOvertoneExit(
        timeframe: TimeFrame,
        divisions: Int,
        skip: Int = 1,
        at date: Date,
        fadeFraction: Double = 0.03
    ) -> TimeInterval? {
        guard divisions > 1 else { return nil }

        if skip > 1 {
            return timeUntilWindingExit(
                timeframe: timeframe,
                divisions: divisions,
                skip: skip,
                at: date,
                fadeFraction: fadeFraction
            )
        }

        let currentDeg = timeframe.degree(at: date)
        let fadeWindow = fadeFraction * 360.0

        var bestExitDelta: Double = .infinity
        for i in 0..<divisions {
            let node = Double(i) * 360.0 / Double(divisions)
            var delta = node - currentDeg
            while delta < -180 { delta += 360 }
            while delta > 180 { delta -= 360 }

            if delta >= -fadeWindow && delta < fadeWindow {
                let exitDelta = delta + fadeWindow
                if exitDelta < bestExitDelta {
                    bestExitDelta = exitDelta
                }
            }
        }

        guard bestExitDelta.isFinite else { return nil }
        let degreesPerSecond = 360.0 / timeframe.cycleDuration
        return bestExitDelta / degreesPerSecond
    }

    /// Winding-aware exit time: mirrors `nodeActivation`'s visit math.
    /// Finds the path-visit window currently containing `date` and
    /// returns the time until it closes.
    private static func timeUntilWindingExit(
        timeframe: TimeFrame,
        divisions n: Int,
        skip k: Int,
        at date: Date,
        fadeFraction: Double
    ) -> TimeInterval? {
        let cycle = timeframe.cycleDuration
        guard cycle > 0 else { return nil }
        let state = TimeframeState(timeframe: timeframe, date: date)

        let totalCycle = Double(k) * cycle
        let rotation = ((state.cycleIndex % k) + k) % k
        let kCycleStart = state.cycleBoundary.addingTimeInterval(-Double(rotation) * cycle)
        let currentOffset = state.date.timeIntervalSince(kCycleStart)
        let fadeTime = fadeFraction * cycle

        var bestExit: TimeInterval = .infinity
        for pathStep in 0..<n {
            let visitOffset = Double(pathStep) * totalCycle / Double(n)
            var delta = currentOffset - visitOffset
            if delta > totalCycle / 2 { delta -= totalCycle }
            if delta < -totalCycle / 2 { delta += totalCycle }

            if abs(delta) <= fadeTime {
                let exit = fadeTime - delta
                if exit < bestExit { bestExit = exit }
            }
        }
        return bestExit.isFinite ? bestExit : nil
    }

    /// Precomputed per-(timeframe, date) state used by `nodeActivation`.
    /// All inputs that don't depend on shape/vertex collapse into this
    /// struct so the hot loop doesn't repeat Calendar lookups per vertex.
    public struct TimeframeState {
        public let timeframe: TimeFrame
        public let date: Date
        public let currentDegree: Double
        public let cycleBoundary: Date
        public let cycleIndex: Int

        public init(timeframe: TimeFrame, date: Date, epoch: Date = PhaseEpoch.instant) {
            self.timeframe = timeframe
            self.date = date
            let cycle = timeframe.cycleDuration
            let currentDegree = timeframe.degree(at: date)
            self.currentDegree = currentDegree
            let cycleBoundary = date.addingTimeInterval(-(currentDegree / 360.0) * cycle)
            self.cycleBoundary = cycleBoundary
            let epochDegree = timeframe.degree(at: epoch)
            let epochBoundary = epoch.addingTimeInterval(-(epochDegree / 360.0) * cycle)
            let cyclesSinceEpoch = cycleBoundary.timeIntervalSince(epochBoundary) / cycle
            self.cycleIndex = Int(cyclesSinceEpoch.rounded())
        }
    }

    /// Activation level for a single vertex of `shape`.
    ///
    /// The k-cycle is anchored two ways at once:
    ///   - Each individual cycle starts at the timeframe's natural
    ///     boundary (indicator = 0°), so path-visits coincide with the
    ///     indicator passing the vertex's geometric angle.
    ///   - The rotation index within the k-cycle is counted from the
    ///     epoch's nearest boundary, so the rotation alternation is
    ///     globally consistent.
    ///
    /// This makes vertex highlights sit directly under the indicator
    /// (instead of being phase-shifted by the epoch's offset from
    /// midnight / top-of-hour / Jan 1 / etc.) while still respecting
    /// the n:k winding pattern. Vertex 0's path-visit lands exactly on
    /// the k-cycle boundary, so its fade wraps across the boundary
    /// continuously.
    public static func nodeActivation(
        shape: GeometryMath.Shape,
        vertexIndex: Int,
        date: Date,
        timeframe: TimeFrame,
        fadeFraction: Double = 0.03,
        epoch: Date = PhaseEpoch.instant
    ) -> Double {
        nodeActivation(
            shape: shape,
            vertexIndex: vertexIndex,
            state: TimeframeState(timeframe: timeframe, date: date, epoch: epoch),
            fadeFraction: fadeFraction
        )
    }

    /// Fast-path variant: caller has already built a `TimeframeState` for
    /// the current (timeframe, date) pair and is iterating over many
    /// vertices/shapes — skips the Calendar lookups otherwise repeated
    /// once per vertex.
    public static func nodeActivation(
        shape: GeometryMath.Shape,
        vertexIndex: Int,
        state: TimeframeState,
        fadeFraction: Double = 0.03
    ) -> Double {
        let n = shape.divisions
        let k = shape.skip
        let cycle = state.timeframe.cycleDuration
        guard cycle > 0 else { return 0 }

        var pathStep = -1
        for j in 0..<n where (j * k) % n == vertexIndex {
            pathStep = j
            break
        }
        guard pathStep >= 0 else { return 0 }

        let totalCycle = Double(k) * cycle
        let visitOffset = Double(pathStep) * totalCycle / Double(n)
        let rotation = ((state.cycleIndex % k) + k) % k
        let kCycleStart = state.cycleBoundary.addingTimeInterval(-Double(rotation) * cycle)
        let currentOffset = state.date.timeIntervalSince(kCycleStart)

        var delta = currentOffset - visitOffset
        if delta > totalCycle / 2 { delta -= totalCycle }
        if delta < -totalCycle / 2 { delta += totalCycle }

        let fadeTime = fadeFraction * cycle
        if abs(delta) > fadeTime { return 0 }
        return cos((delta / fadeTime) * (.pi / 2))
    }
}
