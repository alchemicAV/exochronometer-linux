import SwiftUI
import ExochronometerCore

/// Board widget for the geometric-peak calendar. The 22 months pack into a
/// fixed reading-order grid — `Initia` at the top-left, `Octoz` at the
/// bottom-right — reflowing its column count to the tile's width. Nothing
/// scrolls or re-anchors: the current month is simply highlighted wherever
/// it falls, with today's cell lit. Sized to ~11 wide × 2 tall it shows the
/// whole year at a glance.
struct LivePeakCalendarWidget: View {
    let snapshotDate: Date?

    var body: some View {
        if let date = snapshotDate {
            PeakCalendarWidgetView(date: date)
        } else {
            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                PeakCalendarWidgetView(date: context.date)
            }
        }
    }
}

struct PeakCalendarWidgetView: View {
    let date: Date

    // Taller than wide so the longest month (46 days → 7 rows) fits above
    // the day grid without clipping.
    private let cell = CGSize(width: 184, height: 208)
    private let spacing: CGFloat = 8

    var body: some View {
        let pos = PeakCalendar.position(at: date)
        let months = PeakCalendar.months

        GeometryReader { geo in
            let stepX = cell.width + spacing
            let stepY = cell.height + spacing
            // Column count follows the tile's width; Initia (index 0) always
            // occupies grid cell (row 0, col 0) and the rest follow in order.
            let cols = max(1, Int((geo.size.width + spacing) / stepX))
            let current = pos.monthIndex

            ZStack(alignment: .topLeading) {
                ForEach(months) { month in
                    let i = month.number - 1
                    PeakMonthCell(
                        month: month,
                        highlightedDay: i == current ? pos.dayOfMonth : nil,
                        isCurrent: i == current,
                        compact: true
                    )
                    .frame(width: cell.width, height: cell.height)
                    .offset(
                        x: CGFloat(i % cols) * stepX,
                        y: CGFloat(i / cols) * stepY
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}
