import CoreFoundation
import Darwin
import Foundation

/// Fail-closed Grok Bot presence classification.
///
/// UMA may report whether the official app is installed and whether a local
/// session/meter file is readable. It does not admit Grok to the main usage
/// panel. See `docs/integrations/grok-bot-usage-status-contract.md`.
enum GrokBotPresenceClassification: String, Codable, CaseIterable, Equatable, Sendable {
    case notInstalled
    case installedSignedOut
    case installedSignedInMeterMissing
    case installedStatusRejected
    case installedSignedInMeterRejected
    case installedSignedInMeterNotAdmitted

    func settingsSummary(language: AppLanguage) -> String {
        switch (language, self) {
        case (.english, .notInstalled):
            "Not installed"
        case (.english, .installedSignedOut):
            "Installed, signed out"
        case (.english, .installedSignedInMeterMissing):
            "Signed in, local usage meter missing"
        case (.english, .installedStatusRejected):
            "Installed, local status rejected"
        case (.english, .installedSignedInMeterRejected):
            "Signed in, local usage meter rejected"
        case (.english, .installedSignedInMeterNotAdmitted):
            "Signed in, local usage meter not on the usage panel"
        case (.simplifiedChinese, .notInstalled):
            "未安装"
        case (.simplifiedChinese, .installedSignedOut):
            "已安装，未登录"
        case (.simplifiedChinese, .installedSignedInMeterMissing):
            "已登录，本地用量计量缺失"
        case (.simplifiedChinese, .installedStatusRejected):
            "已安装，本地状态已拒绝"
        case (.simplifiedChinese, .installedSignedInMeterRejected):
            "已登录，本地用量计量已拒绝"
        case (.simplifiedChinese, .installedSignedInMeterNotAdmitted):
            "已登录，本地用量计量未进入用量面板"
        }
    }
}

protocol GrokBotPresenceProbing: Sendable {
    func diagnose(now: Date) -> GrokBotPresenceClassification
}

struct GrokBotPresenceLocations: Equatable, Sendable {
    var applicationURL: URL
    var desktopStatusURL: URL
    var applicationSupportUsageStatusURL: URL
    var homeUsageStatusURL: URL

    static var production: GrokBotPresenceLocations {
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let support = home.appendingPathComponent(
            "Library/Application Support/Grok Bot",
            isDirectory: true
        )
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .resolvingSymlinksInPath()
        return GrokBotPresenceLocations(
            applicationURL: applications.appendingPathComponent("Grok Bot.app", isDirectory: true),
            desktopStatusURL: support.appendingPathComponent("desktop-status.json"),
            applicationSupportUsageStatusURL: support.appendingPathComponent("usage-status.json"),
            homeUsageStatusURL: home.appendingPathComponent(".grokbot/usage-status.json")
        )
    }
}

enum GrokBotUsageStatusContract {
    static let schemaVersion = 1
    static let maximumSampleAge: TimeInterval = 20 * 60
    static let maximumFutureSkew: TimeInterval = 30
    static let percentSumTolerance = 0.6
    static let maximumDesktopStatusBytes = 16 * 1_024
    static let maximumUsageStatusBytes = 64 * 1_024
}

/// In-memory projection of a contract-valid meter file.
///
/// This is a reader stub only. It is not an `AgentUsageSnapshot`, it is not
/// persisted, and `GrokBotPresenceProbe` discards it instead of admitting it.
struct GrokBotUsageMeter: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let id: String
        let label: String
        let usedPercent: Double?
        let remainingPercent: Double?
        let resetsAt: Date?
        let unlimited: Bool
    }

    let capturedAt: Date
    let planLabel: String?
    let usagePercentUsed: Double?
    let remainingPercent: Double?
    let nextResetAt: Date?
    let isUnlimited: Bool
    let isTeamSeat: Bool
    let onDemandEnabled: Bool
    let windows: [Window]
    let source: String?
}

enum GrokBotUsageStatusRead: Equatable, Sendable {
    case missing
    case rejected
    case validated(GrokBotUsageMeter)
}

struct GrokBotUsageStatusReader: Sendable {
    func read(from url: URL, now: Date) -> GrokBotUsageStatusRead {
        switch GrokBotBoundedFile.read(
            at: url,
            maximumBytes: GrokBotUsageStatusContract.maximumUsageStatusBytes,
            permissions: .usageMeter
        ) {
        case .missing:
            return .missing
        case .rejected:
            return .rejected
        case let .data(data):
            guard let meter = Self.project(data, now: now) else { return .rejected }
            return .validated(meter)
        }
    }

    private static let allowedKeys: Set<String> = [
        "schemaVersion",
        "capturedAt",
        "signedIn",
        "planLabel",
        "usagePercentUsed",
        "remainingPercent",
        "nextResetAt",
        "isUnlimited",
        "isTeamSeat",
        "onDemandEnabled",
        "windows",
        "source",
    ]

    private static let windowKeys: Set<String> = [
        "id",
        "label",
        "usedPercent",
        "remainingPercent",
        "resetsAt",
        "unlimited",
    ]

    private static func project(_ data: Data, now: Date) -> GrokBotUsageMeter? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: allowedKeys),
              jsonExactInteger(object["schemaVersion"]) == GrokBotUsageStatusContract.schemaVersion,
              jsonBool(object["signedIn"]) == true,
              let capturedAt = utcDate(object["capturedAt"])
        else { return nil }

        let age = now.timeIntervalSince(capturedAt)
        let planLabel = optionalDisplayLabel(object["planLabel"])
        let nextResetAt = optionalDate(object["nextResetAt"])
        let source = optionalIdentifier(object["source"])
        guard capturedAt.timeIntervalSince1970.isFinite,
              age >= -GrokBotUsageStatusContract.maximumFutureSkew,
              age <= GrokBotUsageStatusContract.maximumSampleAge,
              let percents = pairedPercents(
                  used: optionalNumber(object["usagePercentUsed"]),
                  remaining: optionalNumber(object["remainingPercent"])
              ),
              let isUnlimited = optionalBool(object["isUnlimited"], default: false),
              let isTeamSeat = optionalBool(object["isTeamSeat"], default: false),
              let onDemandEnabled = optionalBool(object["onDemandEnabled"], default: false),
              planLabel.isValid,
              nextResetAt.isValid,
              source.isValid,
              let windows = windows(object["windows"])
        else { return nil }

        return GrokBotUsageMeter(
            capturedAt: capturedAt,
            planLabel: planLabel.value,
            usagePercentUsed: percents.used,
            remainingPercent: percents.remaining,
            nextResetAt: nextResetAt.value,
            isUnlimited: isUnlimited,
            isTeamSeat: isTeamSeat,
            onDemandEnabled: onDemandEnabled,
            windows: windows,
            source: source.value
        )
    }

    private static func windows(_ value: Any?) -> [GrokBotUsageMeter.Window]? {
        guard let value else { return [] }
        guard let array = value as? [Any], array.count <= 8 else { return nil }
        var windows: [GrokBotUsageMeter.Window] = []
        var seen: Set<String> = []
        for item in array {
            guard let object = item as? [String: Any],
                  Set(object.keys).isSubset(of: windowKeys),
                  let id = jsonString(object["id"]).flatMap(boundedIdentifier),
                  seen.insert(id).inserted,
                  let label = jsonString(object["label"]).flatMap(displayLabel),
                  let percents = pairedPercents(
                      used: optionalNumber(object["usedPercent"]),
                      remaining: optionalNumber(object["remainingPercent"])
                  ),
                  let unlimited = optionalBool(object["unlimited"], default: false)
            else { return nil }
            let resetsAt = optionalDate(object["resetsAt"])
            guard resetsAt.isValid else { return nil }
            windows.append(
                GrokBotUsageMeter.Window(
                    id: id,
                    label: label,
                    usedPercent: percents.used,
                    remainingPercent: percents.remaining,
                    resetsAt: resetsAt.value,
                    unlimited: unlimited
                )
            )
        }
        return windows
    }
}

/// Detects Grok Bot.app and reads only allowlisted local status files.
///
/// The probe never launches the app, enumerates host directories, or retains
/// process ids, versions, plan labels, or percentages. A future valid
/// `usage-status.json` stays off the main usage panel.
struct GrokBotPresenceProbe: GrokBotPresenceProbing, Sendable {
    private let locations: GrokBotPresenceLocations
    private let usageReader: GrokBotUsageStatusReader

    init(
        locations: GrokBotPresenceLocations = .production,
        usageReader: GrokBotUsageStatusReader = GrokBotUsageStatusReader()
    ) {
        self.locations = locations
        self.usageReader = usageReader
    }

    func diagnose(now: Date) -> GrokBotPresenceClassification {
        guard applicationIsInstalled(at: locations.applicationURL) else {
            return .notInstalled
        }
        switch desktopStatus() {
        case .missing, .signedOut:
            return .installedSignedOut
        case .rejected:
            return .installedStatusRejected
        case .signedIn:
            break
        }
        switch readUsage(now: now) {
        case .missing:
            return .installedSignedInMeterMissing
        case .rejected:
            return .installedSignedInMeterRejected
        case .validated:
            return .installedSignedInMeterNotAdmitted
        }
    }

    private enum DesktopStatus {
        case missing
        case rejected
        case signedOut
        case signedIn
    }

    private func desktopStatus() -> DesktopStatus {
        switch GrokBotBoundedFile.read(
            at: locations.desktopStatusURL,
            maximumBytes: GrokBotUsageStatusContract.maximumDesktopStatusBytes,
            permissions: .desktopStatus
        ) {
        case .missing:
            return .missing
        case .rejected:
            return .rejected
        case let .data(data):
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let signedIn = jsonBool(object["signedIn"]),
                  optionalProcessID(object["pid"]),
                  optionalAppVersion(object["appVersion"])
            else { return .rejected }
            return signedIn ? .signedIn : .signedOut
        }
    }

    /// Application Support wins. A present but invalid preferred file does not
    /// fall through to `~/.grokbot`, and neither directory is enumerated.
    private func readUsage(now: Date) -> GrokBotUsageStatusRead {
        let preferred = usageReader.read(
            from: locations.applicationSupportUsageStatusURL,
            now: now
        )
        guard case .missing = preferred,
              locations.applicationSupportUsageStatusURL.standardizedFileURL
                  != locations.homeUsageStatusURL.standardizedFileURL
        else { return preferred }
        return usageReader.read(from: locations.homeUsageStatusURL, now: now)
    }

    private func applicationIsInstalled(at url: URL) -> Bool {
        var path = url.standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        if (info.st_mode & S_IFMT) == S_IFLNK {
            guard stat(path, &info) == 0 else { return false }
        }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }
}

private enum GrokBotBoundedFile {
    enum Outcome {
        case missing
        case rejected
        case data(Data)
    }

    enum Permissions {
        case desktopStatus
        case usageMeter
    }

    static func read(
        at url: URL,
        maximumBytes: Int,
        permissions: Permissions
    ) -> Outcome {
        guard maximumBytes >= 0 else { return .rejected }
        let standardized = url.standardizedFileURL
        guard standardized.resolvingSymlinksInPath().path == standardized.path else {
            return .rejected
        }

        let descriptor = open(standardized.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if descriptor < 0 {
            return errno == ENOENT ? .missing : .rejected
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              accepts(info, maximumBytes: maximumBytes, permissions: permissions)
        else { return .rejected }

        let expectedSize = Int(info.st_size)
        var data = Data(count: expectedSize)
        let readSucceeded = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < expectedSize {
                let count = Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    expectedSize - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            var trailingByte: UInt8 = 0
            let trailingCount = Darwin.read(descriptor, &trailingByte, 1)
            return trailingCount == 0
        }
        guard readSucceeded else { return .rejected }

        var finalInfo = stat()
        guard fstat(descriptor, &finalInfo) == 0,
              accepts(finalInfo, maximumBytes: maximumBytes, permissions: permissions),
              finalInfo.st_ino == info.st_ino,
              finalInfo.st_size == info.st_size,
              finalInfo.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              finalInfo.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
              finalInfo.st_ctimespec.tv_sec == info.st_ctimespec.tv_sec,
              finalInfo.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec
        else { return .rejected }
        return .data(data)
    }

    private static func accepts(
        _ info: stat,
        maximumBytes: Int,
        permissions: Permissions
    ) -> Bool {
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              info.st_size > 0,
              info.st_size <= Int64(maximumBytes)
        else { return false }
        switch permissions {
        case .desktopStatus:
            let mode = info.st_mode & 0o777
            return (mode & 0o400) != 0 && (mode & 0o133) == 0
        case .usageMeter:
            return (info.st_mode & 0o777) == 0o600
        }
    }
}

private func optionalProcessID(_ value: Any?) -> Bool {
    guard let value else { return true }
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return false }
    let double = number.doubleValue
    return double.isFinite
        && double.rounded(.towardZero) == double
        && double >= 0
        && double <= Double(Int32.max)
}

private func optionalAppVersion(_ value: Any?) -> Bool {
    guard let value else { return true }
    guard let version = jsonString(value),
          (1...32).contains(version.utf8.count),
          version.unicodeScalars.allSatisfy({ scalar in
              scalar.isASCII && (
                  CharacterSet.alphanumerics.contains(scalar) || "._+-".unicodeScalars.contains(scalar)
              )
          })
    else { return false }
    return true
}

private func jsonBool(_ value: Any?) -> Bool? {
    guard let value, let number = value as? NSNumber else { return nil }
    guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func jsonExactInteger(_ value: Any?) -> Int? {
    guard let value, let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let double = number.doubleValue
    guard double.isFinite,
          double.rounded(.towardZero) == double,
          double >= Double(Int.min),
          double <= Double(Int.max)
    else { return nil }
    return Int(double)
}

private func jsonFiniteNumber(_ value: Any?) -> Double? {
    guard let value, let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let double = number.doubleValue
    return double.isFinite ? double : nil
}

private func jsonString(_ value: Any?) -> String? {
    value as? String
}

private enum OptionalNumber {
    case absent
    case invalid
    case value(Double)
}

private func optionalNumber(_ value: Any?) -> OptionalNumber {
    guard let value else { return .absent }
    guard let number = jsonFiniteNumber(value) else { return .invalid }
    return .value(number)
}

private func pairedPercents(
    used: OptionalNumber,
    remaining: OptionalNumber
) -> (used: Double?, remaining: Double?)? {
    let usedValue: Double?
    switch used {
    case .absent: usedValue = nil
    case .invalid: return nil
    case let .value(number):
        guard (0...100).contains(number) else { return nil }
        usedValue = number
    }
    let remainingValue: Double?
    switch remaining {
    case .absent: remainingValue = nil
    case .invalid: return nil
    case let .value(number):
        guard (0...100).contains(number) else { return nil }
        remainingValue = number
    }
    switch (usedValue, remainingValue) {
    case let (used?, remaining?):
        guard abs((used + remaining) - 100) <= GrokBotUsageStatusContract.percentSumTolerance else {
            return nil
        }
        return (used, remaining)
    case let (used?, nil):
        return (used, nil)
    case let (nil, remaining?):
        return (nil, remaining)
    case (nil, nil):
        return nil
    }
}

private func optionalBool(_ value: Any?, default defaultValue: Bool) -> Bool? {
    guard let value else { return defaultValue }
    return jsonBool(value)
}

private struct OptionalField<Value> {
    let isValid: Bool
    let value: Value?

    static var absent: OptionalField<Value> { OptionalField(isValid: true, value: nil) }
    static var invalid: OptionalField<Value> { OptionalField(isValid: false, value: nil) }
    static func value(_ value: Value) -> OptionalField<Value> {
        OptionalField(isValid: true, value: value)
    }
}

private func optionalDisplayLabel(_ value: Any?) -> OptionalField<String> {
    guard let value else { return .absent }
    guard let label = jsonString(value).flatMap(displayLabel) else { return .invalid }
    return .value(label)
}

private func optionalDate(_ value: Any?) -> OptionalField<Date> {
    guard let value else { return .absent }
    guard let date = utcDate(value) else { return .invalid }
    return .value(date)
}

private func optionalIdentifier(_ value: Any?) -> OptionalField<String> {
    guard let value else { return .absent }
    guard let identifier = jsonString(value).flatMap(boundedIdentifier) else { return .invalid }
    return .value(identifier)
}

private func displayLabel(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          trimmed.utf8.count <= 64,
          !trimmed.contains("@"),
          trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    return trimmed
}

private func boundedIdentifier(_ value: String) -> String? {
    guard (1...64).contains(value.utf8.count),
          value.unicodeScalars.allSatisfy({ scalar in
              scalar.isASCII && (
                  CharacterSet.alphanumerics.contains(scalar) || "-_.:".unicodeScalars.contains(scalar)
              )
          })
    else { return nil }
    return value
}

private func utcDate(_ value: Any?) -> Date? {
    guard let string = jsonString(value), string.utf8.count <= 40 else { return nil }
    let normalized: String
    if string.hasSuffix("Z") {
        normalized = string
    } else if string.hasSuffix("+00:00") || string.hasSuffix("-00:00") {
        normalized = String(string.dropLast(6)) + "Z"
    } else {
        return nil
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    fractional.timeZone = TimeZone(secondsFromGMT: 0)
    if let date = fractional.date(from: normalized) { return date }
    let ordinary = ISO8601DateFormatter()
    ordinary.formatOptions = [.withInternetDateTime]
    ordinary.timeZone = TimeZone(secondsFromGMT: 0)
    return ordinary.date(from: normalized)
}
