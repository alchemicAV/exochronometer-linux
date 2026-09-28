// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VecFreq",
    dependencies: [.package(path: "../swift-core")],
    targets: [
        .executableTarget(
            name: "VecFreq",
            dependencies: [.product(name: "ExochronometerCore", package: "swift-core")],
            path: "Sources/VecFreq"
        )
    ]
)