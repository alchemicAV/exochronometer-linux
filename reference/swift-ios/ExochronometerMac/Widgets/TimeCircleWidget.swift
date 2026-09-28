import SwiftUI
import ExochronometerCore

struct LiveTimeCircleWidget: View {
    let timeFrame: TimeFrame
    let snapshotDate: Date?

    var body: some View {
        if let date = snapshotDate {
            TimeCircleWidgetView(timeFrame: timeFrame, date: date)
        } else {
            SwiftUI.TimelineView(
                .animation(
                    minimumInterval: Self.refreshInterval(for: timeFrame),
                    paused: false
                )
            ) { context in
                TimeCircleWidgetView(timeFrame: timeFrame, date: context.date)
            }
        }
    }

    private static func refreshInterval(for tf: TimeFrame) -> Double {
        switch tf {
        case .minute:      return 1.0 / 15.0
        case .hour:        return 1.0 / 2.0
        case .day:         return 2.0
        case .quarterMoon: return 5.0
        case .moon:        return 10.0
        case .year:        return 30.0
        }
    }
}

struct TimeCircleWidgetView: View {
    let timeFrame: TimeFrame
    let date: Date

    /// Inset from the outer ZStack to the circle. The space between
    /// gets used by the node labels Canvas.
    private static let labelInset: CGFloat = 28

    var body: some View {
        let degree = timeFrame.degree(at: date)

        VStack(spacing: 6) {
            Text(timeFrame.label)
                .font(.system(size: 12, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))
            Text(timeFrame.sublabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            ZStack {
                Canvas { ctx, size in
                    Self.drawNodeLabels(
                        in: &ctx,
                        size: size,
                        timeFrame: timeFrame,
                        date: date
                    )
                }

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)

                    GeometryOverlayView(
                        date: date,
                        timeframe: timeFrame,
                        lineWidth: 0.6
                    )

                    GeometryReader { proxy in
                        let radius = min(proxy.size.width, proxy.size.height) / 2
                        let radians = (degree - 90) * .pi / 180
                        let x = proxy.size.width / 2 + radius * cos(radians)
                        let y = proxy.size.height / 2 + radius * sin(radians)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                            .shadow(color: .white.opacity(0.6), radius: 6)
                    }

                    Text(timeFrame.traditionalLabel(at: date))
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(Self.labelInset)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Node date labels

    /// Collect unique node angles across all active shapes (max opacity
    /// wins), then draw a date/time label outside the circle for each.
    /// Same approach iOS uses on the Circles page.
    private static func drawNodeLabels(
        in ctx: inout GraphicsContext,
        size: CGSize,
        timeFrame: TimeFrame,
        date: Date
    ) {
        let cx = size.width / 2
        let cy = size.height / 2
        let labelRadius = min(size.width, size.height) / 2 - 12

        let currentDegree = timeFrame.degree(at: date)
        var nodesByAngle: [Int: Double] = [:]

        for shape in GeometryMath.defaultShapes {
            let opacity = FadeMath.shapeOpacity(
                currentDegree: currentDegree,
                divisions: shape.divisions
            )
            if opacity < 0.05 { continue }
            for i in 0..<shape.divisions {
                let angle = Double(i) * 360.0 / Double(shape.divisions)
                let key = Int(angle.rounded())
                nodesByAngle[key] = max(nodesByAngle[key] ?? 0, opacity)
            }
        }

        let formatter = formatter(for: timeFrame)

        for (key, opacity) in nodesByAngle {
            let nodeDegree = Double(key)
            let nodeDate = dateForNode(degree: nodeDegree, timeFrame: timeFrame, now: date)
            let radians = (nodeDegree - 90) * .pi / 180
            let x = cx + labelRadius * CGFloat(cos(radians))
            let y = cy + labelRadius * CGFloat(sin(radians))

            let text = Text(formatter.string(from: nodeDate))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(opacity * 0.85))
            ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private static func formatter(for timeFrame: TimeFrame) -> DateFormatter {
        let f = DateFormatter()
        switch timeFrame {
        case .year:        f.dateFormat = "M/d"
        case .moon:        f.dateFormat = "M/d"
        case .quarterMoon: f.dateFormat = "M/d HH:mm"
        case .day:         f.dateFormat = "HH:mm"
        case .hour:        f.dateFormat = "HH:mm"
        case .minute:      f.dateFormat = "mm:ss"
        }
        return f
    }

    private static func dateForNode(degree: Double, timeFrame: TimeFrame, now: Date) -> Date {
        let cycleStart = cycleStartDate(for: timeFrame, now: now)
        let offset = (degree / 360.0) * timeFrame.cycleDuration
        return cycleStart.addingTimeInterval(offset)
    }

    private static func cycleStartDate(for timeFrame: TimeFrame, now: Date) -> Date {
        // UTC: must match the indicator's anchor (TimeFrame.degree uses
        // utcCalendar). The label DateFormatter is local-timezone by
        // default, so the rendered string at the indicator's position
        // is the local time of that UTC instant — exactly what the user
        // sees on their wall clock when the indicator is there.
        let cal = TimeFrame.utcCalendar
        switch timeFrame {
        case .year:
            // Solstice-anchored: the year cycle starts at the December
            // solstice boundary, not civil Jan 1 (matches TimeFrame.yearDegree).
            let elapsed = now.timeIntervalSince(PhaseEpoch.decemberSolstice)
            let completed = floor(elapsed / TimeFrame.tropicalYearSeconds)
            return PhaseEpoch.decemberSolstice.addingTimeInterval(completed * TimeFrame.tropicalYearSeconds)
        case .day:
            return cal.startOfDay(for: now)
        case .hour:
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            return cal.date(from: comps) ?? now
        case .minute:
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            return cal.date(from: comps) ?? now
        case .moon:
            let elapsed = now.timeIntervalSince(MoonPhase.referenceNewMoon)
            let cyclesElapsed = elapsed / MoonPhase.synodicMonthSeconds
            let completed = floor(cyclesElapsed)
            return MoonPhase.referenceNewMoon.addingTimeInterval(completed * MoonPhase.synodicMonthSeconds)
        case .quarterMoon:
            let elapsed = now.timeIntervalSince(MoonPhase.referenceNewMoon)
            let cyclesElapsed = elapsed / MoonPhase.quarterMoonSeconds
            let completed = floor(cyclesElapsed)
            return MoonPhase.referenceNewMoon.addingTimeInterval(completed * MoonPhase.quarterMoonSeconds)
        }
    }
}
