import SwiftUI
import ExochronometerCore

/// Full-year view of the 22 geometric-peak months. All months are visible
/// in a scroll; on appear the view jumps to the current month and lights up
/// today's cell. The highlight tracks live time (updated each minute) while
/// the scroll position stays put.
struct PeakCalendarPage: View {
    @State private var now = Date()
    @State private var didScroll = false
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let pos = PeakCalendar.position(at: now)
        let current = PeakCalendar.months[pos.monthIndex]

        VStack(spacing: 10) {
            header(pos: pos, current: current)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(PeakCalendar.months) { month in
                            PeakMonthCell(
                                month: month,
                                highlightedDay: month.number == current.number ? pos.dayOfMonth : nil,
                                isCurrent: month.number == current.number
                            )
                            .id(month.number)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    guard !didScroll else { return }
                    didScroll = true
                    DispatchQueue.main.async {
                        proxy.scrollTo(current.number, anchor: .center)
                    }
                }
            }
        }
        .padding(.top, 8)
        .onReceive(tick) { now = $0 }
    }

    private func header(pos: PeakCalendar.Position, current: PeakMonth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PEAK CALENDAR")
                .font(.system(size: 10, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
            Text("\(current.name.uppercased()) · DAY \(pos.dayOfMonth) OF \(current.dayCount)  ·  22 months between geometric peaks")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}
