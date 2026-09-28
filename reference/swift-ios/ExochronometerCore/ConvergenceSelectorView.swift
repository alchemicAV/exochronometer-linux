import SwiftUI

/// Shared SwiftUI chart for both Mac widget instances and the iOS pages.
/// Renders the (divisions × degrees) integer-convergence pattern as gray
/// background dots, then lights up white-with-glow on every cell whose
/// angle matches an active geometry. Irregular polygons (7-gon family
/// etc.) whose angles don't snap to the 10° grid get off-grid dots at
/// their exact angles with a faint guide tick.
///
/// `selectedTimeframe` controls scope:
/// - `nil`: all timeframes merged (combined view)
/// - `.year` / `.moon` / etc.: single-timeframe view
public struct ConvergenceSelectorChart: View {
    public let date: Date
    public let selectedTimeframe: TimeFrame?
    public let excludedTimeframes: Set<TimeFrame>
    public let maxDivisions: Int
    public let degreeStep: Double
    public let backgroundOpacity: Double

    private let timeframeOrder: [TimeFrame] = [.year, .moon, .quarterMoon, .day, .hour, .minute]
    private let shapes: [GeometryMath.Shape] = GeometryMath.defaultShapes

    /// Pre-enumerated background dot coordinates. The same `(div, deg)`
    /// pairs every frame regardless of canvas size — only their pixel
    /// positions change. Computed once at type-load.
    private static let backgroundCoords: [(div: Int, deg: Double)] = {
        let maxDiv = 35
        let step: Double = 10
        let stepInt = Int(step)
        let degRows = Int(360.0 / step) - 1
        var coords: [(div: Int, deg: Double)] = []
        // On-grid integer-convergences.
        for div in 3...maxDiv {
            for i in 1...degRows {
                let deg = i * stepInt
                if (deg * div) % 360 == 0 {
                    coords.append((div, Double(deg)))
                }
            }
        }
        // Off-grid: each valid (n, k) shape's angle plus its 360° complement.
        for shape in GeometryMath.defaultShapes {
            let primary = Double(shape.skip) * 360.0 / Double(shape.divisions)
            let snapped = (primary / step).rounded() * step
            guard abs(primary - snapped) >= 0.01 else { continue }
            for angle in [primary, 360.0 - primary] {
                var mult = 1
                while shape.divisions * mult <= maxDiv {
                    coords.append((shape.divisions * mult, angle))
                    mult += 1
                }
            }
        }
        return coords
    }()

    public init(
        date: Date,
        selectedTimeframe: TimeFrame? = nil,
        excludedTimeframes: Set<TimeFrame> = [],
        maxDivisions: Int = 35,
        degreeStep: Double = 10,
        backgroundOpacity: Double = 0.225
    ) {
        self.date = date
        self.selectedTimeframe = selectedTimeframe
        self.excludedTimeframes = excludedTimeframes
        self.maxDivisions = maxDivisions
        self.degreeStep = degreeStep
        self.backgroundOpacity = backgroundOpacity
    }

    public var body: some View {
        Canvas { ctx, size in
            let layout = Layout(
                size: size,
                maxDivisions: maxDivisions,
                degreeStep: degreeStep
            )
            drawAxes(in: &ctx, layout: layout)
            drawBackground(in: &ctx, layout: layout)
            drawActive(in: &ctx, layout: layout)
        }
    }

    // MARK: layout

    private struct Layout {
        let plot: CGRect
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let maxDivisions: Int
        let degreeStep: Double

        init(size: CGSize, maxDivisions: Int, degreeStep: Double) {
            let leftMargin: CGFloat = 28
            let topMargin: CGFloat = 18
            let rightMargin: CGFloat = 6
            let bottomMargin: CGFloat = 6
            let cols = maxDivisions - 2
            let rows = Int(360.0 / degreeStep) - 1
            let w = max(0, size.width - leftMargin - rightMargin)
            let h = max(0, size.height - topMargin - bottomMargin)
            self.cellWidth = w / CGFloat(cols)
            self.cellHeight = h / CGFloat(rows)
            self.plot = CGRect(x: leftMargin, y: topMargin, width: w, height: h)
            self.maxDivisions = maxDivisions
            self.degreeStep = degreeStep
        }

        func position(div: Int, deg: Double) -> CGPoint {
            let x = plot.minX + (CGFloat(div - 3) + 0.5) * cellWidth
            let y = plot.minY + CGFloat(deg / 360.0) * plot.height
            return CGPoint(x: x, y: y)
        }
    }

    // MARK: drawing

    private func drawAxes(in ctx: inout GraphicsContext, layout: Layout) {
        for div in stride(from: 5, through: maxDivisions, by: 5) {
            let pos = layout.position(div: div, deg: 0)
            let label = Text("\(div)")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            ctx.draw(label, at: CGPoint(x: pos.x, y: layout.plot.minY - 8), anchor: .center)
        }
        for degInt in stride(from: 30, through: 330, by: 30) {
            let deg = Double(degInt)
            let pos = layout.position(div: 3, deg: deg)
            let label = Text("\(degInt)°")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            ctx.draw(label, at: CGPoint(x: layout.plot.minX - 14, y: pos.y), anchor: .center)
        }
    }

    private func drawBackground(in ctx: inout GraphicsContext, layout: Layout) {
        let dotRadius: CGFloat = max(1.0, min(layout.cellWidth, layout.cellHeight) * 0.22)
        // Build one Path containing every background ellipse and fill it
        // in a single CoreGraphics call. Cuts per-frame fill overhead by
        // roughly the dot count (≈300×).
        var path = Path()
        for coord in Self.backgroundCoords where coord.div <= maxDivisions {
            let pos = layout.position(div: coord.div, deg: coord.deg)
            path.addEllipse(in: CGRect(
                x: pos.x - dotRadius, y: pos.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            ))
        }
        ctx.fill(path, with: .color(.white.opacity(backgroundOpacity)))
    }

    private func drawActive(in ctx: inout GraphicsContext, layout: Layout) {
        let activations = computeActivations()
        let dotRadius: CGFloat = max(1.5, min(layout.cellWidth, layout.cellHeight) * 0.28)
        let haloRadius: CGFloat = dotRadius * 2.6

        let offGridAngles = Set(activations
            .filter { !$0.onGrid }
            .map { quantize($0.deg) })
        for q in offGridAngles {
            let deg = Double(q) / 100.0
            let pos = layout.position(div: 3, deg: deg)
            var line = Path()
            line.move(to: CGPoint(x: layout.plot.minX, y: pos.y))
            line.addLine(to: CGPoint(x: layout.plot.maxX, y: pos.y))
            ctx.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
        }

        for act in activations {
            let pos = layout.position(div: act.div, deg: act.deg)
            let haloRect = CGRect(
                x: pos.x - haloRadius, y: pos.y - haloRadius,
                width: haloRadius * 2, height: haloRadius * 2
            )
            ctx.fill(Path(ellipseIn: haloRect), with: .color(.white.opacity(0.18 * act.glow)))
            let innerRect = CGRect(
                x: pos.x - dotRadius * 1.6, y: pos.y - dotRadius * 1.6,
                width: dotRadius * 3.2, height: dotRadius * 3.2
            )
            ctx.fill(Path(ellipseIn: innerRect), with: .color(.white.opacity(0.28 * act.glow)))
            let centerRect = CGRect(
                x: pos.x - dotRadius, y: pos.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            )
            ctx.fill(Path(ellipseIn: centerRect), with: .color(.white.opacity(min(1.0, 0.55 + 0.45 * act.glow))))
        }
    }

    // MARK: activation

    private struct Activation {
        let div: Int
        let deg: Double
        let onGrid: Bool
        let glow: Double
    }

    private struct Cell: Hashable {
        let div: Int
        let degQuantized: Int
    }

    private func quantize(_ deg: Double) -> Int { Int((deg * 100).rounded()) }

    private func contributingTimeframes() -> [TimeFrame] {
        if let only = selectedTimeframe { return [only] }
        return timeframeOrder.filter { !excludedTimeframes.contains($0) }
    }

    private func computeActivations() -> [Activation] {
        var byCell: [Cell: (deg: Double, onGrid: Bool, glow: Double)] = [:]
        // Cap propagation strictly below the chart's last column. The
        // rightmost column (maxDivisions) has no on-grid background dots
        // and reads as edge noise even when off-grid backgrounds exist.
        let activeLimit = maxDivisions - 1

        for tf in contributingTimeframes() {
            // Hoist all (timeframe, date) state out of the per-vertex inner
            // loop. Without this, FadeMath.nodeActivation redoes Calendar
            // lookups for every vertex of every shape, every frame.
            let state = FadeMath.TimeframeState(timeframe: tf, date: date)
            for shape in shapes {
                let op = shapeOpacity(shape: shape, state: state)
                guard op > 0.001 else { continue }
                let primary = Double(shape.skip) * 360.0 / Double(shape.divisions)
                let conjugate = 360.0 - primary
                // {n/k} and {n/(n-k)} describe the same shape traced in
                // opposite directions — light both so the active layer is
                // symmetric around 180° like the background lattice.
                for angle in [primary, conjugate] {
                    if isOnDegreeGrid(angle) {
                        let degInt = Int(angle.rounded())
                        guard degInt > 0, degInt < 360 else { continue }
                        for div in 3...activeLimit where (degInt * div) % 360 == 0 {
                            let key = Cell(div: div, degQuantized: quantize(angle))
                            let prior = byCell[key]?.glow ?? 0
                            byCell[key] = (Double(degInt), true, max(prior, op))
                        }
                    } else {
                        var mult = 1
                        while shape.divisions * mult <= activeLimit {
                            let div = shape.divisions * mult
                            let key = Cell(div: div, degQuantized: quantize(angle))
                            let prior = byCell[key]?.glow ?? 0
                            byCell[key] = (angle, false, max(prior, op))
                            mult += 1
                        }
                    }
                }
            }
        }
        return byCell.map { Activation(div: $0.key.div, deg: $0.value.deg, onGrid: $0.value.onGrid, glow: $0.value.glow) }
    }

    private func shapeOpacity(shape: GeometryMath.Shape, state: FadeMath.TimeframeState) -> Double {
        if shape.skip == 1 {
            return FadeMath.shapeOpacity(currentDegree: state.currentDegree, divisions: shape.divisions)
        }
        var best: Double = 0
        for v in 0..<shape.divisions {
            let a = FadeMath.nodeActivation(shape: shape, vertexIndex: v, state: state)
            if a > best { best = a }
        }
        return best
    }

    private func isOnDegreeGrid(_ angle: Double) -> Bool {
        let snapped = (angle / degreeStep).rounded() * degreeStep
        return abs(angle - snapped) < 0.01
    }
}
