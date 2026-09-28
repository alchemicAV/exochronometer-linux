import SwiftUI

/// One month block for the peak calendar — shared by the iOS page and the
/// macOS board widget. `compact` trades the numbered Gregorian-style day
/// grid for tightly packed day cells that fit a fixed-size widget tile.
public struct PeakMonthCell: View {
    let month: PeakMonth
    /// Non-nil only for the month containing "now"; that day cell lights up.
    let highlightedDay: Int?
    let isCurrent: Bool
    let compact: Bool

    private let columns = 7

    public init(
        month: PeakMonth,
        highlightedDay: Int? = nil,
        isCurrent: Bool = false,
        compact: Bool = false
    ) {
        self.month = month
        self.highlightedDay = highlightedDay
        self.isCurrent = isCurrent
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            header
            subheader
            dayGrid
        }
        .padding(compact ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 10)
                .fill(isCurrent ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 6 : 10)
                .stroke(
                    isCurrent ? Color.white.opacity(0.5) : Color.white.opacity(0.12),
                    lineWidth: isCurrent ? 1 : 0.5
                )
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(month.number)")
                .font(.system(size: compact ? 9 : 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            Text(month.name)
                .font(.system(size: compact ? 12 : 16, weight: .light, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Text(month.shorthand)
                .font(.system(size: compact ? 9 : 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var subheader: some View {
        HStack(spacing: 8) {
            Text(String(format: "%.1f d", month.lengthDays))
                .font(.system(size: compact ? 8 : 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Text("opens \(month.fractionLabel) · \(Int(month.openingDegree.rounded()))°")
                .font(.system(size: compact ? 8 : 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private var dayGrid: some View {
        let grid = Array(
            repeating: GridItem(.flexible(), spacing: compact ? 2 : 3),
            count: columns
        )
        return LazyVGrid(columns: grid, spacing: compact ? 2 : 3) {
            ForEach(1...month.dayCount, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let isToday = (day == highlightedDay)
        return RoundedRectangle(cornerRadius: compact ? 2 : 3)
            .fill(isToday ? Color.white : Color.white.opacity(0.06))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text("\(day)")
                    .font(.system(size: compact ? 7 : 9, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(isToday ? .black : .white.opacity(0.5))
            }
    }
}
