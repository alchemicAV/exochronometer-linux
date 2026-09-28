// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VecChords",
    dependencies: [.package(path: "../swift-core")],
    targets: [
        .executableTarget(
            name: "VecChords",
            dependencies: [.product(name: "ExochronometerCore", package: "swift-core")],
            path: "Sources/VecChords"
        )
    ]
)