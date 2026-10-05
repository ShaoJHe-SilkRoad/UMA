import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime
#if canImport(CryptoKit)
import CryptoKit
#endif

private final class MemoryStore: DurableStateStore {
    var value: StoragePersistentState
    init(_ value: StoragePersistentState = .init(ejectIntent: false)) { self.value = value }
    func load() throws -> StoragePersistentState { value }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        guard value.revision == expectedRevision else { return false }; value = newState; return true
    }
}
private final class MemoryLock: OperationLock {
    private(set) var held = false
    func acquire() -> Bool { guard !held else { return false }; held = true; return true }
    func release() { held = false }
}
private final class FixtureBackend: StorageBackend {
    var observation: StorageObservation? = .expectedReady
    var outerObservation: VolumeIdentity? = StorageObservation.expectedReady.outer
    var attachCount = 0
    var performed: [EjectStep] = []
    var occupancyChecks = 0
    var occupancy: [OccupancyScope: OccupancyAssessment] = [.dev: .noVisibleOccupancy, .outer: .noVisibleOccupancy]
    var final: FinalOuterState = .absent
    func observeOuter() -> VolumeIdentity? { outerObservation }
    func observe() -> StorageObservation? { observation }
    func attachImage() -> CommandOutcome { attachCount += 1; return .success }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { occupancyChecks += 1; return occupancy[scope] ?? .incomplete(reason: "fixture unset") }
    func perform(_ step: EjectStep) -> CommandOutcome { performed.append(step); return .success }
    func finalOuterState() -> FinalOuterState { final }
}
private final class FixtureAgentStatusProvider: HESectoriumAgentStatusProviding {
    var value: HESectoriumAgentLoadStatus
    init(_ value: HESectoriumAgentLoadStatus = .unknown) { self.value = value }
    func loadStatus(label: String) -> HESectoriumAgentLoadStatus { value }
}
private final class ScriptedRunner: HESectoriumCommandRunning {
    var outputs: [String: CommandOutcome] = [:]
    private(set) var invocations: [(String, [String], URL)] = []
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        invocations.append((executable, arguments, cwd))
        let key = executable + " " + arguments.joined(separator: " ")
        return outputs[key] ?? .init(exitCode: 127, detail: "fixture command not configured")
    }
}

private func plistText(_ value: Any) throws -> String {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    return String(decoding: data, as: UTF8.self)
}

private func diskInfo(_ values: [String: Any]) throws -> CommandOutcome {
    .init(exitCode: 0, detail: try plistText(values))
}

private func fixtureSHA256(_ data: Data) -> String {
    #if canImport(CryptoKit)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    #else
    return "unavailable"
    #endif
}

private struct Fixture {
    let root: URL; let paths: HESectoriumPaths; let home: URL; let assets: HESectoriumAssets
    init() throws {
        let fixtureBase = URL(fileURLWithPath: "/private/tmp/hesectorium-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureBase, withIntermediateDirectories: true)
        let requestedRoot = fixtureBase.appendingPathComponent("hesectorium-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: false)
        root = requestedRoot.resolvingSymlinksInPath()
        paths = .init(root: root.appendingPathComponent("support", isDirectory: true)); home = root.appendingPathComponent("home", isDirectory: true)
        let source = root.appendingPathComponent("assets", isDirectory: true); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let control = source.appendingPathComponent("HESectoriumControl"); try Data("fixture-control".utf8).write(to: control)
        let mount = source.appendingPathComponent("dev-apfs-mount"); try Data("#!/bin/sh\nexec \"__UMA_CONTROL_PATH__\" mount\n".utf8).write(to: mount)
        let eject = source.appendingPathComponent("he-eject"); try Data("#!/bin/sh\nexec \"__UMA_CONTROL_PATH__\" eject\n".utf8).write(to: eject)
        let agent = source.appendingPathComponent("agent.plist")
        try Data("<plist><string>com.juliushe.dev-apfs-mounter</string><string>__UMA_CONTROL_PATH__</string><string>__UMA_LOG_OUT__</string><string>__UMA_LOG_ERR__</string></plist>".utf8).write(to: agent)
        let config = source.appendingPathComponent("identity.json")
        let identity = """
        {"outerUUID":"2FE2A779-0DC8-3468-8E3C-E113598C46CE","devUUID":"0476F9CC-86A3-40D8-A8D4-83D882522CAD","outerMountPoint":"/Volumes/HE","devMountPoint":"/Volumes/HE/DEV","devVolumeName":"DEV_APFS","imagePath":"/Volumes/HE/.DEV-APFS.sparsebundle"}
        """
        try Data(identity.utf8).write(to: config)
        assets = .init(control: control, devMountWrapper: mount, ejectWrapper: eject, launchAgent: agent, identityConfig: config)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func secureDirectoryMapsSystemTempAliasesAndRejectsNestedSymlinks() throws {
    let f = try Fixture(); defer { f.remove() }

    let tmpAliasTarget = f.root.appendingPathComponent("tmp-alias/managed", isDirectory: true)
    try SecureDirectory.ensure(tmpAliasTarget)
    #expect(FileManager.default.fileExists(atPath: tmpAliasTarget.path))

    let rawTemporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
    let varAliasPath: String
    if rawTemporaryDirectory.hasPrefix("/private/var/") {
        varAliasPath = rawTemporaryDirectory.replacingOccurrences(of: "/private/var/", with: "/var/")
    } else if rawTemporaryDirectory.hasPrefix("/var/") {
        varAliasPath = rawTemporaryDirectory
    } else {
        Issue.record("Fixture temporary directory does not use the macOS /var alias: \(rawTemporaryDirectory)")
        return
    }
    let varAliasTarget = URL(fileURLWithPath: varAliasPath, isDirectory: true)
        .appendingPathComponent("hesectorium-var-alias-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: varAliasTarget) }
    try SecureDirectory.ensure(varAliasTarget)
    #expect(FileManager.default.fileExists(atPath: varAliasTarget.path))

    let symlinkTarget = f.root.appendingPathComponent("symlink-target", isDirectory: true)
    try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: false)
    let symlinkParent = f.root.appendingPathComponent("symlink-parent", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: symlinkParent, withDestinationURL: symlinkTarget)
    let traversalWasRejected: Bool
    do {
        try SecureDirectory.ensure(symlinkParent.appendingPathComponent("managed", isDirectory: true))
        traversalWasRejected = false
    } catch {
        traversalWasRejected = true
    }
    #expect(traversalWasRejected)
}

@Test func explicitInstallIsIdempotentAndAdoptsItsOwnPostimages() throws {
    let f = try Fixture(); defer { f.remove() }
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home)
    let first = installer.apply(f.assets, action: .install)
    #expect(first.succeeded)
    #expect(first.changedPaths.count == 5)
    #expect(installer.status() == .installed)
    let second = installer.apply(f.assets, action: .install)
    #expect(second.succeeded)
    #expect(second.changedPaths.isEmpty)
    #expect(second.summary.contains("adopted"))
}

@Test func unknownExistingTargetBlocksBeforeAnyWrite() throws {
    let f = try Fixture(); defer { f.remove() }
    let eject = f.home.appendingPathComponent(".local/bin/he-eject")
    try FileManager.default.createDirectory(at: eject.deletingLastPathComponent(), withIntermediateDirectories: true)
    let userContent = Data("user-owned".utf8); try userContent.write(to: eject)
    let result = HESectoriumInstaller(paths: f.paths, home: f.home).apply(f.assets, action: .repair)
    #expect(!result.succeeded)
    #expect(try Data(contentsOf: eject) == userContent)
    #expect(!FileManager.default.fileExists(atPath: f.paths.root.appendingPathComponent("HESectoriumControl").path))
}

@Test func unknownExistingIdentityConfigurationIsPreservedAndBlocksInstall() throws {
    let f = try Fixture(); defer { f.remove() }
    try FileManager.default.createDirectory(at: f.paths.root, withIntermediateDirectories: true)
    let unknown = Data("{\"outerUUID\":\"user-owned-identity\"}".utf8)
    try unknown.write(to: f.paths.config)

    let result = HESectoriumInstaller(paths: f.paths, home: f.home).apply(f.assets, action: .repair)

    #expect(!result.succeeded)
    #expect(try Data(contentsOf: f.paths.config) == unknown)
    #expect(!FileManager.default.fileExists(atPath: f.paths.root.appendingPathComponent("HESectoriumControl").path))
    #expect(!result.fileOutcomes.contains(where: { $0.state == .installed }))
}

@Test func frozenLegacyLaunchAgentIsAdoptedByExactBytesAndMode() throws {
    let f = try Fixture(); defer { f.remove() }
    let frozen = URL(fileURLWithPath: "/Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0141-UI-HES-INTAKE-01/integration-r1/inputs/com.juliushe.dev-apfs-mounter.plist")
    let frozenBytes = try Data(contentsOf: frozen)
    #expect(fixtureSHA256(frozenBytes) == "471f364713dc5077adf199fabbaa13b1f57b51407fb0ace850c9b97986f8177e")
    let target = f.home.appendingPathComponent("Library/LaunchAgents/com.juliushe.dev-apfs-mounter.plist")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try frozenBytes.write(to: target)
    let frozenMode = (try FileManager.default.attributesOfItem(atPath: frozen.path)[.posixPermissions] as! NSNumber).intValue & 0o777
    try FileManager.default.setAttributes([.posixPermissions: frozenMode], ofItemAtPath: target.path)

    let result = HESectoriumInstaller(paths: f.paths, home: f.home).apply(f.assets, action: .repair)

    #expect(result.succeeded)
    #expect(result.fileOutcomes.first(where: { $0.file == "launchAgent" })?.state == .installed)
    #expect(try Data(contentsOf: target) != frozenBytes)
    let recoveryRoot = f.paths.root.appendingPathComponent("Recovery", isDirectory: true)
    let recovery = try #require(try FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil).first)
    let backup = recovery.appendingPathComponent("launchAgent.preimage")
    #expect(try Data(contentsOf: backup) == frozenBytes)
    #expect(((try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as! NSNumber).intValue & 0o777) == 0o600)
}

@Test func postMutationWriteFailureIsRecoverableByFreshInstaller() throws {
    let f = try Fixture(); defer { f.remove() }
    let target = f.home.appendingPathComponent("Library/LaunchAgents/com.juliushe.dev-apfs-mounter.plist")
    let frozen = URL(fileURLWithPath: "/Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0141-UI-HES-INTAKE-01/integration-r1/inputs/com.juliushe.dev-apfs-mounter.plist")
    let original = try Data(contentsOf: frozen)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try original.write(to: target)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
    var launchAgentWrites = 0
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home, writeFile: { data, url, mode in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if url == target {
            launchAgentWrites += 1
            if launchAgentWrites > 1 { throw CocoaError(.fileWriteUnknown) }
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        if url == target && launchAgentWrites == 1 { throw CocoaError(.fileWriteUnknown) }
    })

    let interrupted = installer.apply(f.assets, action: .repair)

    #expect(!interrupted.succeeded)
    let outcomeDiagnostic = interrupted.fileOutcomes.map { "\($0.file)=\($0.state.rawValue):\($0.detail)" }.joined(separator: "; ")
    #expect(interrupted.fileOutcomes.first(where: { $0.file == "launchAgent" })?.state == .withheld,
            "\(interrupted.summary); outcomes: [\(outcomeDiagnostic)]")
    #expect(try Data(contentsOf: target) != original)
    let recoveryRoot = f.paths.root.appendingPathComponent("Recovery", isDirectory: true)
    let recovery = try #require(try FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil).first)
    let freshProcess = HESectoriumInstaller(paths: f.paths, home: f.home)
    let recovered = freshProcess.recoverInterruptedInstall(transactionID: recovery.lastPathComponent)
    let recoveryDiagnostic = recovered.fileOutcomes.map { "\($0.file)=\($0.state.rawValue):\($0.detail)" }.joined(separator: "; ")
    #expect(recovered.succeeded, "\(recovered.summary); outcomes: [\(recoveryDiagnostic)]")
    #expect(recovered.fileOutcomes.contains(where: { $0.file == "launchAgent" && $0.state == .restored }))
    #expect(try Data(contentsOf: target) == original)
    #expect(((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as! NSNumber).intValue & 0o777) == 0o644)
}

@Test func failedWriteRollsBackOnlyItsOwnPostimages() throws {
    let f = try Fixture(); defer { f.remove() }
    let failTarget = "he-eject"
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home, writeFile: { data, url, mode in
        if url.lastPathComponent == failTarget { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    })
    let result = installer.apply(f.assets, action: .install)
    #expect(!result.succeeded)
    #expect(!FileManager.default.fileExists(atPath: f.paths.root.appendingPathComponent("HESectoriumControl").path))
    #expect(!FileManager.default.fileExists(atPath: f.paths.config.path))
    #expect(!FileManager.default.fileExists(atPath: f.home.appendingPathComponent(".local/bin/dev-apfs-mount").path))
}

@Test func concurrentPreimageChangeIsNotOverwritten() throws {
    let f = try Fixture(); defer { f.remove() }
    let control = f.paths.root.appendingPathComponent("HESectoriumControl")
    var changed = false
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home, beforePreimageCheck: { target in
        guard target == control, !changed else { return }
        changed = true
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("concurrent-user-edit".utf8).write(to: target)
    })
    let result = installer.apply(f.assets, action: .install)
    #expect(!result.succeeded)
    #expect(try Data(contentsOf: control) == Data("concurrent-user-edit".utf8))
    #expect(!FileManager.default.fileExists(atPath: f.paths.config.path))
    #expect(result.fileOutcomes.contains(where: { $0.file == "control" && $0.state == .withheld }))
    #expect(result.fileOutcomes.contains(where: { $0.file == "identityConfig" && $0.state == .unchanged }))
}

@Test func concurrentModeChangeIsNotOverwritten() throws {
    let f = try Fixture(); defer { f.remove() }
    let control = f.paths.root.appendingPathComponent("HESectoriumControl")
    let legacyURL = URL(fileURLWithPath: "/Volumes/HE/DEV/TOSUMA/.thread-os-runtime/evidence/UMA-0141-UI-HES-INTAKE-01/integration-r1/inputs/dev-apfs-mount")
    let legacy = try Data(contentsOf: legacyURL)
    #expect(fixtureSHA256(legacy) == "7b18ff4c256b449317a953c9ca5419d8a2153363acb7b14e13ed72efd7104b76")
    try FileManager.default.createDirectory(at: control.deletingLastPathComponent(), withIntermediateDirectories: true)
    try legacy.write(to: control)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: control.path)
    var changed = false
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home, beforePreimageCheck: { target in
        guard target == control, !changed else { return }
        changed = true
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    })

    let result = installer.apply(f.assets, action: .repair)

    #expect(!result.succeeded)
    #expect(try Data(contentsOf: control) == legacy)
    #expect(((try FileManager.default.attributesOfItem(atPath: control.path)[.posixPermissions] as! NSNumber).intValue & 0o777) == 0o600)
    #expect(result.fileOutcomes.contains(where: { $0.file == "control" && $0.state == .withheld }))
    #expect(result.fileOutcomes.contains(where: { $0.file == "identityConfig" && $0.state == .unchanged }))
}

@Test func missingIdentityConfigBlocksActionsAndStatusWithoutDiskCommands() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend(); let store = MemoryStore(); let lock = MemoryLock()
    let service = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: lock,
                                     installer: HESectoriumInstaller(paths: f.paths, home: f.home))
    let snapshot = service.refreshStatus()
    #expect(snapshot.readiness == .notReady("identity configuration missing or invalid"))
    #expect(!service.mountDEV().succeeded)
    #expect(!service.safeEjectHE().succeeded)
    let startup = service.runAutomationAgentAtStartup()
    #expect(startup.steps.first?.step == "automationGate")
    #expect(backend.attachCount == 0)
    #expect(backend.performed.isEmpty)
}

@Test func compatibilityEjectRefusesWithoutWholeDeviceCheckpointOrStorageDispatch() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend(), store = MemoryStore(), lock = MemoryLock(), runner = ScriptedRunner()
    let service = HESectoriumService(paths: f.paths, backend: backend, store: store,
        operationLock: lock, runner: runner, identityPolicy: .expected)

    let result = service.safeEjectHE()

    #expect(!result.succeeded)
    #expect(result.failure == .workbenchFailed("whole-device eject requires a fresh user-reviewed confirmation"))
    #expect(result.steps.map(\.step) == ["requireWholeDeviceEjectConfirmation"])
    #expect(backend.occupancyChecks == 0)
    #expect(backend.performed.isEmpty)
    #expect(runner.invocations.isEmpty)
    #expect(!store.value.ejectIntent)
}

@Test func startupAutomaticMountRequiresValidIdentityAndNoPendingIntent() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend(); let store = MemoryStore(); let lock = MemoryLock()
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home)
    try FileManager.default.createDirectory(at: f.paths.root, withIntermediateDirectories: true)
    try Data("invalid".utf8).write(to: f.paths.config)
    let invalid = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: lock, installer: installer)
    #expect(invalid.refreshStatus().readiness == .notReady("identity configuration missing or invalid"))
    #expect(invalid.runAutomationAgentAtStartup().steps.first?.step == "automationGate")
    #expect(backend.attachCount == 0)

    try Data(contentsOf: f.assets.identityConfig!).write(to: f.paths.config)
    let valid = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: lock, installer: installer)
    #expect(valid.setAutomationEnabled(true).succeeded)
    store.value = .init(revision: 1, ejectIntent: true, operationID: "pending")
    let pending = valid.runAutomationAgentAtStartup()
    #expect(pending.failure == .recoveryRequiresManualMount)
    #expect(backend.attachCount == 0)
}

@Test func finalOuterStateRequiresCompleteUUIDEnumeration() throws {
    let f = try Fixture(); defer { f.remove() }
    let runner = ScriptedRunner(); let backend = MacStorageBackend(paths: f.paths, runner: runner)
    let listKey = "/usr/sbin/diskutil list -plist"
    let infoKey = "/usr/sbin/diskutil info -plist /dev/disk9"
    runner.outputs[listKey] = .init(exitCode: 0, detail: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>AllDisks</key><array><string>disk9</string></array></dict></plist>")
    runner.outputs[infoKey] = .init(exitCode: 0, detail: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>VolumeUUID</key><string>\(StorageIdentityPolicy.expected.outerUUID.uuidString)</string></dict></plist>")
    #expect(backend.finalOuterState() == .stillPresent)
    runner.outputs[infoKey] = .init(exitCode: 0, detail: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>VolumeUUID</key><string>11111111-1111-1111-1111-111111111111</string></dict></plist>")
    #expect(backend.finalOuterState() == .absent)
    runner.outputs[infoKey] = .init(exitCode: 1, detail: "disk info denied")
    #expect(backend.finalOuterState() == .unknown("one or more listed devices could not be inspected"))
    #expect(runner.invocations.allSatisfy { $0.2 == f.paths.workingDirectory })
}

@Test func imageBackingAndDevAPFSChainMustMatchReadOnlyCommandOutput() throws {
    let f = try Fixture(); defer { f.remove() }
    let p = StorageIdentityPolicy.expected
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist /Volumes/HE"] = try diskInfo([
        "VolumeUUID": p.outerUUID.uuidString, "MountPoint": p.outerMountPoint, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk20s1", "PartOfWhole": "disk20"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist /Volumes/HE/DEV"] = try diskInfo([
        "VolumeUUID": p.devUUID!.uuidString, "MountPoint": p.devMountPoint, "FilesystemType": "APFS",
        "WritableVolume": true, "VolumeName": p.devVolumeName, "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk31s1"] = runner.outputs["/usr/sbin/diskutil info -plist /Volumes/HE/DEV"]!
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk20s1"] = runner.outputs["/usr/sbin/diskutil info -plist /Volumes/HE"]!
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk20"] = try diskInfo(["DeviceIdentifier": "disk20", "VirtualOrPhysical": "Physical"])
    runner.outputs["/usr/sbin/diskutil apfs list -plist"] = try diskInfo(["Containers": [[
        "ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk30"]],
        "Volumes": [["APFSVolumeUUID": p.devUUID!.uuidString, "DeviceIdentifier": "disk31s1"]]
    ]]])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": [[
        "image-path": p.imagePath, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
            ["mount-point": p.devMountPoint, "volume-uuid": p.devUUID!.uuidString, "dev-entry": "/dev/disk31s1"]
        ]
    ]]])
    runner.outputs["/bin/df -P \(p.imagePath)"] = .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk20s1 1000 100 900 10% 1 2 1% /Volumes/HE\n")
    let backend = MacStorageBackend(paths: f.paths, runner: runner)
    let observed = try #require(backend.observe())
    if case .failure = p.validate(observed) { Issue.record("fixture chain did not validate") }

    runner.outputs["/bin/df -P \(p.imagePath)"] = .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk20s1 1000 100 900 10% 1 2 1% /Volumes/Other\n")
    #expect(backend.observe() == nil)
    runner.outputs["/bin/df -P \(p.imagePath)"] = .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk20s1 1000 100 900 10% 1 2 1% /Volumes/HE\n")
    runner.outputs["/usr/sbin/diskutil apfs list -plist"] = try diskInfo(["Containers": [[
        "ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk99"]],
        "Volumes": [["APFSVolumeUUID": p.devUUID!.uuidString, "DeviceIdentifier": "disk31s1"]]
    ]]])
    #expect(backend.observe() == nil)
}

@Test func storageBackendRefusesAttachBeforeFreshOuterValidation() throws {
    let f = try Fixture(); defer { f.remove() }
    let mount = f.root.appendingPathComponent("outer", isDirectory: true)
    let dev = mount.appendingPathComponent("DEV", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    let image = mount.appendingPathComponent("DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    let policy = StorageIdentityPolicy(outerUUID: UUID(), devUUID: UUID(), outerMountPoint: mount.path,
                                      devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(mount.path)"] = try diskInfo([
        "VolumeUUID": UUID().uuidString, "MountPoint": mount.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk20s1"
    ])
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)
    let result = backend.attachImage()
    #expect(!result.succeeded)
    #expect(!runner.invocations.contains { $0.0 == "/usr/sbin/diskutil" && $0.1.first == "image" })
}

@Test func storageBackendUsesSharedDescriptorPreflightAndRefusesNonEmptyMountpoint() throws {
    let f = try Fixture(); defer { f.remove() }
    let mount = f.root.appendingPathComponent("outer", isDirectory: true)
    let dev = mount.appendingPathComponent("DEV", isDirectory: true)
    let image = mount.appendingPathComponent("DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    try Data("preserve".utf8).write(to: dev.appendingPathComponent("existing.txt"))
    let outerUUID = UUID()
    let policy = StorageIdentityPolicy(outerUUID: outerUUID, devUUID: UUID(), outerMountPoint: mount.path,
                                      devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(mount.path)"] = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": mount.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk20s1"
    ])
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)
    let result = backend.attachImage()

    #expect(!result.succeeded)
    #expect(result.detail.contains("non-empty"))
    #expect(try Data(contentsOf: dev.appendingPathComponent("existing.txt")) == Data("preserve".utf8))
    #expect(!runner.invocations.contains { $0.0 == "/usr/sbin/diskutil" && $0.1.first == "image" })
}

@Test func serviceSnapshotSeparatesDesiredAutomationFromLoadedAgentAndProgress() throws {
    let f = try Fixture(); defer { f.remove() }
    let provider = FixtureAgentStatusProvider(.loaded)
    let backend = FixtureBackend()
    let service = HESectoriumService(paths: f.paths, backend: backend, store: MemoryStore(), operationLock: MemoryLock(),
        installer: HESectoriumInstaller(paths: f.paths, home: f.home), identityPolicy: .expected,
        agentStatusProvider: provider)
    #expect(service.setAutomationEnabled(true).succeeded)
    let snapshot = service.refreshStatus()
    #expect(snapshot.automationEnabled)
    #expect(snapshot.agentLoadStatus == .loaded)
    #expect(snapshot.operationProgress == .idle)
}

@Test func coreBoundaryRejectsUnexpectedPhysicalOuterBeforeAttach() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend()
    backend.outerObservation = .init(uuid: UUID(), mountPoint: "/Volumes/HE", fileSystem: "ExFAT", writable: true,
                                     name: "HE", rootMatchesExpected: true)
    let service = HESectoriumService(paths: f.paths, backend: backend, store: MemoryStore(), operationLock: MemoryLock(),
        installer: HESectoriumInstaller(paths: f.paths, home: f.home), identityPolicy: .expected)
    #expect(!service.mountDEV().succeeded)
    #expect(backend.attachCount == 0)
}

@Test func occupancyDistinguishesVisibleBusyClearAndIncomplete() throws {
    let f = try Fixture(); defer { f.remove() }
    let outer = f.root.appendingPathComponent("HE", isDirectory: true)
    let dev = outer.appendingPathComponent("DEV", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    let policy = StorageIdentityPolicy(outerUUID: UUID(), devUUID: UUID(), outerMountPoint: outer.path,
                                      devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: outer.appendingPathComponent("image.sparsebundle").path)
    let runner = ScriptedRunner(); let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)
    let key = "/usr/sbin/lsof -nP +f -- \(dev.path)"
    runner.outputs[key] = .init(exitCode: 0, detail: "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nEditor 123 user cwd DIR 1 4096 1 \(dev.path)")
    #expect(backend.assessOccupancy(scope: .dev) == .busy(processIDs: [123]))
    runner.outputs[key] = .init(exitCode: 1)
    #expect(backend.assessOccupancy(scope: .dev) == .noVisibleOccupancy)
    runner.outputs[key] = .init(exitCode: 1, detail: "permission denied")
    #expect(backend.assessOccupancy(scope: .dev) == .incomplete(reason: "lsof exit=1: permission denied"))
    #expect(runner.invocations.allSatisfy { $0.0 == "/usr/sbin/lsof" })
}

@Test func kernelLockAndDurableIntentUseOnlyInjectedFixtureRoot() throws {
    let f = try Fixture(); defer { f.remove() }
    let one = KernelOperationLock(url: f.paths.lock); let two = KernelOperationLock(url: f.paths.lock)
    #expect(one.acquire())
    #expect(!two.acquire())
    one.release()
    #expect(two.acquire())
    two.release()
    let store = JSONStateStore(url: f.paths.state)
    let initial = try store.load()
    #expect(!initial.ejectIntent)
    let pending = StoragePersistentState(revision: initial.revision + 1, ejectIntent: true, operationID: "fixture")
    #expect(try store.compareAndSwap(expectedRevision: initial.revision, newState: pending))
    #expect(try store.load().ejectIntent)
    #expect(!(try store.compareAndSwap(expectedRevision: initial.revision, newState: .init(ejectIntent: false))))
}

@Test func persistentStateRoundTripsReconnectClaimAndReadsLegacyJSON() throws {
    let f = try Fixture(); defer { f.remove() }
    let store = JSONStateStore(url: f.paths.state)
    let initial = try store.load()
    let state = StoragePersistentState(revision: initial.revision + 1, ejectIntent: true,
        operationID: "reconnect-fixture", outerDisappearedAfterIntent: true,
        outerReconnectAttempted: true, workbenchOperation: "start:interrupted",
        workbenchPhase: "mutating", workbenchTarget: "fixture-image",
        workbenchCompletedStep: "attachImage", workbenchTerminalResult: nil)
    #expect(try store.compareAndSwap(expectedRevision: initial.revision, newState: state))
    let reloaded = try JSONStateStore(url: f.paths.state).load()
    #expect(reloaded.outerReconnectAttempted)
    #expect(reloaded.workbenchOperation == state.workbenchOperation)
    #expect(reloaded.workbenchPhase == "mutating")
    #expect(reloaded.workbenchCompletedStep == "attachImage")

    let legacy = #"{"revision":9,"ejectIntent":true,"operationID":"legacy","outerDisappearedAfterIntent":true}"#
    try Data(legacy.utf8).write(to: f.paths.state, options: .atomic)
    let oldState = try JSONStateStore(url: f.paths.state).load()
    #expect(oldState.outerDisappearedAfterIntent)
    #expect(!oldState.outerReconnectAttempted)
    #expect(oldState.workbenchOperation == nil)
}

@Test func symlinkedIdentityRootIsNotAccepted() throws {
    let f = try Fixture(); defer { f.remove() }
    let escaped = f.root.appendingPathComponent("escaped-support", isDirectory: true)
    try FileManager.default.createDirectory(at: escaped, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: f.paths.root, withDestinationURL: escaped)
    try Data(contentsOf: f.assets.identityConfig!).write(to: escaped.appendingPathComponent("storage-identity.json"))
    let service = HESectoriumService(paths: f.paths, backend: FixtureBackend(), store: MemoryStore(), operationLock: MemoryLock(),
                                     installer: HESectoriumInstaller(paths: f.paths, home: f.home))
    #expect(service.refreshStatus().readiness == .notReady("identity configuration missing or invalid"))
    #expect(!service.mountDEV().succeeded)
}

@Test func stateStoreRejectsSymlinkedSupportParentWithoutWritingThrough() throws {
    let f = try Fixture(); defer { f.remove() }
    let outside = f.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    let linked = f.root.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
    let paths = HESectoriumPaths(root: linked.appendingPathComponent("support", isDirectory: true))
    let store = JSONStateStore(url: paths.state)
    #expect(throws: (any Error).self) { _ = try store.load() }
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("support").path))
}

@Test func installerRejectsSymlinkedManagedTargetParentAndRollsBack() throws {
    let f = try Fixture(); defer { f.remove() }
    let outside = f.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: f.home, withIntermediateDirectories: false)
    let local = f.home.appendingPathComponent(".local", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: local, withDestinationURL: outside)
    let result = HESectoriumInstaller(paths: f.paths, home: f.home).apply(f.assets, action: .install)
    #expect(!result.succeeded)
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("bin").path))
    #expect(!FileManager.default.fileExists(atPath: f.paths.root.appendingPathComponent("HESectoriumControl").path))
    #expect(!FileManager.default.fileExists(atPath: f.paths.config.path))
}

@Test func automationDisableDoesNotEjectAndOnlyPhysicalHEReconnectCanMount() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend(); let store = MemoryStore(); let lock = MemoryLock()
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home)
    let service = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: lock,
                                     installer: installer, identityPolicy: .expected)
    #expect(service.setAutomationEnabled(false).succeeded)
    #expect(backend.performed.isEmpty)
    let offEvent = service.runAutomationAgent(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
    #expect(offEvent.steps.first?.step == "automationGate")
    #expect(backend.attachCount == 0)
    #expect(service.setAutomationEnabled(true).succeeded)
    _ = service.runAutomationAgent(.devMounted(uuid: StorageIdentityPolicy.expected.devUUID!))
    _ = service.runAutomationAgent(.imageChanged)
    #expect(backend.attachCount == 0)
    let reconnect = service.runAutomationAgent(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
    #expect(reconnect.succeeded)
    #expect(backend.attachCount == 1)
    #expect(backend.performed.isEmpty)
}

@Test func pendingIntentWithoutDisconnectHistoryRequiresManualRecovery() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend(); let store = MemoryStore()
    let service = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: MemoryLock(),
                                     installer: HESectoriumInstaller(paths: f.paths, home: f.home), identityPolicy: .expected)
    #expect(service.setAutomationEnabled(true).succeeded)
    store.value = .init(revision: 1, ejectIntent: true, operationID: "prior")
    let result = service.runAutomationAgent(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
    #expect(result.failure == .recoveryRequiresManualMount)
    #expect(backend.attachCount == 0)
}
