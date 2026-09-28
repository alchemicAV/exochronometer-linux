// swift-tools-version: 6.0
import PackageDescription

// HarmonicColor lives in the iOS app's ExochronometerCore (a SwiftUI-coupled
// file that was never added to the CLI oracle package), so this package
// carries its own verbatim copies of the functions instead of depending on
// swift-core.
let package = Package(
    name: "VecColor",
    targets: [
        .executableTarget(
            name: "VecColor",
            path: "Sources/VecColor"
        )
    ]
)