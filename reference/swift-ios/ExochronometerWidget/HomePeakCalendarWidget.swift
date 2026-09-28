import SwiftUI
import WidgetKit
import ExochronometerCore

/// Home-screen widget for the geometric-peak calendar: one month at a
/// time, the month containing "now". Days fill in as they pass, today is
/// lit, and when the year phase crosses the next peak the whole face
/// turns over to the new month — no configuration, the calendar decides.
struct HomePeakCalendarWidget: Widget {
    let kind = "HomePeakCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeakCalendarProvider()) { entry in
            HomePeakCalendarView(date: entry.date)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Peak Calendar")
        .description("The current peak month, with today lit. Turns over on its own.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline

struct PeakCalendarEntry: TimelineEntry {
    let date: Date
}

/// Every view here is a pure function of its timestamp, so the timeline is
/// just the list of instants the face changes: the day boundaries. Those
/// are exact (the year phase is linear in absolute time), so nothing is
/// polled and nothing drifts.
struct PeakCalendarProvider: TimelineProvider {
    /// Enough boundaries to cover the longest run WidgetKit is likely to
    /// keep, without leaning on it to reload us mid-month.
    private let entryCount = 12

    func placeholder(in context: Context) -> PeakCalendarEntry {
        PeakCalendarEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PeakCalendarEntry) -> Void) {
        completion(PeakCalendarEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PeakCalendarEntry>) -> Void) {
        var entries = [PeakCalendarEntry(date: .now)]
        var cursor = Date.now
        for _ in 0..<entryCount {
            // A second past the boundary: renders as the new day even if the
            // fraction lands a hair short of it.
            cursor = PeakCalendar.nextDayBoundary(after: cursor).addingTimeInterval(1)
            entries.append(PeakCalendarEntry(date: cursor))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Face

struct HomePeakCalendarView: View {
    let date: Date

    private let columns = 7
    private let cellSpacing: CGFloat = 2

    var body: some View {
        let pos = PeakCalendar.position(at: date)
        let month = PeakCalendar.months[pos.monthIndex]

        VStack(alignment: .leading, spacing: 4) {
            header(month)
            subheader(month, pos)
            dayGrid(month: month, today: pos.dayOfMonth)
            progress(pos)
        }
    }

    private func header(_ month: PeakMonth) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(month.name.uppercased())
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            Text(month.shorthand)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func subheader(_ month: PeakMonth, _ pos: PeakCalendar.Position) -> some View {
        HStack(spacing: 4) {
            Text("DAY \(pos.dayOfMonth)/\(month.dayCount)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 2)
            Text("\(month.number)/22 · \(month.fractionLabel)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Day cells in reading order, always 7 to a row — the same grid the
    /// iOS page and the macOS board widget draw, so a month has one shape
    /// wherever you meet it. Cell size is whatever fits both axes, and the
    /// block centers in the tile: short months leave blank space rather
    /// than restyling themselves.
    private func dayGrid(month: PeakMonth, today: Int) -> some View {
        let rows = Int((Double(month.dayCount) / Double(columns)).rounded(.up))
        return GeometryReader { geo in
            let side = min(
                (geo.size.width - cellSpacing * CGFloat(columns - 1)) / CGFloat(columns),
                (geo.size.height - cellSpacing * CGFloat(rows - 1)) / CGFloat(rows)
            )
            VStack(spacing: cellSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            let day = row * columns + col + 1
                            if day <= month.dayCount {
                                dayCell(day, today: today, side: side)
                            } else {
                                Color.clear.frame(width: side, height: side)
                            }
                        }
                    }
                }
            }
            // Default .center alignment on both axes — the whole block sits
            // in the middle of whatever room the header and bar leave it.
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayCell(_ day: Int, today: Int, side: CGFloat) -> some View {
        let isToday = day == today
        let hasPassed = day < today
        return RoundedRectangle(cornerRadius: max(1, side * 0.18))
            .fill(
                isToday ? Color.white
                    : Color.white.opacity(hasPassed ? 0.3 : 0.08)
            )
            .frame(width: side, height: side)
            .overlay {
                // Sized off the cell, so the 46-day months (smallest cells,
                // two-digit numbers) stay readable without a separate case.
                Text("\(day)")
                    .font(.system(size: side * 0.46, weight: isToday ? .medium : .regular, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(
                        isToday ? Color.black
                            : Color.white.opacity(hasPassed ? 0.65 : 0.32)
                    )
                    .padding(.horizontal, 1)
            }
            .shadow(color: isToday ? .white.opacity(0.7) : .clear, radius: 3)
    }

    /// Progress through the month — the continuous reading of the same
    /// position the discrete cells quantize.
    private func progress(_ pos: PeakCalendar.Position) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: geo.size.width * pos.fractionThroughMonth)
            }
        }
        .frame(height: 2)
    }
}
