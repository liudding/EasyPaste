// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyPaste",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "EasyPaste", targets: ["EasyPaste"]),
        // Sparkle framework is added via Xcode SPM; this target does not depend on it directly.
    ],
    targets: [
        .executableTarget(name: "EasyPaste", path: ".", exclude: ["Tests", "script", ".codex", ".git", "dist"], sources: ["App", "Models", "Stores", "Services", "Support", "Views"]),
        .testTarget(name: "EasyPasteTests", dependencies: ["EasyPaste"], path: "Tests/EasyPasteTests")
    ]
)
