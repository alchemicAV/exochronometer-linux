import Foundation

public enum GeometryMath {

    public static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a)
        var b = abs(b)
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }

    /// Largest odd divisor — the pitch class of an integer multiplier
    /// under octave equivalence. A {n/k} star's winding frequency is
    /// (n/k)·f, so its pitch class is oddPart(n)/oddPart(k); a star
    /// introduces a pitch class the regular polygon lacks iff
    /// oddPart(k) > 1 (k = 2 stars are exact octaves, k = 3 are not).
    public static func oddPart(_ n: Int) -> Int {
        var x = abs(n)
        while x > 1 && x % 2 == 0 { x /= 2 }
        return x
    }

    public struct Edge: Hashable, Sendable {
        public let from: Int
        public let to: Int
        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }

    public struct Shape: Hashable, Identifiable, Sendable {
        public let divisions: Int
        public let skip: Int
        public let path: [Edge]
        public let isRegular: Bool
        public var nodeSpacing: Double { 360.0 / Double(divisions) }
        public var id: String { "\(divisions)-\(skip)" }
    }

    public static func generateShapePath(divisions: Int, skip: Int) -> [Edge] {
        var path: [Edge] = []
        var visited: Set<Int> = []
        for start in 0..<divisions {
            if visited.contains(start) { continue }
            var current = start
            while !visited.contains(current) {
                visited.insert(current)
                let next = (current + skip) % divisions
                path.append(Edge(from: current, to: next))
                current = next
            }
        }
        return path
    }

    public static func buildShapeList(
        minDivisions: Int = 3,
        maxDivisions: Int = 12,
        includeStars: Bool = true
    ) -> [Shape] {
        var shapes: [Shape] = []
        guard minDivisions <= maxDivisions else { return shapes }
        for div in minDivisions...maxDivisions {
            for skip in 1..<div {
                if Double(skip) >= Double(div) / 2 { continue }
                if gcd(div, skip) != 1 { continue }
                let isReg = (skip == 1)
                if !includeStars && !isReg { continue }
                shapes.append(Shape(
                    divisions: div,
                    skip: skip,
                    path: generateShapePath(divisions: div, skip: skip),
                    isRegular: isReg
                ))
            }
        }
        return shapes
    }

    public static func nodeDegrees(divisions: Int) -> [Double] {
        (0..<divisions).map { Double($0) * 360.0 / Double(divisions) }
    }
}
