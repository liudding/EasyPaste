// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EasyPaste",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "EasyPaste", targets: ["EasyPaste"]),
        // Sparkle framework is added via Xcode SPM; this target does not depend on it directly.
    ],
    dependencies: [
        // GRDB：纯 Swift 的 SQLite 封装，与 SwiftPM 可执行 target 契合度最高。
        // 阶段一用 GRDB 做本地持久化（不动 CloudKit / Harmony）。
        // 与 .xcodeproj 锁同一版本，确保 SwiftPM 与 Xcode 解析一致；当前锁定 7.11.1（已验证支持 Swift 6 / 本机 6.2.4）。
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),

        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "EasyPaste",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: ".",
            exclude: ["Tests", "script", ".codex", ".git", "dist"],
            sources: ["App", "Models", "Stores", "Services", "Support", "Views"],
            resources: [.copy("L10n")]
        ),
        .testTarget(
            name: "EasyPasteTests",
            dependencies: [
                "EasyPaste",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/EasyPasteTests"
        ),
    ]
)