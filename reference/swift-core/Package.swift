// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExochronometerCore",
    products: [
        .library(name: "ExochronometerCore", targets: ["ExochronometerCore"])
    ],
    targets: [
        .target(
            name: "ExochronometerCore",
            path: "Sources/ExochronometerCore"
        ),
        .executableTarget(
            name: "VectorGen",
            dependencies: ["ExochronometerCore"],
            path: "Sources/VectorGen"
        )
    ]
)
