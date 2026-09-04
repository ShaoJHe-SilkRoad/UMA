import Foundation

/// A typed key whose spelling remains the on-disk compatibility contract.
/// Existing UMA keys are intentionally not namespaced or rewritten here.
public struct ApplicationPreferenceKey<Value> {
    public let name: String
    public let defaultValue: Value
    fileprivate let decode: (Any) -> Value?
    fileprivate let encode: (Value) -> Any?
    fileprivate let equals: (Value, Value) -> Bool

    fileprivate init(
        name: String,
        defaultValue: Value,
        decode: @escaping (Any) -> Value?,
        encode: @escaping (Value) -> Any?,
        equals: @escaping (Value, Value) -> Bool
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.decode = decode
        self.encode = encode
        self.equals = equals
    }
}

public extension ApplicationPreferenceKey where Value == Bool {
    init(_ name: String, default defaultValue: Bool) {
        self.init(
            name: name,
            defaultValue: defaultValue,
            decode: { value in
                if let value = value as? Bool { return value }
                return (value as? NSNumber)?.boolValue
            },
            encode: { $0 },
            equals: ==
        )
    }
}

public extension ApplicationPreferenceKey where Value == String {
    init(_ name: String, default defaultValue: String) {
        self.init(
            name: name,
            defaultValue: defaultValue,
            decode: { $0 as? String },
            encode: { $0 },
            equals: ==
        )
    }
}

public extension ApplicationPreferenceKey where Value == String? {
    init(optional name: String) {
        self.init(
            name: name,
            defaultValue: nil,
            decode: { $0 as? String },
            encode: { $0 },
            equals: ==
        )
    }
}

public extension ApplicationPreferenceKey where Value == Data? {
    init(optionalData name: String) {
        self.init(
            name: name,
            defaultValue: nil,
            decode: { $0 as? Data },
            encode: { $0 },
            equals: ==
        )
    }
}

@MainActor
protocol ApplicationPreferenceBacking: AnyObject {
    var persistenceIdentifier: String? { get }
    var isEphemeral: Bool { get }
    func object(forKey key: String) -> Any?
    func set(_ value: Any, forKey key: String)
    func removeObject(forKey key: String)
}

@MainActor
private final class UserDefaultsPreferenceBacking: ApplicationPreferenceBacking {
    let defaults: UserDefaults
    let persistenceIdentifier: String?
    let isEphemeral = false

    init(defaults: UserDefaults, persistenceIdentifier: String?) {
        self.defaults = defaults
        self.persistenceIdentifier = persistenceIdentifier
    }

    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func set(_ value: Any, forKey key: String) { defaults.set(value, forKey: key) }
    func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}

@MainActor
private final class InMemoryPreferenceBacking: ApplicationPreferenceBacking {
    let persistenceIdentifier: String? = nil
    let isEphemeral = true
    private var values: [String: Any]

    init(seed: [String: Any]) {
        values = seed
    }

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

/// The one application-level preference boundary. Production explicitly wraps
/// `.standard`; tests explicitly choose an in-memory backing or a named suite.
/// There is no optional initializer and therefore no nil-to-standard fallback.
@MainActor
public final class ApplicationPreferences {
    public struct Change: Equatable, Sendable {
        public let key: String
        public let revision: UInt64
    }

    @MainActor
    public final class Observation {
        private let cancelAction: @MainActor () -> Void
        private var isCancelled = false

        fileprivate init(cancelAction: @escaping @MainActor () -> Void) {
            self.cancelAction = cancelAction
        }

        public func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            cancelAction()
        }
    }

    public static let production = ApplicationPreferences(
        backing: UserDefaultsPreferenceBacking(
            defaults: .standard,
            persistenceIdentifier: Bundle.main.bundleIdentifier
        )
    )

    private let backing: any ApplicationPreferenceBacking
    private var revision: UInt64 = 0
    private var observers: [UUID: (Change) -> Void] = [:]

    private init(backing: any ApplicationPreferenceBacking) {
        self.backing = backing
    }

    public convenience init(userDefaults: UserDefaults) {
        self.init(
            backing: UserDefaultsPreferenceBacking(
                defaults: userDefaults,
                persistenceIdentifier: nil
            )
        )
    }

    public static func isolatedSuite(named suiteName: String) throws -> ApplicationPreferences {
        guard !suiteName.isEmpty, let defaults = UserDefaults(suiteName: suiteName) else {
            throw ApplicationPreferenceError.invalidSuiteName
        }
        return ApplicationPreferences(
            backing: UserDefaultsPreferenceBacking(
                defaults: defaults,
                persistenceIdentifier: suiteName
            )
        )
    }

    public static func inMemory(seed: [String: Any] = [:]) -> ApplicationPreferences {
        ApplicationPreferences(backing: InMemoryPreferenceBacking(seed: seed))
    }

    public var persistenceIdentifier: String? { backing.persistenceIdentifier }
    public var isEphemeral: Bool { backing.isEphemeral }

    public func value<Value>(for key: ApplicationPreferenceKey<Value>) -> Value {
        guard let stored = backing.object(forKey: key.name),
              let decoded = key.decode(stored)
        else {
            return key.defaultValue
        }
        return decoded
    }

    public func contains<Value>(_ key: ApplicationPreferenceKey<Value>) -> Bool {
        backing.object(forKey: key.name) != nil
    }

    public func set<Value>(_ value: Value, for key: ApplicationPreferenceKey<Value>) {
        let oldValue = self.value(for: key)
        guard let encoded = key.encode(value) else {
            remove(key)
            return
        }
        backing.set(encoded, forKey: key.name)
        if !key.equals(oldValue, value) { publish(key.name) }
    }

    public func remove<Value>(_ key: ApplicationPreferenceKey<Value>) {
        guard contains(key) else { return }
        backing.removeObject(forKey: key.name)
        publish(key.name)
    }

    @discardableResult
    public func observe(_ callback: @escaping (Change) -> Void) -> Observation {
        let id = UUID()
        observers[id] = callback
        return Observation { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
    }

    private func publish(_ key: String) {
        revision &+= 1
        let change = Change(key: key, revision: revision)
        for callback in observers.values { callback(change) }
    }

}

public enum ApplicationPreferenceError: Error, Equatable {
    case invalidSuiteName
}

/// Global appearance is an application preference rather than a view-local
/// override so Main, Settings, the Quick Panel, and Desktop Wizard always use
/// one visual truth.
public enum UMAApplicationAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }
}

/// Closed catalog for preferences moved behind the typed boundary in Infra G1.
/// The raw names are the exact 0.13 keys.
@MainActor
public enum UMAApplicationPreferenceKeys {
    public static let language = ApplicationPreferenceKey<String?>(
        optional: AppLanguage.storageKey
    )
    public static let assistantEnabled = ApplicationPreferenceKey<Bool>(
        DesktopAssistantPreferences.Keys.isEnabled,
        default: true
    )
    public static let assistantAlwaysOnTop = ApplicationPreferenceKey<Bool>(
        DesktopAssistantPreferences.Keys.isAlwaysOnTop,
        default: true
    )
    public static let assistantDensity = ApplicationPreferenceKey<String>(
        DesktopAssistantPreferences.Keys.density,
        default: DesktopAssistantDensity.automatic.rawValue
    )
    public static let assistantPosition = ApplicationPreferenceKey<Data?>(
        optionalData: DesktopAssistantPreferences.Keys.position
    )
    public static let appearance = ApplicationPreferenceKey<String>(
        "app.appearance",
        default: UMAApplicationAppearance.system.rawValue
    )
    public static let menuBarShowsRemaining = ApplicationPreferenceKey<Bool>(
        "app.menuBarShowsRemaining",
        default: true
    )
    public static let quickPanelShowsReset = ApplicationPreferenceKey<Bool>(
        "app.quickPanelShowsReset",
        default: true
    )
    static let agentPreferences = ApplicationPreferenceKey<Data?>(
        optionalData: AgentPreferenceStore.key
    )
    static let legacyShowUsageSummary = ApplicationPreferenceKey<Bool?>(
        optionalBool: AgentPreferenceStore.LegacyKeys.showUsageSummary
    )
    static let legacyShowRecentTasks = ApplicationPreferenceKey<Bool?>(
        optionalBool: AgentPreferenceStore.LegacyKeys.showRecentTasks
    )
    static let legacyShowAPICost = ApplicationPreferenceKey<Bool?>(
        optionalBool: AgentPreferenceStore.LegacyKeys.showAPICost
    )
    static let antigravityAutoRefresh = ApplicationPreferenceKey<Bool>(
        "antigravity.autoRefreshEnabled",
        default: true
    )
}

extension ApplicationPreferenceKey where Value == Bool? {
    init(optionalBool name: String) {
        self.init(
            name: name,
            defaultValue: nil,
            decode: { value in
                if let value = value as? Bool { return value }
                return (value as? NSNumber)?.boolValue
            },
            encode: { $0 },
            equals: ==
        )
    }
}
