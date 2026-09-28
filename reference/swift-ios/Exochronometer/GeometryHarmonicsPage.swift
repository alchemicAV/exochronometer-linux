import SwiftUI
import ExochronometerCore

struct GeometryHarmonicsPage: View {
    @State private var selectedTimeframe: TimeFrame = .day
    @State private var showingAllHarmonics = false

    private let shapes: [GeometryMath.Shape] = GeometryMath.defaultShapes
    private let gridColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: 3
    )

    var body: some View {
        VStack(spacing: 12) {
            timeframeSelector
                .padding(.top, 4)
                .padding(.horizontal, 16)

            allHarmonicsRow
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(shapes) { shape in
                        HarmonicRow(shape: shape, timeframe: selectedTimeframe)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingAllHarmonics) {
            AllHarmonicsSheet(shapes: shapes)
        }
    }

    private var timeframeSelector: some View {
        LazyVGrid(columns: gridColumns, spacing: 6) {
            ForEach(TimeFrame.allCases) { tf in
                Button {
                    selectedTimeframe = tf
                } label: {
                    Text(tf.label)
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedTimeframe == tf ? .black : .white.opacity(0.7))
                        .background(
                            Capsule()
                                .fill(selectedTimeframe == tf ? Color.white : .clear)
                        )
                        .overlay(
                            Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    private var allHarmonicsRow: some View {
        HStack {
            Spacer()
            Button {
                showingAllHarmonics = true
            } label: {
                Text("ALL HARMONICS")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white.opacity(0.85))
                    .overlay(
                        Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5)
                    )
            }
        }
    }
}

private struct HarmonicRow: View {
    let shape: GeometryMath.Shape
    let timeframe: TimeFrame

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 0.6)
                PolygonView(shape: shape)
                    .padding(2)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ratioLabel)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(shapeName)
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text("period: \(periodString)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text("interval: \(intervalString)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
    }

    private var ratioLabel: String {
        "\(shape.divisions):\(shape.skip)"
    }

    private var harmonicPeriodSeconds: Double {
        timeframe.cycleDuration * Double(shape.skip) / Double(shape.divisions)
    }

    private var periodString: String {
        FrequencyMath.formatDuration(harmonicPeriodSeconds)
    }

    private var intervalString: String {
        let name = intervalName(n: shape.divisions, k: shape.skip)
        return "\(name) (\(shape.divisions):\(shape.skip))"
    }

    private var shapeName: String {
        switch (shape.divisions, shape.skip) {
        case (3, 1): return "TRIANGLE"
        case (4, 1): return "SQUARE"
        case (5, 1): return "PENTAGON"
        case (5, 2): return "PENTAGRAM"
        case (6, 1): return "HEXAGON"
        case (7, 1): return "HEPTAGON"
        case (7, 2): return "HEPTAGRAM {7/2}"
        case (7, 3): return "HEPTAGRAM {7/3}"
        case (8, 1): return "OCTAGON"
        case (8, 3): return "OCTAGRAM"
        default:     return "{\(shape.divisions)/\(shape.skip)}"
        }
    }
}

private struct PolygonView: View {
    let shape: GeometryMath.Shape

    var body: some View {
        Canvas { ctx, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let points = nodePoints(divisions: shape.divisions, center: center, radius: radius)
            let path = makePath(edges: shape.path, points: points)
            ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1)
        }
    }

    private func nodePoints(divisions: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(divisions)
        for i in 0..<divisions {
            let degrees = Double(i) * 360.0 / Double(divisions) - 90
            let radians = degrees * .pi / 180
            points.append(CGPoint(
                x: center.x + radius * CGFloat(cos(radians)),
                y: center.y + radius * CGFloat(sin(radians))
            ))
        }
        return points
    }

    private func makePath(edges: [GeometryMath.Edge], points: [CGPoint]) -> Path {
        var path = Path()
        for edge in edges {
            path.move(to: points[edge.from])
            path.addLine(to: points[edge.to])
        }
        return path
    }
}

// MARK: - All Harmonics Sheet

private struct AllHarmonicsSheet: View {
    let shapes: [GeometryMath.Shape]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("frequency · period · closest 5-limit JI note vs A=432 Hz")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    ForEach(TimeFrame.allCases) { tf in
                        section(for: tf)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("ALL HARMONICS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section(for tf: TimeFrame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(tf.label)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(tf.sublabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(shapes) { shape in
                    AllHarmonicsRow(timeframe: tf, shape: shape)
                    Divider().background(Color.white.opacity(0.08))
                }
            }
        }
    }
}

private struct AllHarmonicsRow: View {
    let timeframe: TimeFrame
    let shape: GeometryMath.Shape

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(shape.divisions):\(shape.skip)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(FrequencyMath.format(frequency))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Text("period: \(FrequencyMath.formatDuration(period))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(match.noteName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                Text(centsLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var period: Double {
        timeframe.cycleDuration * Double(shape.skip) / Double(shape.divisions)
    }

    private var frequency: Double {
        period > 0 ? 1.0 / period : 0
    }

    private var match: JustIntonation.Match {
        JustIntonation.closestNote(frequency: frequency)
    }

    private var centsLabel: String {
        let cents = match.centsDelta
        let sign = cents >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", cents))¢"
    }
}

// MARK: - Interval naming

/// Octave-reduces n:k until n/k is in [1, 2), then names the resulting
/// simple ratio. {n/k} polygons share the same name as their octave
/// multiples — e.g. {7/1}, {7/2} both reduce to 7:4 (Harmonic Seventh).
private func intervalName(n: Int, k: Int) -> String {
    let num = n
    var den = k
    while num >= 2 * den { den *= 2 }
    switch (num, den) {
    case (1, 1):   return "Unison"
    case (2, 1):   return "Octave"
    case (3, 2):   return "Perfect Fifth"
    case (4, 3):   return "Perfect Fourth"
    case (5, 3):   return "Major Sixth"
    case (5, 4):   return "Major Third"
    case (6, 5):   return "Minor Third"
    case (7, 4):   return "Harmonic Seventh"
    case (7, 5):   return "Septimal Tritone"
    case (7, 6):   return "Septimal Subminor Third"
    case (8, 5):   return "Minor Sixth"
    case (8, 7):   return "Septimal Major Second"
    case (9, 5):   return "Minor Seventh"
    case (9, 7):   return "Septimal Major Third"
    case (9, 8):   return "Major Second"
    case (15, 8):  return "Major Seventh"
    case (16, 15): return "Minor Second"
    case (45, 32): return "Tritone"
    default:       return "\(num):\(den) ratio"
    }
}

