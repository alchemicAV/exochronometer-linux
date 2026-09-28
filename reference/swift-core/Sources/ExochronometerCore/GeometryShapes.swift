import Foundation

// Extracted verbatim from GeometryOverlayView.swift (a SwiftUI file) in the
// original iOS project. The definition itself is pure data - `buildShapeList`
// lives in the portable Geometry.swift - so it only needed separating from the
// `View` that shares its file, not rewriting.
//
// Original location: ExochronometerCore/GeometryOverlayView.swift lines 3-10
extension GeometryMath {
    /// Shared shape list used by both app and widget (3..8 divisions, with star polygons).
    public static let defaultShapes: [Shape] = buildShapeList(
        minDivisions: 3,
        maxDivisions: 8,
        includeStars: true
    )
}
