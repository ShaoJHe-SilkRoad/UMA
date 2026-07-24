import Foundation

public enum DesktopAssistantDensity: String, CaseIterable, Codable, Sendable {
    case automatic
    case regular
    case minimalist

    public func resolvedDensity(visibleProviderCount: Int) -> DesktopAssistantResolvedDensity {
        if visibleProviderCount >= 5 {
            return .minimalist
        }
        switch self {
        case .automatic:
            return .regular
        case .regular:
            return .regular
        case .minimalist:
            return .minimalist
        }
    }
}

public enum DesktopAssistantResolvedDensity: String, Codable, Sendable {
    case regular
    case minimalist
}

/// A display-relative position keeps the Assistant recoverable when a display
/// disappears or changes resolution. Values are clamped again by the host
/// controller before being applied to an AppKit window.
public struct DesktopAssistantPosition: Codable, Equatable, Sendable {
    public let displayIdentifier: UInt32?
    public let horizontalFraction: Double
    public let verticalFraction: Double

    public init(
        displayIdentifier: UInt32?,
        horizontalFraction: Double,
        verticalFraction: Double
    ) {
        self.displayIdentifier = displayIdentifier
        self.horizontalFraction = Self.clamp(horizontalFraction)
        self.verticalFraction = Self.clamp(verticalFraction)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }
}

public struct DesktopAssistantPreferences: Equatable, Sendable {
    public enum Keys {
        public static let isEnabled = "desktopAssistant.isEnabled"
        public static let isAlwaysOnTop = "desktopAssistant.isAlwaysOnTop"
        public static let density = "desktopAssistant.density"
        public static let position = "desktopAssistant.position"
    }

    public var isEnabled: Bool
    public var isAlwaysOnTop: Bool
    public var density: DesktopAssistantDensity
    public var position: DesktopAssistantPosition?

    public init(
        isEnabled: Bool = true,
        isAlwaysOnTop: Bool = true,
        density: DesktopAssistantDensity = .automatic,
        position: DesktopAssistantPosition? = nil
    ) {
        self.isEnabled = isEnabled
        self.isAlwaysOnTop = isAlwaysOnTop
        self.density = density
        self.position = position
    }

    @MainActor
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        let enabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        let alwaysOnTop = defaults.object(forKey: Keys.isAlwaysOnTop) as? Bool ?? true
        let density = defaults.string(forKey: Keys.density)
            .flatMap(DesktopAssistantDensity.init(rawValue:)) ?? .automatic
        let position = defaults.data(forKey: Keys.position)
            .flatMap { try? JSONDecoder().decode(DesktopAssistantPosition.self, from: $0) }
        return Self(
            isEnabled: enabled,
            isAlwaysOnTop: alwaysOnTop,
            density: density,
            position: position
        )
    }

    @MainActor
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(isAlwaysOnTop, forKey: Keys.isAlwaysOnTop)
        defaults.set(density.rawValue, forKey: Keys.density)
        if let position, let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: Keys.position)
        } else {
            defaults.removeObject(forKey: Keys.position)
        }
    }
}
