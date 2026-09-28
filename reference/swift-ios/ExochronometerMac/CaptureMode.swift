import SwiftUI

/// Environment flag set by `StaticCanvas` during a capture render. Widgets
/// that wrap their content in `ScrollView` read this and unwrap to a
/// straight container instead — `ImageRenderer` doesn't drive ScrollViews
/// (no scroll position is established) so the content otherwise captures
/// as an empty viewport.
private struct ExoCaptureModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var exoCaptureMode: Bool {
        get { self[ExoCaptureModeKey.self] }
        set { self[ExoCaptureModeKey.self] = newValue }
    }
}

/// Container that becomes a `ScrollView` in live mode and a passthrough
/// VStack in capture mode. Drop-in for widget bodies that previously
/// used `ScrollView { VStack { … } }`.
struct CaptureAwareScrollView<Content: View>: View {
    @Environment(\.exoCaptureMode) private var isCapturing
    let axes: Axis.Set
    let showsIndicators: Bool
    @ViewBuilder var content: () -> Content

    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content
    }

    var body: some View {
        if isCapturing {
            // Render content at its natural size. StaticCanvas applies
            // `.frame(...alignment: .topLeading).clipped()` outside this,
            // so overflow is bounded and the visible portion is top-down.
            content()
        } else {
            ScrollView(axes, showsIndicators: showsIndicators) {
                content()
            }
        }
    }
}
