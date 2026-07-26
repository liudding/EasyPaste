// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EasyPaste",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "EasyPaste", targets: ["EasyPaste"]),
        // Sparkle framework is added via Xcode SPM; this target does not depend on it directly.
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),

        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.23.0"),
    ],
    targets: [
        .executableTarget(
            name: "EasyPaste",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: ".",
            exclude: ["Tests", "script", ".build", "dist", "deliverables", "docs"],
            sources: ["App", "Models", "Stores", "Services", "Views"],
            resources: [.process("L10n")]
        ),
        .testTarget(
            name: "EasyPasteTests",
            dependencies: [
                "EasyPaste",
            ],
            path: "Tests/EasyPasteTests"
        ),
    ]
)