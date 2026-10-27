import AppKit
import SwiftUI

enum AgentConnectionIndicatorPalette {
    static func connected(isDark: Bool, increasedLightContrast: Bool = false) -> Color {
        isDark ? Color(red: 0.35, green: 1.0, blue: 0.52)
            : (increasedLightContrast ? Color(red: 0.02, green: 0.46, blue: 0.18) : .green)
    }
}

enum DesktopAgentLogoAsset: String, CaseIterable {
    case codex
    case claudeCode = "claude-code"
    case workbuddy
    case antigravity

    static func resolve(providerID: String) -> Self? {
        switch providerID.lowercased().split(separator: ".").first {
        case "codex": .codex
        case "claude": .claudeCode
        case "workbuddy": .workbuddy
        case "antigravity": .antigravity
        default: nil
        }
    }
}

@MainActor
struct DesktopAgentLogo: View {
    let providerID: String
    let tint: Color
    let diameter: CGFloat
    var silhouetteScale: CGFloat = 1

    private static let images: [DesktopAgentLogoAsset: NSImage] = {
        Dictionary(uniqueKeysWithValues: DesktopAgentLogoAsset.allCases.compactMap { asset in
            guard let url = Bundle.main.url(forResource: asset.rawValue,
                                           withExtension: "svg", subdirectory: "AgentLogos"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.isTemplate = true
            return (asset, image)
        })
    }()

    var body: some View {
        Group {
            if let asset = DesktopAgentLogoAsset.resolve(providerID: providerID),
               let image = Self.images[asset] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(tint)
        // Keep the silhouette halo inside the existing identity allocation.
        .padding(diameter * (1 - (5.0 / 6.0) * silhouetteScale) / 2)
        .frame(width: diameter, height: diameter)
        .shadow(color: tint.opacity(0.24), radius: diameter / 20)
        .allowsHitTesting(false)
    }
}
