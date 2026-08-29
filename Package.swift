// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"]),
        .executable(name: "ClaudeStatusLineRelay", targets: ["ClaudeStatusLineRelay"]),
        .executable(name: "ClaudeBrowserNativeHost", targets: ["ClaudeBrowserNativeHost"]),
        .executable(name: "UMASafariBridgeHost", targets: ["UMASafariBridgeHost"]),
        .executable(name: "PreviewRendererTool", targets: ["PreviewRendererTool"])
    ],
    targets: [
        .target(
            name: "ClaudeStatusLineCore",
            path: "Sources/ClaudeStatusLineCore"
        ),
        .executableTarget(
            name: "ClaudeStatusLineRelay",
            dependencies: ["ClaudeStatusLineCore"],
            path: "Sources/ClaudeStatusLineRelay"
        ),
        .target(
            name: "ClaudeBrowserBridgeProtocol",
            path: "Sources/ClaudeBrowserBridgeProtocol"
        ),
        .target(
            name: "ClaudeBrowserNativeHostCore",
            dependencies: ["ClaudeBrowserBridgeProtocol"],
            path: "Sources/ClaudeBrowserNativeHostCore"
        ),
        .target(
            name: "ClaudeSafariHostIPC",
            dependencies: ["ClaudeBrowserBridgeProtocol"],
            path: "Sources/ClaudeSafariHostIPC"
        ),
        .executableTarget(
            name: "UMASafariBridgeHost",
            dependencies: [
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
                "ClaudeSafariHostIPC",
            ],
            path: "Sources/UMASafariBridgeHost"
        ),
        .executableTarget(
            name: "ClaudeBrowserNativeHost",
            dependencies: [
                "ClaudeBrowserNativeHostCore",
                "ClaudeBrowserBridgeProtocol",
            ],
            path: "Sources/ClaudeBrowserNativeHost"
        ),
        .target(
            name: "CodexUsageUI",
            dependencies: [
                "ClaudeStatusLineCore",
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
                "ClaudeSafariHostIPC",
            ],
            path: "Sources/CodexUsageUI"
        ),
        .executableTarget(
            name: "CodexUsageMonitor",
            dependencies: ["CodexUsageUI"],
            path: "Sources/CodexUsageMonitor"
        ),
        .executableTarget(
            name: "PreviewRendererTool",
            dependencies: ["CodexUsageUI"],
            path: "Sources/PreviewRendererTool"
        ),
        .testTarget(
            name: "CodexUsageUITests",
            dependencies: [
                "ClaudeStatusLineCore",
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
                "CodexUsageUI",
                "CodexUsageMonitor",
            ],
            path: "Tests/CodexUsageUITests"
        ),
        .testTarget(
            name: "ClaudeBrowserBridgeCoreTests",
            dependencies: [
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
                "ClaudeSafariHostIPC",
            ],
            path: "Tests/ClaudeBrowserBridgeCoreTests"
        )
    ]
)
