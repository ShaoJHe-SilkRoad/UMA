import Foundation
import HESectoriumCore
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Explicit, fixture-rooted deployment transaction. It never launches launchd or mutates a running service.
public final class HESectoriumInstaller: @unchecked Sendable {
    private struct Target { let url: URL; let key: String; let mode: Int }
    private struct Preimage { let target: Target; let data: Data?; let mode: Int?; let postimage: Data }
    private struct RecoveryRecord: Codable {
        let key: String
        let targetPath: String
        let existed: Bool
        let mode: Int?
        let backupFile: String?
        let sha256: String?
        let postimageSHA256: String
    }
    private struct RecoveryManifest: Codable {
        let schema: Int
        let transactionID: String
        let createdAt: String
        let records: [RecoveryRecord]
    }
    private let paths: HESectoriumPaths
    private let home: URL
    private let fileManager: FileManager
    private let beforePreimageCheck: ((URL) -> Void)?
    private let writeFile: ((Data, URL, Int) throws -> Void)?
    private let knownLegacyHashes: Set<String> = [
        "7b18ff4c256b449317a953c9ca5419d8a2153363acb7b14e13ed72efd7104b76",
        "8c1376bd15e41fb24eb0b50679df84ec7e0568f6671d061b068b548d48b2c913",
        "471f364713dc5077adf199fabbaa13b1f57b51407fb0ace850c9b97986f8177e"
    ]
    // Exact control bytes shipped in the 0.14.1 / 2026100403 preview. Limit this
    // upgrade allowance to the control target; it does not admit arbitrary files.
    static func isAcceptedPreviousControl(hash: String, targetKey: String) -> Bool {
        targetKey == "control" && hash == "3266c4dd532a3106d66a18d7a94ac7808d8afdcca2093a2ec29dde79e34810c7"
    }
    public init(paths: HESectoriumPaths, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                fileManager: FileManager = .default, beforePreimageCheck: ((URL) -> Void)? = nil,
                writeFile: ((Data, URL, Int) throws -> Void)? = nil) {
        self.paths = paths; self.home = home.standardizedFileURL; self.fileManager = fileManager
        self.beforePreimageCheck = beforePreimageCheck; self.writeFile = writeFile
    }
    private var targets: [Target] {
        [Target(url: paths.root.appendingPathComponent("HESectoriumControl"), key: "control", mode: 0o700),
         Target(url: paths.config, key: "identityConfig", mode: 0o600),
         Target(url: home.appendingPathComponent(".local/bin/dev-apfs-mount"), key: "devMount", mode: 0o700),
         Target(url: home.appendingPathComponent(".local/bin/he-eject"), key: "eject", mode: 0o700),
         Target(url: home.appendingPathComponent("Library/LaunchAgents/com.juliushe.dev-apfs-mounter.plist"), key: "launchAgent", mode: 0o600)]
    }
    private var automationURL: URL { paths.root.appendingPathComponent("automation.json") }

    /// A registered profile is the configuration authority for its disk. The fixed
    /// identity file remains a compatibility target only while no profiles exist.
    public func status(profileConfigured: Bool = false) -> HESectoriumInstalledStatus {
        var missing = false
        for target in targets where !profileConfigured || target.key != "identityConfig" {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: target.url.path, isDirectory: &isDirectory) {
                if isSymlink(target.url) { return .conflict("Managed target is a dangling symbolic link: \(target.key)") }
                missing = true; continue
            }
            guard !isDirectory.boolValue, !isSymlink(target.url), let attributes = try? fileManager.attributesOfItem(atPath: target.url.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular else { return .conflict("Managed target is not a regular file: \(target.key)") }
            guard (((attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777) == target.mode else {
                return .conflict("Managed target has an unexpected mode: \(target.key)")
            }
            guard let data = try? Data(contentsOf: target.url), !data.isEmpty else { return .conflict("Managed target is unreadable or empty: \(target.key)") }
            if target.key == "devMount" || target.key == "eject" {
                guard let text = String(data: data, encoding: .utf8),
                      text.contains(paths.root.appendingPathComponent("HESectoriumControl").path) else {
                    return .conflict("Compatibility wrapper is not bound to the shared controller: \(target.key)")
                }
            }
            if target.key == "identityConfig" {
                guard let cfg = try? JSONDecoder().decode(StatusIdentityConfiguration.self, from: data),
                      UUID(uuidString: cfg.outerUUID) == StorageIdentityPolicy.expected.outerUUID,
                      UUID(uuidString: cfg.devUUID) == StorageIdentityPolicy.expected.devUUID else {
                    return .conflict("Installed identity configuration is invalid")
                }
            }
            if target.key == "launchAgent" {
                guard SectoriumLaunchAgentConfiguration.matchesInstalledPlist(data,
                    controlPath: paths.root.appendingPathComponent("HESectoriumControl").path,
                    standardOutPath: paths.logs.appendingPathComponent("launch-agent.out.log").path,
                    standardErrorPath: paths.logs.appendingPathComponent("launch-agent.err.log").path) else {
                    return .conflict("LaunchAgent is not bound to the shared controller")
                }
            }
        }
        return missing ? .missing : .installed
    }
    public func apply(_ assets: HESectoriumAssets?, action: HESectoriumInstallAction,
                      profileConfigured: Bool = false) -> HESectoriumInstallResult {
        guard let assets else { return .init(succeeded: false, summary: "Install assets must be supplied by the app bundle or caller") }
        guard profileConfigured || assets.identityConfig != nil else {
            return .init(succeeded: false, summary: "Identity configuration asset is required")
        }
        let assetURLs: [String: URL] = ["control": assets.control, "devMount": assets.devMountWrapper,
                                       "eject": assets.ejectWrapper, "launchAgent": assets.launchAgent]
            .merging(assets.identityConfig.map { ["identityConfig": $0] } ?? [:]) { current, _ in current }
        var outcomes: [HESectoriumFileInstallOutcome] = []
        var recoveryDirectory: URL?
        var transactionPlans: [Preimage] = []
        do {
            for target in targets where !profileConfigured || target.key != "identityConfig" {
                guard let source = assetURLs[target.key], fileManager.fileExists(atPath: source.path) else {
                    throw RuntimeError.installConflict("Missing asset: \(target.key)")
                }
                let raw = try Data(contentsOf: source)
                let post = try prepared(raw, key: target.key)
                guard !post.isEmpty else { throw RuntimeError.installConflict("Empty asset: \(target.key)") }
                let existed = fileManager.fileExists(atPath: target.url.path)
                var oldData: Data?; var oldMode: Int?
                if !existed && isSymlink(target.url) { throw RuntimeError.installConflict("Refusing dangling symbolic link: \(target.key)") }
                if existed {
                    guard !isSymlink(target.url), let attrs = try? fileManager.attributesOfItem(atPath: target.url.path),
                          (attrs[.type] as? FileAttributeType) == .typeRegular else {
                        throw RuntimeError.installConflict("Refusing non-regular managed target: \(target.key)")
                    }
                    oldData = try Data(contentsOf: target.url)
                    oldMode = (attrs[.posixPermissions] as? NSNumber)?.intValue
                    if oldData == post && oldMode.map({ $0 & 0o777 }) == target.mode {
                        transactionPlans.append(.init(target: target, data: oldData, mode: oldMode, postimage: post))
                        outcomes.append(.init(file: target.key, state: .adopted, detail: "Exact bytes and mode already present"))
                        continue
                    }
                    guard oldData.map({
                        let hash = Self.sha256($0)
                        return knownLegacyHashes.contains(hash)
                            || Self.isAcceptedPreviousControl(hash: hash, targetKey: target.key)
                            || (oldMode.map { $0 & 0o777 } == target.mode
                                && hasManagedControlReceipt(hash: hash, target: target))
                    }) == true else {
                        throw RuntimeError.installConflict("Existing target is not a recognized legacy component: \(target.key)")
                    }
                }
                if action == .install && existed && oldData != post {
                    throw RuntimeError.installConflict("Install target already contains a different component: \(target.key)")
                }
                transactionPlans.append(.init(target: target, data: oldData, mode: oldMode, postimage: post))
            }
            // Persist every original byte sequence and mode before the first replacement.
            // The recovery directory and manifest remain on the internal support volume.
            recoveryDirectory = try persistPreimages(transactionPlans, transactionID: UUID().uuidString)
            for plan in transactionPlans {
                if plan.data == plan.postimage && plan.mode.map({ $0 & 0o777 }) == plan.target.mode { continue }
                // Recheck the exact preimage immediately before the write to detect concurrent edits.
                beforePreimageCheck?(plan.target.url)
                let nowExists = fileManager.fileExists(atPath: plan.target.url.path)
                let nowData = nowExists ? try Data(contentsOf: plan.target.url) : nil
                let nowAttributes = nowExists ? try? fileManager.attributesOfItem(atPath: plan.target.url.path) : nil
                let nowMode = (nowAttributes?[.posixPermissions] as? NSNumber)?.intValue
                guard nowData == plan.data, nowMode == plan.mode else {
                    outcomes.append(.init(file: plan.target.key, state: .withheld, detail: "Preimage bytes or mode changed before replacement"))
                    throw RuntimeError.installConflict("Target changed during install: \(plan.target.key)")
                }
                try secureDirectory(plan.target.url.deletingLastPathComponent())
                do {
                    try write(plan.postimage, to: plan.target.url, mode: plan.target.mode)
                } catch {
                    // The injected writer may mutate and then throw. Let the recovery path
                    // inspect the resulting target; never assume a throwing write changed nothing.
                    throw error
                }
                guard currentMatches(plan.target.url, data: plan.postimage, mode: plan.target.mode) else {
                    outcomes.append(.init(file: plan.target.key, state: .withheld, detail: "Write returned but postimage bytes or mode did not verify"))
                    throw RuntimeError.installConflict("Postimage verification failed: \(plan.target.key)")
                }
                outcomes.append(.init(file: plan.target.key, state: .installed, detail: "Bytes and mode verified"))
            }
            let changed = outcomes.contains { $0.state == .installed }
            return .init(succeeded: true,
                         summary: changed ? "Install complete; durable recovery copy: \(recoveryDirectory?.path ?? "unavailable")" : "Existing HESectorium components adopted; no files changed",
                         changedPaths: transactionPlans.filter { plan in outcomes.contains(where: { $0.file == plan.target.key && $0.state == .installed }) }.map { $0.target.url.path },
                         fileOutcomes: outcomes)
        } catch {
            // Roll back only exact postimages. A changed/partial target is retained beside
            // its durable backup so a later explicit recovery can inspect it safely.
            var updatedOutcomes = outcomes.filter { $0.state == .adopted || $0.state == .withheld }
            for plan in transactionPlans.reversed() {
                if currentMatches(plan.target.url, data: plan.data, mode: plan.mode) {
                    if !updatedOutcomes.contains(where: { $0.file == plan.target.key }) {
                        updatedOutcomes.append(.init(file: plan.target.key, state: .unchanged, detail: "Original preimage remains intact"))
                    }
                    continue
                }
                guard currentMatches(plan.target.url, data: plan.postimage, mode: plan.target.mode) else {
                    updatedOutcomes.removeAll { $0.file == plan.target.key && $0.state == .installed }
                    updatedOutcomes.append(.init(file: plan.target.key, state: .withheld,
                                                 detail: "Target differs from both preimage and expected postimage; durable recovery retained"))
                    continue
                }
                do {
                    if let prior = plan.data { try write(prior, to: plan.target.url, mode: plan.mode ?? plan.target.mode) }
                    else { try fileManager.removeItem(at: plan.target.url) }
                    guard currentMatches(plan.target.url, data: plan.data, mode: plan.mode) else {
                        throw RuntimeError.installConflict("Restored preimage did not verify")
                    }
                    updatedOutcomes.removeAll { $0.file == plan.target.key }
                    updatedOutcomes.append(.init(file: plan.target.key, state: .restored, detail: "Original bytes and mode restored"))
                } catch {
                    // A writer can throw after successfully restoring; verify before reporting failure.
                    if currentMatches(plan.target.url, data: plan.data, mode: plan.mode) {
                        updatedOutcomes.removeAll { $0.file == plan.target.key }
                        updatedOutcomes.append(.init(file: plan.target.key, state: .restored, detail: "Original bytes and mode restored despite writer error"))
                    } else {
                        updatedOutcomes.removeAll { $0.file == plan.target.key }
                        updatedOutcomes.append(.init(file: plan.target.key, state: .withheld,
                                                     detail: "Rollback failed; durable recovery retained: \(error.localizedDescription)"))
                    }
                }
            }
            let summary = "Install incomplete: \(error.localizedDescription); recovery \(recoveryDirectory?.path ?? "manifest not created")"
            let changedPaths = updatedOutcomes.filter { $0.state == .withheld || $0.state == .installed }.compactMap { outcome in
                targets.first(where: { $0.key == outcome.file })?.url.path
            }
            return .init(succeeded: false, summary: summary, changedPaths: changedPaths, fileOutcomes: updatedOutcomes)
        }
    }
    public func setAutomation(_ enabled: Bool) -> HESectoriumInstallResult {
        do {
            try secureDirectory(paths.root)
            let data = try JSONEncoder().encode(AutomationConfiguration(enabled: enabled))
            try write(data, to: automationURL, mode: 0o600)
            return .init(succeeded: true, summary: enabled ? "Automation enabled" : "Automation disabled; disks unchanged")
        } catch { return .init(succeeded: false, summary: "Could not save automation setting: \(error.localizedDescription)") }
    }
    public func automationEnabled() -> Bool {
        guard automationURL.standardizedFileURL.path == automationURL.resolvingSymlinksInPath().path,
              let attrs = try? fileManager.attributesOfItem(atPath: automationURL.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let data = try? Data(contentsOf: automationURL) else { return false }
        return (try? JSONDecoder().decode(AutomationConfiguration.self, from: data).enabled) ?? false
    }
    public func appendDiagnostic(_ value: String, to directory: URL) {
        do {
            try secureDirectory(directory)
            let file = directory.appendingPathComponent("hesectorium.log")
            let safeExistingLog = file.standardizedFileURL.path == file.resolvingSymlinksInPath().path &&
                (try? fileManager.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType) == .typeRegular
            var contents = safeExistingLog ? ((try? String(contentsOf: file, encoding: .utf8)) ?? "") : ""
            contents += "\(ISO8601DateFormatter().string(from: Date())) \(String(value.prefix(240)))\n"
            if contents.utf8.count > 16_384 { contents = String(contents.suffix(12_000)) }
            try atomicWrite(Data(contents.utf8), to: file, mode: 0o600)
        } catch { /* diagnostics are best-effort and never change operation outcome */ }
    }
    private func prepared(_ raw: Data, key: String) throws -> Data {
        guard ["launchAgent", "devMount", "eject"].contains(key) else { return raw }
        guard let template = String(data: raw, encoding: .utf8) else {
            throw RuntimeError.installConflict("Managed text asset is not valid UTF-8: \(key)")
        }
        var value = template.replacingOccurrences(of: "__UMA_CONTROL_PATH__", with: paths.root.appendingPathComponent("HESectoriumControl").path)
        if key == "launchAgent" {
            value = value
            .replacingOccurrences(of: "__UMA_LOG_OUT__", with: paths.logs.appendingPathComponent("launch-agent.out.log").path)
            .replacingOccurrences(of: "__UMA_LOG_ERR__", with: paths.logs.appendingPathComponent("launch-agent.err.log").path)
        }
        guard !value.contains("__UMA_") else { throw RuntimeError.installConflict("LaunchAgent path token unresolved") }
        let prepared = Data(value.utf8)
        if key == "launchAgent" {
            guard SectoriumLaunchAgentConfiguration.matchesInstalledPlist(prepared,
                controlPath: paths.root.appendingPathComponent("HESectoriumControl").path,
                standardOutPath: paths.logs.appendingPathComponent("launch-agent.out.log").path,
                standardErrorPath: paths.logs.appendingPathComponent("launch-agent.err.log").path) else {
                throw RuntimeError.installConflict("LaunchAgent asset has an unexpected label, program, arguments, or configuration")
            }
        }
        return prepared
    }
    private func secureDirectory(_ directory: URL) throws {
        try SecureDirectory.ensure(directory)
        guard !isSymlink(directory), directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().path,
              let attrs = try? fileManager.attributesOfItem(atPath: directory.path),
              (attrs[.type] as? FileAttributeType) == .typeDirectory else { throw RuntimeError.unsafePath("managed parent is not a plain directory") }
    }
    private func isSymlink(_ url: URL) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }
    private func atomicWrite(_ data: Data, to url: URL, mode: Int) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).hesectorium-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        #if canImport(Darwin)
        guard chmod(temp.path, mode_t(mode)) == 0 else { try? fileManager.removeItem(at: temp); throw RuntimeError.unsafePath("could not set managed file mode") }
        guard !isSymlink(url) else {
            try? fileManager.removeItem(at: temp)
            throw RuntimeError.unsafePath("refusing to replace a symbolic link")
        }
        let renameResult = temp.path.withCString { source in
            url.path.withCString { destination in Darwin.rename(source, destination) }
        }
        guard renameResult == 0 else {
            let failure = errno
            try? fileManager.removeItem(at: temp)
            throw RuntimeError.unsafePath("could not atomically replace managed file (errno \(failure))")
        }
        #else
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temp, backupItemName: nil, options: [])
        } else { try fileManager.moveItem(at: temp, to: url) }
        #endif
    }
    private func write(_ data: Data, to url: URL, mode: Int) throws {
        if let writeFile { try writeFile(data, url, mode) }
        else { try atomicWrite(data, to: url, mode: mode) }
    }
    private func persistPreimages(_ plans: [Preimage], transactionID: String) throws -> URL {
        let recoveryRoot = paths.root.appendingPathComponent("Recovery", isDirectory: true)
        try secureDirectory(recoveryRoot)
        try syncDirectory(paths.root)
        let directory = recoveryRoot.appendingPathComponent(transactionID, isDirectory: true)
        try secureDirectory(directory)
        try syncDirectory(recoveryRoot)
        var records: [RecoveryRecord] = []
        for plan in plans {
            let filename = plan.data == nil ? nil : "\(plan.target.key).preimage"
            if let filename, let data = plan.data {
                let backup = directory.appendingPathComponent(filename)
                try durableAtomicWrite(data, to: backup, mode: 0o600)
            }
            records.append(.init(key: plan.target.key, targetPath: plan.target.url.path, existed: plan.data != nil,
                                 mode: plan.mode.map { $0 & 0o777 }, backupFile: filename,
                                 sha256: plan.data.map(Self.sha256), postimageSHA256: Self.sha256(plan.postimage)))
        }
        let manifest = RecoveryManifest(schema: 1, transactionID: transactionID,
                                        createdAt: ISO8601DateFormatter().string(from: Date()), records: records)
        let encoded = try JSONEncoder().encode(manifest)
        try durableAtomicWrite(encoded, to: directory.appendingPathComponent("manifest.json"), mode: 0o600)
        return directory
    }
    /// The existing durable installation record also identifies a previously managed
    /// control executable. Match its exact postimage, never a name or arbitrary binary.
    /// This is local upgrade provenance, not signature verification or host permission.
    private func hasManagedControlReceipt(hash: String, target: Target) -> Bool {
        guard target.key == "control", target.url == paths.root.appendingPathComponent("HESectoriumControl"),
              plainOwnedItem(target.url, type: .typeRegular, mode: target.mode),
              plainOwnedItem(paths.root, type: .typeDirectory, mode: 0o700) else { return false }
        let recoveryRoot = paths.root.appendingPathComponent("Recovery", isDirectory: true)
        guard plainOwnedItem(recoveryRoot, type: .typeDirectory, mode: 0o700),
              let directories = try? fileManager.contentsOfDirectory(at: recoveryRoot,
                  includingPropertiesForKeys: nil) else { return false }
        let expectedKeys = Set(targets.map(\.key))
        let profileKeys = expectedKeys.subtracting(["identityConfig"])
        for directory in directories {
            guard let transaction = UUID(uuidString: directory.lastPathComponent),
                  transaction.uuidString == directory.lastPathComponent,
                  plainOwnedItem(directory, type: .typeDirectory, mode: 0o700) else { continue }
            let receipt = directory.appendingPathComponent("manifest.json")
            guard plainOwnedItem(receipt, type: .typeRegular, mode: 0o600),
                  let size = try? fileManager.attributesOfItem(atPath: receipt.path)[.size] as? NSNumber,
                  size.intValue > 0, size.intValue <= 65_536,
                  let data = try? Data(contentsOf: receipt),
                  let manifest = try? JSONDecoder().decode(RecoveryManifest.self, from: data),
                  manifest.schema == 1, manifest.transactionID == transaction.uuidString,
                  ISO8601DateFormatter().date(from: manifest.createdAt) != nil else { continue }
            let keys = Set(manifest.records.map(\.key))
            guard keys.count == manifest.records.count,
                  keys == expectedKeys || keys == profileKeys,
                  manifest.records.allSatisfy({ record in
                      targets.contains { $0.key == record.key && $0.url.path == record.targetPath }
                  }),
                  let control = manifest.records.first(where: { $0.key == "control" }),
                  control.postimageSHA256 == hash else { continue }
            // A retained preimage must remain usable when the transaction replaced
            // an earlier control. New installations explicitly have no preimage.
            if control.existed {
                guard control.backupFile == "control.preimage", let priorMode = control.mode,
                      (0...0o777).contains(priorMode), let priorHash = control.sha256 else { continue }
                let backup = directory.appendingPathComponent("control.preimage")
                guard plainOwnedItem(backup, type: .typeRegular, mode: 0o600),
                      let bytes = try? Data(contentsOf: backup), Self.sha256(bytes) == priorHash else { continue }
            } else if control.backupFile != nil || control.mode != nil || control.sha256 != nil { continue }
            return true
        }
        return false
    }
    private func plainOwnedItem(_ url: URL, type: FileAttributeType, mode: Int) -> Bool {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == type,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o7777 == mode else { return false }
        #if canImport(Darwin)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else { return false }
        #endif
        return true
    }
    /// Restores only the targets that still contain an exact transaction postimage. A fresh
    /// process may call this explicit, fixture-testable recovery using the retained manifest.
    public func recoverInterruptedInstall(transactionID: String) -> HESectoriumInstallResult {
        guard let identifier = UUID(uuidString: transactionID), identifier.uuidString == transactionID.uppercased() else {
            return .init(succeeded: false, summary: "Invalid recovery transaction identifier")
        }
        let directory = paths.root.appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(identifier.uuidString, isDirectory: true)
        guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().path,
              let manifestData = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(RecoveryManifest.self, from: manifestData),
              manifest.schema == 1, manifest.transactionID == identifier.uuidString else {
            return .init(succeeded: false, summary: "Recovery manifest is unavailable or invalid")
        }
        var outcomes: [HESectoriumFileInstallOutcome] = []
        for record in manifest.records.reversed() {
            guard let target = targets.first(where: { $0.key == record.key && $0.url.path == record.targetPath }) else {
                outcomes.append(.init(file: record.key, state: .withheld, detail: "Manifest target is outside the fixed managed target set"))
                continue
            }
            let prior: Data?
            if record.existed {
                guard record.backupFile == "\(record.key).preimage",
                      let backupFile = record.backupFile,
                      let backup = try? Data(contentsOf: directory.appendingPathComponent(backupFile)),
                      Self.sha256(backup) == record.sha256 else {
                    outcomes.append(.init(file: target.key, state: .withheld, detail: "Durable preimage is missing or corrupt"))
                    continue
                }
                prior = backup
            } else { prior = nil }
            if currentMatches(target.url, data: prior, mode: record.mode) {
                outcomes.append(.init(file: target.key, state: .unchanged, detail: "Original preimage already present"))
                continue
            }
            guard let current = try? Data(contentsOf: target.url), !isSymlink(target.url),
                  Self.sha256(current) == record.postimageSHA256,
                  let attrs = try? fileManager.attributesOfItem(atPath: target.url.path),
                  (((attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777) == target.mode else {
                outcomes.append(.init(file: target.key, state: .withheld, detail: "Target is not the exact transaction postimage; preserved without overwrite"))
                continue
            }
            do {
                if let prior { try write(prior, to: target.url, mode: record.mode ?? target.mode) }
                else { try fileManager.removeItem(at: target.url) }
                guard currentMatches(target.url, data: prior, mode: record.mode) else {
                    throw RuntimeError.installConflict("Recovered preimage did not verify")
                }
                outcomes.append(.init(file: target.key, state: .restored, detail: "Original bytes and mode restored from durable recovery"))
            } catch {
                outcomes.append(.init(file: target.key, state: .withheld,
                                     detail: "Recovery write failed: \(error.localizedDescription); preimage remains retained"))
            }
        }
        let succeeded = outcomes.allSatisfy { $0.state == .restored || $0.state == .unchanged }
        let changed = outcomes.filter { $0.state == .withheld }.compactMap { outcome in targets.first(where: { $0.key == outcome.file })?.url.path }
        return .init(succeeded: succeeded,
                     summary: succeeded ? "Interrupted install recovered from durable preimages" : "Interrupted install recovery incomplete; conflicts were preserved",
                     changedPaths: changed, fileOutcomes: outcomes)
    }
    private func currentMatches(_ url: URL, data: Data?, mode: Int?) -> Bool {
        let exists = fileManager.fileExists(atPath: url.path)
        guard exists == (data != nil) else { return false }
        guard let data else { return true }
        guard !isSymlink(url), let current = try? Data(contentsOf: url), current == data,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let currentMode = (attributes[.posixPermissions] as? NSNumber)?.intValue else { return false }
        return mode.map { currentMode & 0o777 == ($0 & 0o777) } ?? false
    }
    private func durableAtomicWrite(_ data: Data, to url: URL, mode: Int) throws {
        try atomicWrite(data, to: url, mode: mode)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        #if canImport(Darwin)
        try syncDirectory(url.deletingLastPathComponent())
        #endif
    }
    private func syncDirectory(_ directory: URL) throws {
        #if canImport(Darwin)
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RuntimeError.unsafePath("could not open recovery directory for sync") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw RuntimeError.unsafePath("could not sync recovery directory") }
        #endif
    }
    private static func sha256(_ data: Data) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return ""
        #endif
    }
}
private struct AutomationConfiguration: Codable { let enabled: Bool }
private struct StatusIdentityConfiguration: Codable { let outerUUID: String; let devUUID: String }
