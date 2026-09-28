import SwiftUI
import SwiftData
import ExochronometerCore

struct ContentView: View {
    @State private var currentPage: AppPage = .circles
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                AppHeader(currentPage: $currentPage)

                Group {
                    switch currentPage {
                    case .circles:
                        CirclesPage()
                    case .timeline:
                        TimelinePage()
                    case .geometryHarmonics:
                        GeometryHarmonicsPage()
                    case .harmonicAnalysis:
                        HarmonicAnalysisPage()
                    case .peakCalendar:
                        PeakCalendarPage()
                    case .misc:
                        MiscPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // v2 re-anchoring (solstice year, Metonic epoch) invalidated
            // degrees stored under earlier schemas; purge rather than
            // migrate (pre-release policy).
            JournalNote.purgeStaleSchema(in: modelContext)
        }
    }
}
