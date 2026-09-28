// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VecNodeLabels",
    dependencies: [.package(path: "../swift-core")],
    targets: [
        .executableTarget(
            name: "VecNodeLabels",
            dependencies: [.product(name: "ExochronometerCore", package: "swift-core")],
            path: "Sources/VecNodeLabels"
        )
    ]
)
