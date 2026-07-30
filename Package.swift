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
            name: "CodexUsageUI",
            dependencies: ["ClaudeStatusLineCore"],
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
                "CodexUsageUI",
                "CodexUsageMonitor",
            ],
            path: "Tests/CodexUsageUITests"
        )
    ]
)
