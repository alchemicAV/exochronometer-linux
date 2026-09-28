import SwiftUI
import WidgetKit

@main
struct ExochronometerWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeChronometerWidget()
        HomePeakCalendarWidget()
    }
}
