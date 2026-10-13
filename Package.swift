// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Legible",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Legible",
            dependencies: ["LegibleRender"],
            path: "Sources/Legible"
        ),
        // Markdown → HTML without a web view (JavaScriptCore), shared by the app and the extension.
        .target(
            name: "LegibleRender",
            path: "Sources/LegibleRender",
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        // Quick Look preview extension (bundled as Contents/PlugIns/LegibleQuickLook.appex).
        .executableTarget(
            name: "LegibleQuickLook",
            dependencies: ["LegibleRender"],
            path: "Sources/LegibleQuickLook",
            linkerSettings: [.linkedFramework("QuickLookUI")]
        ),
        .testTarget(
            name: "LegibleTests",
            dependencies: ["Legible", "LegibleRender"],
            path: "Tests/LegibleTests"
        ),
    ]
)
