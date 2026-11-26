import AppKit
import SwiftUI

enum AgentConnectionIndicatorPalette {
    static func connected(isDark: Bool, increasedLightContrast: Bool = false) -> Color {
        switch AUVLook.current {
        case .standard:
            isDark ? Color(red: 0.35, green: 1.0, blue: 0.52)
                : (increasedLightContrast ? Color(red: 0.02, green: 0.46, blue: 0.18) : .green)
        // Moss, not a signal green; the problem colours stay as they are.
        case .wabiSabi: AUVLookPalette.moss(isDark: isDark)
        case .brutalist: AUVLookPalette.ink(.brutalist, isDark: isDark)
        }
    }
}

enum DesktopAgentLogoAsset: String, CaseIterable {
    case codex
    case claudeCode = "claude-code"
    case workbuddy
    case antigravity
    case gemini

    static func resolve(providerID: String) -> Self? {
        switch providerID.lowercased().split(separator: ".").first {
        case "codex": .codex
        case "claude": .claudeCode
        case "workbuddy": .workbuddy
        case "antigravity": .antigravity
        case "gemini": .gemini
        default: nil
        }
    }
}

/// The agent logos as menu bar template images.
@MainActor
public enum AgentLogoTemplateImage {
    private static var cache: [String: NSImage] = [:]

    /// A template image of the agent's logo at `pointSize`, or nil for an
    /// unknown agent.
    public static func image(providerID: String, pointSize: CGFloat = 16) -> NSImage? {
        guard let asset = DesktopAgentLogoAsset.resolve(providerID: providerID) else { return nil }
        let key = "\(asset.rawValue)@\(pointSize)"
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource: asset.rawValue, withExtension: "svg",
                                        subdirectory: "AgentLogos"),
              let source = NSImage(contentsOf: url) else { return nil }
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
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
