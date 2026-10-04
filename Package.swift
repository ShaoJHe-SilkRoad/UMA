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
        .executable(name: "PreviewRendererTool", targets: ["PreviewRendererTool"]),
        .executable(name: "HESectoriumControl", targets: ["HESectoriumControl"])
    ],
    targets: [
        .target(
            name: "ClaudeStatusLineCore",
            path: "Sources/ClaudeStatusLineCore"
        ),
        .target(
            name: "HESectoriumCore",
            path: "Sources/HESectoriumCore"
        ),
        .target(
            name: "HESectoriumRuntime",
            dependencies: ["HESectoriumCore"],
            path: "Sources/HESectoriumRuntime",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "HESectoriumCLI",
            dependencies: ["HESectoriumCore", "HESectoriumRuntime"],
            path: "Sources/HESectoriumCLI"
        ),
        .executableTarget(
            name: "HESectoriumControl",
            dependencies: ["HESectoriumCore", "HESectoriumRuntime", "HESectoriumCLI"],
            path: "Sources/HESectoriumControl"
        ),
        .executableTarget(
            name: "HESectoriumControlTestHarness",
            dependencies: ["HESectoriumCore", "HESectoriumRuntime", "HESectoriumCLI"],
            path: "Tests/HESectoriumControlTestHarness"
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
                "HESectoriumRuntime",
            ],
            path: "Sources/CodexUsageUI",
            resources: [.process("Resources")]
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
            path: "Tests/CodexUsageUITests",
            resources: [.process("Fixtures/ThreadOS")]
        ),
        .testTarget(
            name: "ClaudeBrowserBridgeCoreTests",
            dependencies: [
                "ClaudeBrowserBridgeProtocol",
                "ClaudeBrowserNativeHostCore",
                "ClaudeSafariHostIPC",
            ],
            path: "Tests/ClaudeBrowserBridgeCoreTests"
        ),
        .testTarget(
            name: "HESectoriumCoreTests",
            dependencies: ["HESectoriumCore"],
            path: "Tests/HESectoriumCoreTests"
        ),
        .testTarget(
            name: "HESectoriumRuntimeTests",
            dependencies: ["HESectoriumRuntime", "HESectoriumCore"],
            path: "Tests/HESectoriumRuntimeTests"
        )
    ]
)
