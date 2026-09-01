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
        load(from: ApplicationPreferences(userDefaults: defaults))
    }

    @MainActor
    public static func load(from preferences: ApplicationPreferences) -> Self {
        let enabled = preferences.value(for: UMAApplicationPreferenceKeys.assistantEnabled)
        let alwaysOnTop = preferences.value(
            for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
        )
        let densityRawValue = preferences.value(
            for: UMAApplicationPreferenceKeys.assistantDensity
        )
        let density = DesktopAssistantDensity(rawValue: densityRawValue)
            ?? .automatic
        let position = preferences.value(for: UMAApplicationPreferenceKeys.assistantPosition)
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
        save(to: ApplicationPreferences(userDefaults: defaults))
    }

    @MainActor
    public func save(to preferences: ApplicationPreferences) {
        preferences.set(isEnabled, for: UMAApplicationPreferenceKeys.assistantEnabled)
        preferences.set(
            isAlwaysOnTop,
            for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
        )
        preferences.set(density.rawValue, for: UMAApplicationPreferenceKeys.assistantDensity)
        if let position, let data = try? JSONEncoder().encode(position) {
            preferences.set(data, for: UMAApplicationPreferenceKeys.assistantPosition)
        } else {
            preferences.remove(UMAApplicationPreferenceKeys.assistantPosition)
        }
    }
}
