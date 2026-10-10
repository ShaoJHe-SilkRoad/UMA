import Foundation

/// Read-only local client metadata, never backend attestation or native activation.
public struct ThreadOSCapabilities: Sendable {
    public enum Availability: String, Sendable { case supported, unsupported, unverified }
    public let models: [String: Set<String>]
    public let observedAt: Date?
    public let client: String
    public let now: Date
    public static let unverified = Self(models: [:], observedAt: nil, client: "offline", now: Date())

    public init(models: [String: Set<String>], observedAt: Date?, client: String, now: Date = Date()) {
        self.models = models; self.observedAt = observedAt; self.client = client; self.now = now
    }
    public func availability(model: String, effort: String) -> Availability {
        guard let date = observedAt, now.timeIntervalSince(date) >= -60,
              now.timeIntervalSince(date) <= 86400, let efforts = models[model] else { return .unverified }
        return efforts.contains(effort) ? .supported : .unsupported
    }
    /// Existing CLI catalog cache; no server, credentials, sessions, polling or writes.
    /// Only model/effort and cache freshness/version fields are projected into memory.
    public static func local(now: Date = Date()) -> Self {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url), data.count < 2_000_000 else { return .unverified }
        return decode(data, now: now)
    }
    public static func decode(_ data: Data, now: Date = Date()) -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unverified }
        let dateText = root["fetched_at"] as? String ?? root["observed_at"] as? String ?? ""
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateText) ?? ISO8601DateFormatter().date(from: dateText)
        let rows = root["models"] as? [[String: Any]] ?? root["data"] as? [[String: Any]] ?? []
        var models: [String: Set<String>] = [:]
        var ambiguous: Set<String> = []
        for row in rows {
            guard let model = row["slug"] as? String ?? row["model"] as? String else { continue }
            let efforts = row["supported_reasoning_levels"] as? [[String: Any]] ?? row["supportedReasoningEfforts"] as? [[String: Any]] ?? []
            let values = efforts.compactMap { $0["effort"] as? String ?? $0["reasoningEffort"] as? String }
            // Missing/ambiguous capabilities are unknown, never an unsupported assertion.
            guard !values.isEmpty, values.count == efforts.count, values.allSatisfy({ !$0.isEmpty }),
                  models[model] == nil, !ambiguous.contains(model) else {
                models.removeValue(forKey: model); ambiguous.insert(model); continue
            }
            models[model] = Set(values)
        }
        return Self(models: models, observedAt: date, client: "Codex CLI " + (root["client_version"] as? String ?? "unknown"), now: now)
    }
    public static func catalogAllows(model: String, effort: String) -> Bool {
        guard let catalog = try? ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.ultraCatalogRevision) else { return false }
        return catalog.models[model]?.reasoningEfforts.contains(effort) == true
    }
}
