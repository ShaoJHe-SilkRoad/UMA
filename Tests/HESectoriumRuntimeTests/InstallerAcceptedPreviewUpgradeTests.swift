import CryptoKit
import Foundation
import Testing
@testable import HESectoriumRuntime

@Suite struct InstallerAcceptedPreviewUpgradeTests {
    private static let acceptedHash = "3266c4dd532a3106d66a18d7a94ac7808d8afdcca2093a2ec29dde79e34810c7"
    private static let artifactVariable = "AUV_TEST_LEGACY_CONTROL_FIXTURE"

    @Test func acceptedPreviewHashIsRestrictedToControl() {
        #expect(HESectoriumInstaller.isAcceptedPreviousControl(hash: Self.acceptedHash, targetKey: "control"))
        for target in ["devMount", "eject", "launchAgent", "identityConfig", "unrelated"] {
            #expect(!HESectoriumInstaller.isAcceptedPreviousControl(hash: Self.acceptedHash, targetKey: target))
        }
        #expect(!HESectoriumInstaller.isAcceptedPreviousControl(hash: String(repeating: "0", count: 64), targetKey: "control"))
    }

    // The historical executable is an external build artifact, never executed by
    // these tests. Supply its path explicitly to exercise its exact bytes without
    // checking a binary or a developer's private path into the source repository.
    @Test(.enabled(if: ProcessInfo.processInfo.environment[artifactVariable] != nil))
    func acceptedPreviewUpgradeRetainsDurableRecoveryAndUserState() throws {
        let original = try Self.legacyBytes()
        let fixture = try UpgradeFixture(control: original)
        defer { fixture.remove() }
        let beforeRecovery = try fixture.recoveryDirectories()
        let oldAgent = try Data(contentsOf: fixture.agent)
        let oldMount = try Data(contentsOf: fixture.mountWrapper)
        let oldEject = try Data(contentsOf: fixture.ejectWrapper)
        let sentinel = Data("retained user configuration".utf8)
        let retained = [fixture.paths.config, fixture.paths.root.appendingPathComponent("sectorium-profiles.json"),
                        fixture.paths.root.appendingPathComponent("state.json"),
                        fixture.paths.root.appendingPathComponent("automation.json")]
        for url in retained { try sentinel.write(to: url) }
        let replacement = Data("new control fixture; not executable behavior".utf8)
        try replacement.write(to: fixture.assets.control)

        let result = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
            .apply(fixture.assets, action: .repair, profileConfigured: true)

        #expect(result.succeeded, "\(result.summary)")
        #expect(result.changedPaths == [fixture.control.path])
        #expect(try Data(contentsOf: fixture.control) == replacement)
        #expect(try fixture.mode(fixture.control) == 0o700)
        #expect(try Data(contentsOf: fixture.agent) == oldAgent)
        #expect(try Data(contentsOf: fixture.mountWrapper) == oldMount)
        #expect(try Data(contentsOf: fixture.ejectWrapper) == oldEject)
        for url in retained { #expect(try Data(contentsOf: url) == sentinel) }

        let newRecovery = try fixture.recoveryDirectories().subtracting(beforeRecovery)
        #expect(newRecovery.count == 1)
        let directory = try #require(newRecovery.first)
        let backup = directory.appendingPathComponent("control.preimage")
        #expect(try Data(contentsOf: backup) == original)
        #expect(try fixture.mode(backup) == 0o600)
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            directory.appendingPathComponent("manifest.json"))) as? [String: Any])
        let records = try #require(manifest["records"] as? [[String: Any]])
        let controlRecord = try #require(records.first { $0["key"] as? String == "control" })
        #expect(controlRecord["sha256"] as? String == Self.acceptedHash)
        #expect(controlRecord["mode"] as? Int == 0o700)

        let freshInstaller = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
        let recovered = freshInstaller.recoverInterruptedInstall(transactionID: directory.lastPathComponent)
        #expect(recovered.succeeded, "\(recovered.summary)")
        #expect(try Data(contentsOf: fixture.control) == original)
        #expect(try fixture.mode(fixture.control) == 0o700)
        for url in retained { #expect(try Data(contentsOf: url) == sentinel) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment[artifactVariable] != nil))
    func alteredPreviewIsRefusedBeforeAnyReplacement() throws {
        var altered = try Self.legacyBytes()
        altered[0] ^= 1
        try verifyRefusedUpgrade(original: altered)
    }

    @Test func unknownControlIsRefusedBeforeAnyReplacement() throws {
        try verifyRefusedUpgrade(original: Data("unknown user control".utf8))
    }

    @Test func managedControlUpgradesAcrossVersionsAndRetainsRecoverablePreimages() throws {
        let first = Data("managed control v1".utf8)
        let fixture = try UpgradeFixture(control: first, recordedAsManaged: true)
        defer { fixture.remove() }
        let retained = fixture.paths.root.appendingPathComponent("state.json")
        let sentinel = Data("preserved operation state".utf8)
        try sentinel.write(to: retained)
        var previous = first
        for version in 2...3 {
            let before = try fixture.recoveryDirectories()
            let replacement = Data("managed control v\(version)".utf8)
            try replacement.write(to: fixture.assets.control)
            let installed = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
                .apply(fixture.assets, action: .repair, profileConfigured: true)
            #expect(installed.succeeded, "\(installed.summary)")
            #expect(installed.changedPaths == [fixture.control.path])
            #expect(try Data(contentsOf: fixture.control) == replacement)
            let directory = try #require(fixture.recoveryDirectories().subtracting(before).first)
            #expect(try Data(contentsOf: directory.appendingPathComponent("control.preimage")) == previous)
            if version == 3 {
                let recovery = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
                    .recoverInterruptedInstall(transactionID: directory.lastPathComponent)
                #expect(recovery.succeeded, "\(recovery.summary)")
                #expect(try Data(contentsOf: fixture.control) == previous)
            }
            previous = replacement
        }
        #expect(try Data(contentsOf: retained) == sentinel)
    }

    @Test func alteredManagedControlIsNotAuthorizedByItsOldReceipt() throws {
        let fixture = try UpgradeFixture(control: Data("managed original".utf8), recordedAsManaged: true)
        defer { fixture.remove() }
        let altered = Data("altered installed control".utf8)
        try altered.write(to: fixture.control)
        try assertRejected(fixture, preserved: altered)
    }

    @Test(arguments: ["wrong-path", "wrong-key", "duplicate-key", "unknown-target", "wrong-schema",
                      "wrong-transaction", "wrong-digest", "missing-receipt", "manifest-symlink",
                      "directory-symlink", "manifest-mode", "control-mode"])
    func invalidManagedReceiptCannotAuthorizeReplacement(_ defect: String) throws {
        let original = Data("managed original".utf8)
        let fixture = try UpgradeFixture(control: original, recordedAsManaged: true)
        defer { fixture.remove() }
        let directory = try #require(fixture.recoveryDirectories().first)
        let receipt = directory.appendingPathComponent("manifest.json")
        if defect == "missing-receipt" {
            try FileManager.default.removeItem(at: receipt)
        } else if defect == "manifest-symlink" || defect == "directory-symlink" {
            let originalURL = defect == "manifest-symlink" ? receipt : directory
            let retainedURL = fixture.root.appendingPathComponent("linked-receipt-source")
            try FileManager.default.moveItem(at: originalURL, to: retainedURL)
            try FileManager.default.createSymbolicLink(at: originalURL, withDestinationURL: retainedURL)
        } else if defect == "manifest-mode" || defect == "control-mode" {
            try FileManager.default.setAttributes([.posixPermissions: 0o644],
                ofItemAtPath: defect == "manifest-mode" ? receipt.path : fixture.control.path)
        } else {
            var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any])
            var records = try #require(manifest["records"] as? [[String: Any]])
            let index = try #require(records.firstIndex { $0["key"] as? String == "control" })
            switch defect {
            case "wrong-path": records[index]["targetPath"] = fixture.root.appendingPathComponent("other-control").path
            case "wrong-key": records[index]["key"] = "eject"
            case "duplicate-key": records.append(records[index])
            case "unknown-target": records.append(["key": "unrelated", "targetPath": "/unrelated", "existed": false,
                                                    "postimageSHA256": String(repeating: "0", count: 64)])
            case "wrong-schema": manifest["schema"] = 99
            case "wrong-transaction": manifest["transactionID"] = UUID().uuidString
            case "wrong-digest": records[index]["postimageSHA256"] = String(repeating: "0", count: 64)
            default: Issue.record("Unrecognized fixture defect")
            }
            manifest["records"] = records
            try JSONSerialization.data(withJSONObject: manifest).write(to: receipt)
        }
        try assertRejected(fixture, preserved: original)
    }

    @Test(arguments: [false, true])
    func managedUpgradeRequiresRetainedValidControlPreimage(_ symbolicLink: Bool) throws {
        let fixture = try UpgradeFixture(control: Data("older managed control".utf8), recordedAsManaged: true)
        defer { fixture.remove() }
        let current = Data("current managed control".utf8)
        let before = try fixture.recoveryDirectories()
        try current.write(to: fixture.assets.control)
        let result = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
            .apply(fixture.assets, action: .repair, profileConfigured: true)
        try #require(result.succeeded)
        let receipt = try #require(fixture.recoveryDirectories().subtracting(before).first)
        let backup = receipt.appendingPathComponent("control.preimage")
        if symbolicLink {
            let moved = fixture.root.appendingPathComponent("linked-backup")
            try FileManager.default.moveItem(at: backup, to: moved)
            try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: moved)
        } else {
            try Data("corrupt preimage".utf8).write(to: backup)
        }
        try assertRejected(fixture, preserved: current)
    }

    @Test func managedControlReceiptDoesNotAuthorizeAnotherComponent() throws {
        let original = Data("managed control bytes".utf8)
        let fixture = try UpgradeFixture(control: original, recordedAsManaged: true)
        defer { fixture.remove() }
        try original.write(to: fixture.mountWrapper)
        let result = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
            .apply(fixture.assets, action: .repair, profileConfigured: true)
        #expect(!result.succeeded)
        #expect(result.summary.contains("not a recognized legacy component: devMount"))
        #expect(try Data(contentsOf: fixture.mountWrapper) == original)
    }

    private func assertRejected(_ fixture: UpgradeFixture, preserved original: Data) throws {
        let before = try fixture.recoveryDirectories()
        try Data("new replacement control".utf8).write(to: fixture.assets.control)
        let result = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
            .apply(fixture.assets, action: .repair, profileConfigured: true)
        #expect(!result.succeeded)
        #expect(result.summary.contains("not a recognized legacy component: control"))
        #expect(result.changedPaths.isEmpty)
        #expect(try Data(contentsOf: fixture.control) == original)
        #expect(try fixture.recoveryDirectories() == before)
    }

    private func verifyRefusedUpgrade(original: Data) throws {
        let fixture = try UpgradeFixture(control: original)
        defer { fixture.remove() }
        let beforeRecovery = try fixture.recoveryDirectories()
        let agent = try Data(contentsOf: fixture.agent)
        try Data("replacement control".utf8).write(to: fixture.assets.control)

        let result = HESectoriumInstaller(paths: fixture.paths, home: fixture.home)
            .apply(fixture.assets, action: .repair, profileConfigured: true)

        #expect(!result.succeeded)
        #expect(result.summary.contains("not a recognized legacy component: control"))
        #expect(result.changedPaths.isEmpty)
        #expect(try Data(contentsOf: fixture.control) == original)
        #expect(try Data(contentsOf: fixture.agent) == agent)
        #expect(try fixture.recoveryDirectories() == beforeRecovery)
    }

    private static func legacyBytes() throws -> Data {
        let path = try #require(ProcessInfo.processInfo.environment[artifactVariable])
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try #require(digest == acceptedHash, "Historical control artifact hash must match before fixture use")
        return bytes
    }
}

private struct UpgradeFixture {
    let root: URL
    let home: URL
    let paths: HESectoriumPaths
    let assets: HESectoriumAssets
    var control: URL { paths.root.appendingPathComponent("HESectoriumControl") }
    var agent: URL { home.appendingPathComponent("Library/LaunchAgents/com.juliushe.dev-apfs-mounter.plist") }
    var mountWrapper: URL { home.appendingPathComponent(".local/bin/dev-apfs-mount") }
    var ejectWrapper: URL { home.appendingPathComponent(".local/bin/he-eject") }

    init(control: Data, recordedAsManaged: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("auv-installer-upgrade-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        paths = HESectoriumPaths(root: home.appendingPathComponent("support", isDirectory: true))
        let input = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let controlURL = input.appendingPathComponent("control")
        let mountURL = input.appendingPathComponent("mount")
        let ejectURL = input.appendingPathComponent("eject")
        let agentURL = input.appendingPathComponent("agent.plist")
        // Unknown/legacy fixtures are placed independently of this installer's
        // durable provenance; managed-upgrade fixtures retain their real receipt.
        try (recordedAsManaged ? control : Data("fixture initial managed seed".utf8)).write(to: controlURL)
        try Data("#!/bin/sh\nexec \"__UMA_CONTROL_PATH__\" mount\n".utf8).write(to: mountURL)
        try Data("#!/bin/sh\nexec \"__UMA_CONTROL_PATH__\" eject\n".utf8).write(to: ejectURL)
        let plist: [String: Any] = ["Label": "com.juliushe.dev-apfs-mounter",
            "ProgramArguments": ["__UMA_CONTROL_PATH__", "agent"], "RunAtLoad": true,
            "ProcessType": "Background", "StandardOutPath": "__UMA_LOG_OUT__", "StandardErrorPath": "__UMA_LOG_ERR__"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL)
        assets = HESectoriumAssets(control: controlURL, devMountWrapper: mountURL,
            ejectWrapper: ejectURL, launchAgent: agentURL, identityConfig: nil)
        let installed = HESectoriumInstaller(paths: paths, home: home)
            .apply(assets, action: .install, profileConfigured: true)
        try #require(installed.succeeded, "\(installed.summary)")
        if !recordedAsManaged {
            try control.write(to: paths.root.appendingPathComponent("HESectoriumControl"))
            try control.write(to: controlURL)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func mode(_ path: URL) throws -> Int {
        ((try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777
    }
    func recoveryDirectories() throws -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: paths.root.appendingPathComponent("Recovery"),
            includingPropertiesForKeys: nil))
    }
}
