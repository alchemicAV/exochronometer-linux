// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VecCalendar",
    dependencies: [
        .package(path: "../swift-core")
    ],
    targets: [
        .executableTarget(
            name: "VecCalendar",
            dependencies: [.product(name: "ExochronometerCore", package: "swift-core")],
            path: "Sources/VecCalendar"
        )
    ]
)
