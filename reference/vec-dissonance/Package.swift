// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VecDissonance",
    dependencies: [.package(path: "../swift-core")],
    targets: [.executableTarget(
        name: "VecDissonance",
        dependencies: [.product(name: "ExochronometerCore", package: "swift-core")],
        path: "Sources/VecDissonance")]
)
