import SwiftUI

extension GeometryMath {
    /// Shared shape list used by both app and widget (3..8 divisions, with star polygons).
    public static let defaultShapes: [Shape] = buildShapeList(
        minDivisions: 3,
        maxDivisions: 8,
        includeStars: true
    )
}

/// Draws inscribed polygons / star polygons whose nodes "breathe" in and
/// out of view as the indicator dot sweeps past them. When the indicator
/// approaches a vertex that is path-visited in the current rotation of
/// the k-rotation winding cycle (anchored at `PhaseEpoch.instant`), the
/// whole shape fades in: the two legs touching that vertex peak to full
/// opacity, while the rest of the shape rises only to `baselineMax`.
public struct GeometryOverlayView: View {
    public let shapes: [GeometryMath.Shape]
    public let date: Date
    public let timeframe: TimeFrame
    public let lineWidth: CGFloat
    public let strokeColor: Color
    public let fadeFraction: Double
    public let baselineMax: Double

    public init(
        shapes: [GeometryMath.Shape] = GeometryMath.defaultShapes,
        date: Date,
        timeframe: TimeFrame,
        lineWidth: CGFloat = 0.8,
        strokeColor: Color = .white,
        fadeFraction: Double = 0.03,
        baselineMax: Double = 0.35
    ) {
        self.shapes = shapes
        self.date = date
        self.timeframe = timeframe
        self.lineWidth = lineWidth
        self.strokeColor = strokeColor
        self.fadeFraction = fadeFraction
        self.baselineMax = baselineMax
    }

    public var body: some View {
        Canvas { context, size in
            drawShapes(in: &context, size: size)
        }
    }

    private func drawShapes(in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let cycle = timeframe.cycleDuration
        let fadeTime = fadeFraction * cycle

        // Per-frame timeframe state, hoisted out of the inner loops so the
        // calendar lookups happen twice per frame instead of ~n per vertex.
        let currentDegree = timeframe.degree(at: date)
        let cycleBoundary = date.addingTimeInterval(-(currentDegree / 360.0) * cycle)
        let epochDegree = timeframe.degree(at: PhaseEpoch.instant)
        let epochBoundary = PhaseEpoch.instant
            .addingTimeInterval(-(epochDegree / 360.0) * cycle)
        let cyclesSinceEpoch = cycleBoundary.timeIntervalSince(epochBoundary) / cycle
        let cycleIndex = Int(cyclesSinceEpoch.rounded())

        for shape in shapes {
            let points = Self.nodePoints(divisions: shape.divisions, center: center, radius: radius)
            let n = shape.divisions
            let k = shape.skip

            if k == 1 {
                let op = FadeMath.shapeOpacity(
                    currentDegree: currentDegree,
                    divisions: n,
                    fadeFraction: fadeFraction
                )
                guard op > 0.001 else { continue }
                let path = Self.makePath(edges: shape.path, points: points)
                let stroke = strokeColor.opacity(op * 0.85)
                context.stroke(path, with: .color(stroke), lineWidth: lineWidth)
                continue
            }

            let totalCycle = Double(k) * cycle
            let rotation = ((cycleIndex % k) + k) % k
            let kCycleStart = cycleBoundary.addingTimeInterval(-Double(rotation) * cycle)
            let currentOffset = date.timeIntervalSince(kCycleStart)

            var nodeActs = [Double](repeating: 0, count: n)
            for j in 0..<n {
                let vertex = (j * k) % n
                let visitOffset = Double(j) * totalCycle / Double(n)
                var delta = currentOffset - visitOffset
                if delta > totalCycle / 2 { delta -= totalCycle }
                if delta < -totalCycle / 2 { delta += totalCycle }
                if abs(delta) <= fadeTime {
                    nodeActs[vertex] = cos((delta / fadeTime) * (.pi / 2))
                }
            }

            let shapeVisibility = nodeActs.max() ?? 0
            guard shapeVisibility > 0.001 else { continue }
            let baselineOpacity = baselineMax * shapeVisibility

            for edge in shape.path {
                let opFrom = max(nodeActs[edge.from], baselineOpacity)
                let opTo = max(nodeActs[edge.to], baselineOpacity)
                let p0 = points[edge.from]
                let p1 = points[edge.to]
                var leg = Path()
                leg.move(to: p0)
                leg.addLine(to: p1)

                if abs(opFrom - opTo) < 0.01 {
                    let stroke = strokeColor.opacity(((opFrom + opTo) / 2) * 0.85)
                    context.stroke(leg, with: .color(stroke), lineWidth: lineWidth)
                } else {
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: [
                            .init(color: strokeColor.opacity(opFrom * 0.85), location: 0),
                            .init(color: strokeColor.opacity(opTo * 0.85), location: 1),
                        ]),
                        startPoint: p0,
                        endPoint: p1
                    )
                    context.stroke(leg, with: shading, lineWidth: lineWidth)
                }
            }
        }
    }

    private static func nodePoints(divisions: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(divisions)
        for i in 0..<divisions {
            let degrees = Double(i) * 360.0 / Double(divisions) - 90
            let radians = degrees * .pi / 180
            let x = center.x + radius * CGFloat(cos(radians))
            let y = center.y + radius * CGFloat(sin(radians))
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    private static func makePath(edges: [GeometryMath.Edge], points: [CGPoint]) -> Path {
        var path = Path()
        for edge in edges {
            path.move(to: points[edge.from])
            path.addLine(to: points[edge.to])
        }
        return path
    }
}
