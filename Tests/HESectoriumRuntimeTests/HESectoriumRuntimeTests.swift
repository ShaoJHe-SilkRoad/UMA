import Foundation
import Testing
import HESectoriumCore
import HESectoriumCLI
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
private final class RefusingPortableWriter: SectoriumPortableDocumentWriting {
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult {
        .pending("fixture withholds portable writes")
    }
}

private func plistText(_ value: Any) throws -> String {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    return String(decoding: data, as: UTF8.self)
}

private func diskInfo(_ values: [String: Any]) throws -> CommandOutcome {
    .init(exitCode: 0, detail: try plistText(values))
}

private func mountedAPFSPreflightFixture(unverifiableDevIdentity: Bool = false) throws
    -> (fixture: Fixture, dev: URL, image: URL, runner: ScriptedRunner, backend: MacStorageBackend) {
    let f = try Fixture()
    let outerUUID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    let devUUID = UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!
    let outer = f.root.appendingPathComponent("HE", isDirectory: true)
    let dev = outer.appendingPathComponent("DEV", isDirectory: true)
    let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    let policy = StorageIdentityPolicy(outerUUID: outerUUID, devUUID: devUUID,
        outerMountPoint: outer.path, devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    let outerInfo = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    var devInfoValues: [String: Any] = [
        "MountPoint": dev.path, "FilesystemType": "APFS", "WritableVolume": true,
        "VolumeName": "DEV_APFS", "DeviceIdentifier": "disk5s1", "APFSContainerReference": "disk5"
    ]
    if !unverifiableDevIdentity { devInfoValues["VolumeUUID"] = devUUID.uuidString }
    let devInfo = try diskInfo(devInfoValues)
    runner.outputs["/usr/sbin/diskutil info -plist \(outer.path)"] = outerInfo
    runner.outputs["/usr/sbin/diskutil info -plist \(dev.path)"] = devInfo
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk5s1"] = devInfo
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk6s1"] = outerInfo
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk6"] = try diskInfo([
        "DeviceIdentifier": "disk6", "ParentWholeDisk": "disk6", "VirtualOrPhysical": "Physical"
    ])
    runner.outputs["/usr/sbin/diskutil apfs list -plist"] = try diskInfo(["Containers": [[
        "ContainerReference": "disk5", "PhysicalStores": [["DeviceIdentifier": "disk99"]],
        "Volumes": [["APFSVolumeUUID": devUUID.uuidString, "DeviceIdentifier": "disk5s1"]]
    ]]])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": [[
        "image-path": image.path, "system-entities": [
            ["dev-entry": "/dev/disk4"], ["dev-entry": "/dev/disk4s1"],
            ["dev-entry": "/dev/disk4s2"], ["dev-entry": "/dev/disk5"],
            ["dev-entry": "/dev/disk5s1", "mount-point": dev.path, "volume-uuid": devUUID.uuidString]
        ]
    ]]])
    runner.outputs["/bin/df -P \(image.path)"] = .init(exitCode: 0,
        detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk6s1 1000 100 900 10% 1 2 1% \(outer.path)\n")
    return (f, dev, image, runner, MacStorageBackend(paths: f.paths, runner: runner, policy: policy))
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
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let mount = source.appendingPathComponent("dev-apfs-mount")
        try Data(contentsOf: repository.appendingPathComponent("Configuration/HESectorium/dev-apfs-mount")).write(to: mount)
        let eject = source.appendingPathComponent("he-eject")
        try Data(contentsOf: repository.appendingPathComponent("Configuration/HESectorium/he-eject")).write(to: eject)
        let agent = source.appendingPathComponent("agent.plist")
        let agentTemplate: [String: Any] = [
            "Label": SectoriumLaunchAgentConfiguration.label,
            "ProgramArguments": ["__UMA_CONTROL_PATH__", "agent"],
            "RunAtLoad": true, "ProcessType": "Background",
            "StandardOutPath": "__UMA_LOG_OUT__", "StandardErrorPath": "__UMA_LOG_ERR__"
        ]
        try PropertyListSerialization.data(fromPropertyList: agentTemplate, format: .xml, options: 0).write(to: agent)
        let config = source.appendingPathComponent("identity.json")
        let identity = """
        {"outerUUID":"\(StorageIdentityPolicy.expected.outerUUID.uuidString)","devUUID":"\(StorageIdentityPolicy.expected.devUUID!.uuidString)","outerMountPoint":"/Volumes/HE","devMountPoint":"/Volumes/HE/DEV","devVolumeName":"DEV_APFS","imagePath":"/Volumes/HE/.DEV-APFS.sparsebundle"}
        """
        try Data(identity.utf8).write(to: config)
        assets = .init(control: control, devMountWrapper: mount, ejectWrapper: eject, launchAgent: agent, identityConfig: config)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func dispatcherReportUsesRealOperationResultAndPreservesJSONAndExitStatus() throws {
    let failed = OperationResult(operationID: "fixture-failed", mode: .manual,
        steps: [.init(step: "attach", status: .failed, detail: "synthetic fixture failure")],
        failure: .attachFailed(1, "synthetic fixture failure"))
    var failedOut: [String] = []; var failedErr: [String] = []
    let failedExit = HESectoriumCommandDispatcher.report(failed,
        writeStdout: { failedOut.append($0) }, writeStderr: { failedErr.append($0) })
    #expect(failedExit == 1)
    #expect(failedOut.count == 1)
    let failedJSON = try #require(JSONSerialization.jsonObject(with: Data(failedOut[0].utf8)) as? [String: Any])
    #expect(failedJSON["succeeded"] as? Bool == false)
    #expect(failedErr == ["Sectorium: operation did not complete. Keep the drive connected, refresh its identity, and review the operation details before retrying.\n"])

    let succeeded = OperationResult(operationID: "fixture-succeeded", mode: .manual,
        steps: [.init(step: "attach", status: .succeeded)])
    var succeededOut: [String] = []; var succeededErr: [String] = []
    let succeededExit = HESectoriumCommandDispatcher.report(succeeded,
        writeStdout: { succeededOut.append($0) }, writeStderr: { succeededErr.append($0) })
    #expect(succeededExit == 0)
    #expect(succeededOut.count == 1)
    let succeededJSON = try #require(JSONSerialization.jsonObject(with: Data(succeededOut[0].utf8)) as? [String: Any])
    #expect(succeededJSON["succeeded"] as? Bool == true)
    #expect(succeededErr.isEmpty)
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

@Test func loadedAgentRequiresExactLabelProgramAndArguments() {
    let label = SectoriumLaunchAgentConfiguration.label
    let control = "/private/tmp/agent-fixture/HESectoriumControl"
    let expected: [String: Any] = ["Label": label, "ProgramArguments": [control, "agent"]]
    #expect(SystemAgentStatusProvider.classify(job: expected, label: label,
        expectedControlPath: control) == .loaded)
    var wrongLabel = expected; wrongLabel["Label"] = "com.example.other-agent"
    var wrongProgram = expected; wrongProgram["ProgramArguments"] = ["/bin/sh", "agent"]
    var wrongArguments = expected; wrongArguments["ProgramArguments"] = [control, "eject"]
    var extraArgument = expected; extraArgument["ProgramArguments"] = [control, "agent", "unexpected"]
    var conflictingProgram = expected; conflictingProgram["Program"] = "/bin/sh"
    var noArguments = expected; noArguments.removeValue(forKey: "ProgramArguments")
    for job in [wrongLabel, wrongProgram, wrongArguments, extraArgument, conflictingProgram, noArguments] {
        #expect(SystemAgentStatusProvider.classify(job: job, label: label,
            expectedControlPath: control) == .unknown)
    }
    #expect(SystemAgentStatusProvider.classify(job: expected, label: "com.example.other-agent",
        expectedControlPath: control) == .unknown)
}

@Test func installedAgentRequiresExactStructuredPlist() throws {
    let f = try Fixture(); defer { f.remove() }
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home)
    #expect(installer.apply(f.assets, action: .install).succeeded)
    #expect(installer.status() == .installed)
    let target = f.home.appendingPathComponent("Library/LaunchAgents/com.juliushe.dev-apfs-mounter.plist")
    let original = try Data(contentsOf: target)
    let valid = try #require(PropertyListSerialization.propertyList(from: original, options: [], format: nil) as? [String: Any])
    var wrongLabel = valid; wrongLabel["Label"] = "com.example.other-agent"
    var wrongProgram = valid; wrongProgram["ProgramArguments"] = ["/bin/sh", "agent"]
    var wrongArguments = valid; wrongArguments["ProgramArguments"] = [f.paths.root.appendingPathComponent("HESectoriumControl").path, "eject"]
    var conflictingProgram = valid; conflictingProgram["Program"] = "/bin/sh"
    var wrongRunAtLoad = valid; wrongRunAtLoad["RunAtLoad"] = false
    var decoy = wrongProgram; decoy["Comment"] = f.paths.root.appendingPathComponent("HESectoriumControl").path
    for job in [wrongLabel, wrongProgram, wrongArguments, conflictingProgram, wrongRunAtLoad, decoy] {
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
            .write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        #expect(installer.status() == .conflict("LaunchAgent is not bound to the shared controller"))
    }
    try original.write(to: target, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    #expect(installer.status() == .installed)
}

@Test func maliciousAgentAssetIsRejectedBeforeAnyInstallWrite() throws {
    let f = try Fixture(); defer { f.remove() }
    let source = f.root.appendingPathComponent("malicious-agent.plist")
    let template = try #require(PropertyListSerialization.propertyList(
        from: Data(contentsOf: f.assets.launchAgent), options: [], format: nil) as? [String: Any])
    var malicious = template
    malicious["ProgramArguments"] = ["/bin/sh", "-c", "exit 0"]
    malicious["Comment"] = "__UMA_CONTROL_PATH__"
    try PropertyListSerialization.data(fromPropertyList: malicious, format: .xml, options: 0).write(to: source)
    let assets = HESectoriumAssets(control: f.assets.control, devMountWrapper: f.assets.devMountWrapper,
        ejectWrapper: f.assets.ejectWrapper, launchAgent: source, identityConfig: f.assets.identityConfig)

    let result = HESectoriumInstaller(paths: f.paths, home: f.home).apply(assets, action: .install)

    #expect(!result.succeeded)
    #expect(!FileManager.default.fileExists(atPath: f.paths.root.appendingPathComponent("HESectoriumControl").path))
    #expect(!FileManager.default.fileExists(atPath:
        f.home.appendingPathComponent("Library/LaunchAgents/com.juliushe.dev-apfs-mounter.plist").path))
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

@Test func registeredProfileInstallerDoesNotRequireLegacyIdentityFile() throws {
    let f = try Fixture(); defer { f.remove() }
    let installer = HESectoriumInstaller(paths: f.paths, home: f.home)
    let profileAssets = HESectoriumAssets(control: f.assets.control,
        devMountWrapper: f.assets.devMountWrapper, ejectWrapper: f.assets.ejectWrapper,
        launchAgent: f.assets.launchAgent, identityConfig: nil)

    let installed = installer.apply(profileAssets, action: .install, profileConfigured: true)

    #expect(installed.succeeded, "\(installed.summary)")
    #expect(installer.status(profileConfigured: true) == .installed)
    #expect(installer.status() == .missing)
    #expect(!FileManager.default.fileExists(atPath: f.paths.config.path))
    #expect(installed.fileOutcomes.allSatisfy { $0.file != "identityConfig" })
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
                                     installer: HESectoriumInstaller(paths: f.paths, home: f.home),
                                     runner: ScriptedRunner(), portableDocumentWriter: RefusingPortableWriter())
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
        operationLock: lock, installer: HESectoriumInstaller(paths: f.paths, home: f.home),
        runner: runner, identityPolicy: .expected, portableDocumentWriter: RefusingPortableWriter())

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
    let invalid = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: lock,
        installer: installer, runner: ScriptedRunner(), portableDocumentWriter: RefusingPortableWriter())
    #expect(invalid.refreshStatus().readiness == .notReady("identity configuration missing or invalid"))
    #expect(invalid.runAutomationAgentAtStartup().steps.first?.step == "automationGate")
    #expect(backend.attachCount == 0)

    try Data(contentsOf: f.assets.identityConfig!).write(to: f.paths.config)
    let valid = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: lock,
        installer: installer, runner: ScriptedRunner(), portableDocumentWriter: RefusingPortableWriter())
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

@Test(arguments: ["/Volumes/HE", "/Volumes/HE Work", "/Volumes/HE  Work"])
func imageBackingAndDevAPFSChainMustMatchReadOnlyCommandOutput(outerMount: String) throws {
    let f = try Fixture(); defer { f.remove() }
    let p = StorageIdentityPolicy(outerUUID: StorageIdentityPolicy.expected.outerUUID,
        devUUID: StorageIdentityPolicy.expected.devUUID, outerMountPoint: outerMount,
        devMountPoint: outerMount + "/DEV", devVolumeName: "DEV_APFS",
        imagePath: outerMount + "/.DEV-APFS.sparsebundle")
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(p.outerMountPoint)"] = try diskInfo([
        "VolumeUUID": p.outerUUID.uuidString, "MountPoint": p.outerMountPoint, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk20s1", "PartOfWhole": "disk20"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist \(p.devMountPoint)"] = try diskInfo([
        "VolumeUUID": p.devUUID!.uuidString, "MountPoint": p.devMountPoint, "FilesystemType": "APFS",
        "WritableVolume": true, "VolumeName": p.devVolumeName, "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk31s1"] = runner.outputs["/usr/sbin/diskutil info -plist \(p.devMountPoint)"]!
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk20s1"] = runner.outputs["/usr/sbin/diskutil info -plist \(p.outerMountPoint)"]!
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
    runner.outputs["/bin/df -P \(p.imagePath)"] = .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk20s1 1000 100 900 10% 1 2 1% \(p.outerMountPoint)\n")
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: p)
    let observed = try #require(backend.observe())
    if case .failure = p.validate(observed) { Issue.record("fixture chain did not validate") }

    runner.outputs["/bin/df -P \(p.imagePath)"] = .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk20s1 1000 100 900 10% 1 2 1% /Volumes/Other\n")
    #expect(backend.observe() == nil)
    runner.outputs["/bin/df -P \(p.imagePath)"] = .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk20s1 1000 100 900 10% 1 2 1% \(p.outerMountPoint)\n")
    runner.outputs["/usr/sbin/diskutil apfs list -plist"] = try diskInfo(["Containers": [[
        "ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk99"]],
        "Volumes": [["APFSVolumeUUID": p.devUUID!.uuidString, "DeviceIdentifier": "disk31s1"]]
    ]]])
    #expect(backend.observe() == nil)
}

@Test func capturedMountedHEDEVAPFSChainIsIdempotentWithoutProbingOccupiedMountpoint() throws {
    let f = try Fixture(); defer { f.remove() }
    // Sanitized structural fixture: synthetic UUIDs retain the observed parent/volume relationships;
    // this is not an exact replay of native host identifiers or plists.
    let outerUUID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    let devUUID = UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!
    let outer = f.root.appendingPathComponent("HE", isDirectory: true)
    let dev = outer.appendingPathComponent("DEV", isDirectory: true)
    let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    // The marker proves the already-mounted path returns on verified identity before
    // the detached-mountpoint metadata-only empty-directory safety check.
    try Data("preserve".utf8).write(to: dev.appendingPathComponent("existing.txt"))
    let policy = StorageIdentityPolicy(outerUUID: outerUUID, devUUID: devUUID,
        outerMountPoint: outer.path, devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(outer.path)"] = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    let devInfo = try diskInfo([
        "VolumeUUID": devUUID.uuidString, "MountPoint": dev.path, "FilesystemType": "APFS",
        "WritableVolume": true, "VolumeName": "DEV_APFS", "DeviceIdentifier": "disk5s1",
        "APFSContainerReference": "disk5"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist \(dev.path)"] = devInfo
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk5s1"] = devInfo
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk6s1"] = runner.outputs["/usr/sbin/diskutil info -plist \(outer.path)"]
    runner.outputs["/usr/sbin/diskutil info -plist /dev/disk6"] = try diskInfo([
        "DeviceIdentifier": "disk6", "ParentWholeDisk": "disk6", "VirtualOrPhysical": "Physical"
    ])
    runner.outputs["/usr/sbin/diskutil apfs list -plist"] = try diskInfo(["Containers": [[
        "ContainerReference": "disk5", "PhysicalStores": [["DeviceIdentifier": "disk4s2"]],
        "Volumes": [["APFSVolumeUUID": devUUID.uuidString, "DeviceIdentifier": "disk5s1"]]
    ]]])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": [[
        "image-path": image.path, "system-entities": [
            ["dev-entry": "/dev/disk4"], ["dev-entry": "/dev/disk4s1"],
            ["dev-entry": "/dev/disk4s2"], ["dev-entry": "/dev/disk5"],
            ["dev-entry": "/dev/disk5s1", "mount-point": dev.path, "volume-uuid": devUUID.uuidString]
        ]
    ]]])
    runner.outputs["/bin/df -P \(image.path)"] = .init(exitCode: 0,
        detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk6s1 1000 100 900 10% 1 2 1% \(outer.path)\n")

    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)
    let result = backend.attachImage()

    #expect(result.succeeded)
    #expect(!runner.invocations.contains { ($0.0 == "/usr/sbin/diskutil" && $0.1.first == "image")
        || ($0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach") })
    #expect(try Data(contentsOf: dev.appendingPathComponent("existing.txt")) == Data("preserve".utf8))

    runner.outputs["/usr/sbin/diskutil apfs list -plist"] = try diskInfo(["Containers": [[
        "ContainerReference": "disk5", "PhysicalStores": [["DeviceIdentifier": "disk99"]],
        "Volumes": [["APFSVolumeUUID": devUUID.uuidString, "DeviceIdentifier": "disk5s1"]]
    ]]])
    let contradicted = backend.attachImage()
    #expect(!contradicted.succeeded)
    #expect(contradicted.detail.contains("already mounted"))
    #expect(!runner.invocations.contains { ($0.0 == "/usr/sbin/diskutil" && $0.1.first == "image")
        || ($0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach") })
}

@Test func mountedMismatchedAPFSChainWithEmptyDEVRootRefusesBeforeAttach() throws {
    let fixture = try mountedAPFSPreflightFixture()
    defer { fixture.fixture.remove() }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.dev.path).isEmpty)

    let result = fixture.backend.attachImage()

    #expect(!result.succeeded)
    #expect(result.detail.contains("already mounted"))
    #expect(!fixture.runner.invocations.contains {
        ($0.0 == "/usr/sbin/diskutil" && $0.1.first == "image")
            || ($0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach")
    })
}

@Test func mountedDEVTargetWithUnverifiableIdentityRefusesBeforeAttach() throws {
    let fixture = try mountedAPFSPreflightFixture(unverifiableDevIdentity: true)
    defer { fixture.fixture.remove() }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.dev.path).isEmpty)

    let result = fixture.backend.attachImage()

    #expect(!result.succeeded)
    #expect(result.detail.contains("Could not verify that the DEV target"))
    #expect(!fixture.runner.invocations.contains {
        ($0.0 == "/usr/sbin/diskutil" && $0.1.first == "image")
            || ($0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach")
    })
}

@Test func detachedEmptyDEVMountpointStillAttachesConfiguredImage() throws {
    let f = try Fixture(); defer { f.remove() }
    let outer = f.root.appendingPathComponent("HE", isDirectory: true)
    let dev = outer.appendingPathComponent("DEV", isDirectory: true)
    let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    let outerUUID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    let policy = StorageIdentityPolicy(outerUUID: outerUUID,
        devUUID: UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!,
        outerMountPoint: outer.path, devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(outer.path)"] = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist \(dev.path)"] = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": []])
    let attach = "/usr/bin/hdiutil attach -nobrowse -mountpoint \(dev.path) \(image.path)"
    runner.outputs[attach] = .init(exitCode: 0)
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)

    let result = backend.attachImage()

    #expect(result.succeeded)
    #expect(runner.invocations.filter { $0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach" }.count == 1)
}

@Test func absentOrMalformedDEVObservationRefusesBeforeAttach() throws {
    let f = try Fixture(); defer { f.remove() }
    let outer = f.root.appendingPathComponent("HE", isDirectory: true)
    let dev = outer.appendingPathComponent("DEV", isDirectory: true)
    let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    let outerUUID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    let policy = StorageIdentityPolicy(outerUUID: outerUUID,
        devUUID: UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!,
        outerMountPoint: outer.path, devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(outer.path)"] = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": []])
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)
    let devKey = "/usr/sbin/diskutil info -plist \(dev.path)"
    for observation in [
        CommandOutcome(exitCode: 1, detail: "fixture identity observation unavailable"),
        CommandOutcome(exitCode: 0, detail: "fixture identity observation malformed")
    ] {
        runner.outputs[devKey] = observation
        let result = backend.attachImage()
        #expect(!result.succeeded)
        #expect(result.detail.contains("Could not verify that the DEV target"))
    }
    #expect(!runner.invocations.contains {
        ($0.0 == "/usr/sbin/diskutil" && $0.1.first == "image")
            || ($0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach")
    })
}

@Test func unavailableMountpointMetadataHasDistinctSafeGuidanceBeforeAttach() throws {
    let f = try Fixture(); defer { f.remove() }
    let outer = f.root.appendingPathComponent("HE", isDirectory: true)
    try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
    let dev = outer.appendingPathComponent("DEV")
    try Data("fixture file blocks directory metadata open".utf8).write(to: dev)
    let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
    try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
    let policy = StorageIdentityPolicy(outerUUID: UUID(), devUUID: nil, outerMountPoint: outer.path,
        devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
    let runner = ScriptedRunner()
    runner.outputs["/usr/sbin/diskutil info -plist \(outer.path)"] = try diskInfo([
        "VolumeUUID": policy.outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    runner.outputs["/usr/sbin/diskutil info -plist \(dev.path)"] = try diskInfo([
        "VolumeUUID": policy.outerUUID.uuidString, "MountPoint": outer.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6"
    ])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": []])
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)

    let result = backend.attachImage()

    #expect(!result.succeeded)
    #expect(result.detail.contains("open the mount directory"))
    #expect(result.detail.contains("Not a directory"))
    #expect(result.detail.contains("No Load command was run"))
    #expect(try Data(contentsOf: dev) == Data("fixture file blocks directory metadata open".utf8))
    #expect(!runner.invocations.contains { ($0.0 == "/usr/sbin/diskutil" && $0.1.first == "image")
        || ($0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach") })
}

@Test func sourceCompatibilityWrapperKeepsMachineJSONAndAddsOneHumanFailureLine() throws {
    let f = try Fixture(); defer { f.remove() }
    let wrapper = f.assets.devMountWrapper
    let control = f.root.appendingPathComponent("fixture-control", isDirectory: false)
    try Data("#!/bin/sh\nprintf '%s\\n' '{\"succeeded\":false}'\nprintf '%s\\n' 'Sectorium: operation did not complete. Keep the drive connected, refresh its identity, and review the operation details before retrying.' >&2\nexit 1\n".utf8).write(to: control)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: control.path)
    let template = try String(contentsOf: wrapper, encoding: .utf8)
    try Data(template.replacingOccurrences(of: "__UMA_CONTROL_PATH__", with: control.path).utf8).write(to: wrapper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)

    let process = Process()
    let stdout = Pipe(), stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [wrapper.path]
    process.currentDirectoryURL = f.root
    process.standardOutput = stdout; process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 1)
    #expect(output == "{\"succeeded\":false}\n")
    #expect(error.components(separatedBy: "Sectorium: operation did not complete.").count == 2)
    #expect(!error.contains("attachFailed"))
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

@Test func storageBackendPreservesNonemptyMountpointAndReturnsNativeFailure() throws {
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
    runner.outputs["/usr/sbin/diskutil info -plist \(dev.path)"] = try diskInfo([
        "VolumeUUID": outerUUID.uuidString, "MountPoint": mount.path, "FilesystemType": "ExFAT",
        "WritableVolume": true, "VolumeName": "HE", "DeviceIdentifier": "disk20s1"
    ])
    runner.outputs["/usr/bin/hdiutil info -plist"] = try diskInfo(["images": []])
    runner.outputs["/usr/sbin/diskutil image attach --help"] = .init(exitCode: 0, detail: "diskutil image attach")
    let nativeKey = "/usr/sbin/diskutil image attach --nobrowse --mountPoint \(dev.path) \(image.path)"
    runner.outputs[nativeKey] = .init(exitCode: 1, detail: "Native mount cancelled by user")
    let backend = MacStorageBackend(paths: f.paths, runner: runner, policy: policy)
    let result = backend.attachImage()

    #expect(!result.succeeded)
    #expect(result.exitCode == 1)
    #expect(result.detail == "Native mount cancelled by user")
    #expect(try Data(contentsOf: dev.appendingPathComponent("existing.txt")) == Data("preserve".utf8))
    #expect(runner.invocations.filter { $0.0 == "/usr/sbin/diskutil" && $0.1 == ["image", "attach", "--nobrowse", "--mountPoint", dev.path, image.path] }.count == 1)
    #expect(!runner.invocations.contains { $0.0 == "/usr/bin/hdiutil" && $0.1.first == "attach" })
}

@Test func serviceSnapshotSeparatesDesiredAutomationFromLoadedAgentAndProgress() throws {
    let f = try Fixture(); defer { f.remove() }
    let provider = FixtureAgentStatusProvider(.loaded)
    let backend = FixtureBackend()
    let service = HESectoriumService(paths: f.paths, backend: backend, store: MemoryStore(), operationLock: MemoryLock(),
        installer: HESectoriumInstaller(paths: f.paths, home: f.home), runner: ScriptedRunner(),
        identityPolicy: .expected, agentStatusProvider: provider,
        portableDocumentWriter: RefusingPortableWriter())
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
        installer: HESectoriumInstaller(paths: f.paths, home: f.home), runner: ScriptedRunner(),
        identityPolicy: .expected, portableDocumentWriter: RefusingPortableWriter())
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
    let key = "/usr/sbin/lsof -nP -Fpcf +f -- \(dev.path)"
    runner.outputs[key] = .init(exitCode: 0, detail: "p123\ncEditor\nfcwd\n")
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
        outerReconnectAttempted: true,
        suppressedProfileIDs: ["manual-profile"], disconnectedProfileIDs: ["disconnected-profile"],
        reconnectAttemptedProfileIDs: ["attempted-profile"],
        terminalEjectJournals: ["physical-A": "encoded-terminal-journal"],
        workbenchOperation: "start:interrupted",
        workbenchPhase: "mutating", workbenchTarget: "fixture-image",
        workbenchCompletedStep: "attachImage", workbenchTerminalResult: nil)
    #expect(try store.compareAndSwap(expectedRevision: initial.revision, newState: state))
    let reloaded = try JSONStateStore(url: f.paths.state).load()
    #expect(reloaded.outerReconnectAttempted)
    #expect(reloaded.suppressedProfileIDs == ["manual-profile"])
    #expect(reloaded.disconnectedProfileIDs == ["disconnected-profile"])
    #expect(reloaded.reconnectAttemptedProfileIDs == ["attempted-profile"])
    #expect(reloaded.terminalEjectJournals == ["physical-A": "encoded-terminal-journal"])
    #expect(reloaded.workbenchOperation == state.workbenchOperation)
    #expect(reloaded.workbenchPhase == "mutating")
    #expect(reloaded.workbenchCompletedStep == "attachImage")

    let legacy = #"{"revision":9,"ejectIntent":true,"operationID":"legacy","outerDisappearedAfterIntent":true}"#
    try Data(legacy.utf8).write(to: f.paths.state, options: .atomic)
    let oldState = try JSONStateStore(url: f.paths.state).load()
    #expect(oldState.outerDisappearedAfterIntent)
    #expect(!oldState.outerReconnectAttempted)
    #expect(oldState.suppressedProfileIDs.isEmpty)
    #expect(oldState.disconnectedProfileIDs.isEmpty)
    #expect(oldState.reconnectAttemptedProfileIDs.isEmpty)
    #expect(oldState.terminalEjectJournals.isEmpty)
    #expect(oldState.workbenchOperation == nil)
}

@Test func symlinkedIdentityRootIsNotAccepted() throws {
    let f = try Fixture(); defer { f.remove() }
    let escaped = f.root.appendingPathComponent("escaped-support", isDirectory: true)
    try FileManager.default.createDirectory(at: escaped, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: f.paths.root, withDestinationURL: escaped)
    try Data(contentsOf: f.assets.identityConfig!).write(to: escaped.appendingPathComponent("storage-identity.json"))
    let service = HESectoriumService(paths: f.paths, backend: FixtureBackend(), store: MemoryStore(), operationLock: MemoryLock(),
                                     installer: HESectoriumInstaller(paths: f.paths, home: f.home),
                                     runner: ScriptedRunner(), portableDocumentWriter: RefusingPortableWriter())
    #expect(!service.identityConfigurationReady)
    #expect(service.refreshStatus().readiness == .notReady("registered profile configuration unavailable or invalid"))
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
                                     installer: installer, runner: ScriptedRunner(), identityPolicy: .expected,
                                     portableDocumentWriter: RefusingPortableWriter())
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
    #expect(reconnect.steps.contains { $0.step == "reuseVerifiedImage" && $0.status == .succeeded })
    #expect(backend.attachCount == 0)
    #expect(backend.performed.isEmpty)
}

@Test func pendingIntentWithoutDisconnectHistoryRequiresManualRecovery() throws {
    let f = try Fixture(); defer { f.remove() }
    let backend = FixtureBackend(); let store = MemoryStore()
    let service = HESectoriumService(paths: f.paths, backend: backend, store: store, operationLock: MemoryLock(),
                                     installer: HESectoriumInstaller(paths: f.paths, home: f.home),
                                     runner: ScriptedRunner(), identityPolicy: .expected,
                                     portableDocumentWriter: RefusingPortableWriter())
    #expect(service.setAutomationEnabled(true).succeeded)
    store.value = .init(revision: 1, ejectIntent: true, operationID: "prior")
    let result = service.runAutomationAgent(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
    #expect(result.failure == .recoveryRequiresManualMount)
    #expect(backend.attachCount == 0)
}
