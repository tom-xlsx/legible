// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Legible",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Legible",
            path: "Sources/Legible"
        ),
        .testTarget(
            name: "LegibleTests",
            dependencies: ["Legible"],
            path: "Tests/LegibleTests"
        ),
    ]
)
