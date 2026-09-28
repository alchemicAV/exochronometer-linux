// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VecAnalysis",
    dependencies: [.package(path: "../swift-core")],
    targets: [.executableTarget(
        name: "VecAnalysis",
        dependencies: [.product(name: "ExochronometerCore", package: "swift-core")],
        path: "Sources/VecAnalysis")]
)