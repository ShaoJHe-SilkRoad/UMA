// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"]),
        .executable(name: "ClaudeBrowserNativeHost", targets: ["ClaudeBrowserNativeHost"]),
        .executable(name: "PreviewRendererTool", targets: ["PreviewRendererTool"])
    ],
    targets: [
        .target(
            name: "ClaudeBrowserBridgeProtocol",
            path: "Sources/ClaudeBrowserBridgeProtocol"
        ),
        .target(
            name: "ClaudeBrowserNativeHostCore",
            dependencies: ["ClaudeBrowserBridgeProtocol"],
            path: "Sources/ClaudeBrowserNativeHostCore"
        ),
        .executableTarget(
            name: "ClaudeBrowserNativeHost",
            dependencies: [
                "ClaudeBrowserNativeHostCore",
                "ClaudeBrowserBridgeProtocol",
            ],
            path: "Sources/ClaudeBrowserNativeHost"
        ),
        // Retained only so checksum-backed historical status-line tests and
        // records remain reviewable. No relay executable target remains.
        .target(
            name: "ClaudeStatusLineCore",
            path: "Sources/ClaudeStatusLineCore"
        ),
        .target(
            name: "CodexUsageUI",
            dependencies: [
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
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
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
                "ClaudeStatusLineCore",
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
            ],
            path: "Tests/ClaudeBrowserBridgeCoreTests"
        )
    ]
)
