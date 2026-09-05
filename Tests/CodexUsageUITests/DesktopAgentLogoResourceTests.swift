import AppKit
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Desktop Agent official local logo resources")
@MainActor
struct DesktopAgentLogoResourceTests {
    @Test func resourcesLoadWithTransparentVectorGeometry() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for asset in DesktopAgentLogoAsset.allCases {
            let url = root.appendingPathComponent("Assets/AgentLogos/\(asset.rawValue).svg")
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(source.contains("<path"))
            #expect(!source.contains("<image"))
            #expect(!source.contains("<text"))
            #expect(!source.contains("href="))
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width > 0 && image.size.height > 0)
            #expect(!image.representations.isEmpty)
        }
        #expect(DesktopAgentLogoAsset.resolve(providerID: "workBuddy") == .workbuddy)
        #expect(DesktopAgentLogoAsset.resolve(providerID: "claude.browserSync") == .claudeCode)
    }
}
