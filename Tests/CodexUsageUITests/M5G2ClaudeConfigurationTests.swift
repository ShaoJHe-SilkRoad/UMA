import ClaudeStatusLineCore
import Darwin
import Foundation
import Testing

@Suite("M5-G2 Claude reversible configuration")
struct M5G2ClaudeConfigurationTests {
    @Test
    func absentSettingsEnableAndRestoreExactAbsence() throws {
        try withFixture { fixture in
            let manager = fixture.manager()
            #expect(manager.check().state == .ready(
                priorStatusLinePresent: false
            ))
            try manager.enable()
            #expect(manager.check().state == .installed)
            #expect(
                FileManager.default.fileExists(
                    atPath: fixture.paths.settingsURL.path
                )
            )
            #expect(
                try permissions(of: fixture.paths.settingsURL) == 0o600
            )
            #expect(
                try permissions(
                    of: fixture.paths.integrationDirectoryURL
                ) == 0o700
            )
            #expect(
                try permissions(of: fixture.paths.backupURL) == 0o600
            )
            try manager.restore()
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.paths.settingsURL.path
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.paths.backupURL.path
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.paths.metadataURL.path
                )
            )
        }
    }

    @Test
    func themeOnlySettingsRestoreByteForByteAndPreserveMode() throws {
        try withFixture { fixture in
            let original = Data(
                """
                {
                  "theme": "dark"
                }
                """.utf8
            ) + Data([0x0A])
            try fixture.writeSettings(original, mode: 0o640)
            let manager = fixture.manager()
            try manager.enable()
            let installed = try Data(
                contentsOf: fixture.paths.settingsURL
            )
            #expect(installed != original)
            #expect(
                try JSONSerialization.jsonObject(with: installed)
                    as? [String: Any] != nil
            )
            #expect(
                try Data(contentsOf: fixture.paths.backupURL) == original
            )
            try manager.disable()
            #expect(
                try Data(contentsOf: fixture.paths.settingsURL) == original
            )
            #expect(
                try permissions(of: fixture.paths.settingsURL) == 0o640
            )
        }
    }

    @Test
    func existingStatusLineObjectAndOptionsArePreserved() throws {
        try withFixture { fixture in
            let original = Data(
                """
                {
                  "theme": "dark",
                  "statusLine": {
                    "type": "command",
                    "command": "printf 'synthetic prior'",
                    "padding": 2,
                    "refreshInterval": 750,
                    "futureSafeOption": true
                  }
                }
                """.utf8
            ) + Data([0x0A])
            try fixture.writeSettings(original)
            let manager = fixture.manager()
            try manager.enable()
            #expect(
                try manager.priorCommandFromBackup()
                    == "printf 'synthetic prior'"
            )
            let object = try fixture.settingsObject()
            let status = try #require(
                object["statusLine"] as? [String: Any]
            )
            #expect(status["type"] as? String == "command")
            #expect(
                status["command"] as? String
                    == Fixture.relayCommand
            )
            #expect(status["padding"] as? Int == 2)
            #expect(status["refreshInterval"] as? Int == 750)
            #expect(status["futureSafeOption"] as? Bool == true)

            let metadataText = try String(
                contentsOf: fixture.paths.metadataURL,
                encoding: .utf8
            )
            #expect(!metadataText.contains("synthetic prior"))
            #expect(!metadataText.contains("command"))

            try manager.restore()
            #expect(
                try Data(contentsOf: fixture.paths.settingsURL) == original
            )
        }
    }

    @Test
    func statusLineOnlyConcurrentModificationFailsClosed() throws {
        try withFixture { fixture in
            try fixture.writeSettings(
                Data(#"{"theme":"dark"}"#.utf8)
            )
            let manager = fixture.manager()
            try manager.enable()
            var root = try fixture.settingsObject()
            var status = try #require(
                root["statusLine"] as? [String: Any]
            )
            status["command"] = "/synthetic/broken"
            root["statusLine"] = status
            try fixture.writeSettings(
                JSONSerialization.data(
                    withJSONObject: root,
                    options: [.sortedKeys]
                ),
                replacing: true
            )
            let modified = try Data(contentsOf: fixture.paths.settingsURL)
            #expect(manager.check().state == .repairRequired)
            #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
                try manager.repair()
            }
            #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
                try manager.restore()
            }
            #expect(
                try Data(contentsOf: fixture.paths.settingsURL) == modified
            )
            #expect(
                FileManager.default.fileExists(
                    atPath: fixture.paths.backupURL.path
                )
            )
            #expect(
                FileManager.default.fileExists(
                    atPath: fixture.paths.metadataURL.path
                )
            )
        }
    }

    @Test
    func repairSupportsAChangedPackagedRelayAndRestoresOriginal() throws {
        try withFixture { fixture in
            let original = Data(
                """
                {"theme":"dark","statusLine":{"type":"command",
                "command":"printf synthetic","padding":1}}
                """.utf8
            )
            try fixture.writeSettings(original, mode: 0o640)
            try fixture.manager().enable()

            let updatedRelay =
                "'/synthetic/Updated.app/Contents/Helpers/ClaudeStatusLineRelay'"
            let updatedManager = ClaudeStatusLineConfigurationManager(
                paths: fixture.paths,
                relayCommand: updatedRelay
            )
            #expect(updatedManager.check().state == .repairRequired)
            try updatedManager.repair()
            #expect(updatedManager.check().state == .installed)
            let status = try #require(
                fixture.settingsObject()["statusLine"] as? [String: Any]
            )
            #expect(status["command"] as? String == updatedRelay)
            #expect(status["padding"] as? Int == 1)

            try updatedManager.restore()
            #expect(
                try Data(contentsOf: fixture.paths.settingsURL) == original
            )
            #expect(
                try permissions(of: fixture.paths.settingsURL) == 0o640
            )
        }
    }

    @Test
    func disableCoexistsWithLiveSocketThenUninstallPrunesEmptyDirectory()
    throws {
        try withFixture { fixture in
            let original = Data(#"{"theme":"dark"}"#.utf8)
            try fixture.writeSettings(original)
            let manager = fixture.manager()
            try manager.enable()
            let socket = fixture.paths.integrationDirectoryURL
                .appendingPathComponent("usage.sock")
            try Data().write(to: socket)

            try manager.disable()
            #expect(
                try Data(contentsOf: fixture.paths.settingsURL) == original
            )
            #expect(FileManager.default.fileExists(atPath: socket.path))
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.paths.backupURL.path
                )
            )
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.paths.metadataURL.path
                )
            )

            try FileManager.default.removeItem(at: socket)
            try manager.uninstall()
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.paths.integrationDirectoryURL.path
                )
            )
        }
    }

    @Test
    func missingOrCorruptBackupAndFutureMetadataFailClosed() throws {
        try withFixture { fixture in
            try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8))
            let manager = fixture.manager()
            try manager.enable()
            try FileManager.default.removeItem(at: fixture.paths.backupURL)
            #expect(manager.check().state == .repairRequired)
            #expect(throws: ClaudeStatusLineConfigurationError.self) {
                try manager.restore()
            }
        }
        try withFixture { fixture in
            try fixture.writeSettings(Data(#"{"theme":"dark"}"#.utf8))
            let manager = fixture.manager()
            try manager.enable()
            var metadata = try #require(
                JSONSerialization.jsonObject(
                    with: Data(contentsOf: fixture.paths.metadataURL)
                ) as? [String: Any]
            )
            metadata["schemaVersion"] = 2
            try JSONSerialization.data(withJSONObject: metadata).write(
                to: fixture.paths.metadataURL,
                options: .atomic
            )
            #expect(chmod(fixture.paths.metadataURL.path, 0o600) == 0)
            #expect(manager.check().state == .unsupported)
        }
    }

    @Test
    func concurrentUnrelatedModificationFailsClosed() throws {
        try withFixture { fixture in
            try fixture.writeSettings(
                Data(#"{"theme":"dark"}"#.utf8)
            )
            let manager = fixture.manager()
            try manager.enable()
            var root = try fixture.settingsObject()
            root["unrelatedHumanSetting"] = true
            try fixture.writeSettings(
                JSONSerialization.data(
                    withJSONObject: root,
                    options: [.sortedKeys]
                ),
                replacing: true
            )
            #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
                try manager.repair()
            }
            #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
                try manager.restore()
            }
        }
    }

    @Test(arguments: [
        (#"{"disableAllHooks":true}"#, ClaudeStatusLineConfigurationState.unsupported),
        (#"{"allowManagedHooksOnly":true}"#, ClaudeStatusLineConfigurationState.unsupported),
        (#"{"schemaVersion":2}"#, ClaudeStatusLineConfigurationState.unsupported),
        (#"{"statusLine":"unsupported"}"#, ClaudeStatusLineConfigurationState.unsupported),
        ("{", ClaudeStatusLineConfigurationState.failed),
    ])
    func malformedFutureAndManagedFixturesFailClosed(
        json: String,
        expected: ClaudeStatusLineConfigurationState
    ) throws {
        try withFixture { fixture in
            try fixture.writeSettings(Data(json.utf8))
            #expect(fixture.manager().check().state == expected)
        }
    }

    @Test
    func explicitManagedAuthorityFailsClosed() throws {
        try withFixture { fixture in
            let manager = ClaudeStatusLineConfigurationManager(
                paths: fixture.paths,
                relayCommand: Fixture.relayCommand,
                authority: .managed
            )
            #expect(manager.check().state == .unsupported)
            #expect(throws: ClaudeStatusLineConfigurationError.managedConfiguration) {
                try manager.enable()
            }
        }
    }

    @Test
    func unsafeSecretAndRecursivePriorCommandsFailClosedWithoutDisclosure()
    throws {
        try withFixture { fixture in
            try fixture.writeSettings(
                Data(
                    """
                    {"statusLine":{"type":"command",
                    "command":"export ANTHROPIC_API_KEY=synthetic"}}
                    """.utf8
                )
            )
            let check = fixture.manager().check()
            #expect(check.state == .failed)
            #expect(throws: ClaudeStatusLineConfigurationError.unsafeLiteralSecret) {
                try fixture.manager().enable()
            }
        }
        try withFixture { fixture in
            try fixture.writeSettings(
                Data(
                    """
                    {"statusLine":{"type":"command",
                    "command":"/synthetic/ClaudeStatusLineRelay"}}
                    """.utf8
                )
            )
            #expect(throws: ClaudeStatusLineConfigurationError.recursivePriorCommand) {
                try fixture.manager().enable()
            }
        }
    }

    @Test
    func symlinkHardlinkAndNonregularSettingsAreRejected() throws {
        try withFixture { fixture in
            let parent = fixture.paths.settingsURL
                .deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            let target = fixture.root.appendingPathComponent("target.json")
            try Data("{}".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(
                at: fixture.paths.settingsURL,
                withDestinationURL: target
            )
            #expect(fixture.manager().check().state == .failed)
        }
        try withFixture { fixture in
            let parent = fixture.paths.settingsURL
                .deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            let target = fixture.root.appendingPathComponent("target.json")
            try Data("{}".utf8).write(to: target)
            #expect(
                link(
                    target.path,
                    fixture.paths.settingsURL.path
                ) == 0
            )
            #expect(fixture.manager().check().state == .failed)
        }
        try withFixture { fixture in
            try FileManager.default.createDirectory(
                at: fixture.paths.settingsURL,
                withIntermediateDirectories: true
            )
            #expect(fixture.manager().check().state == .failed)
        }
    }

    @Test
    func metadataContainsOnlyNonsecretRestorationFacts() throws {
        try withFixture { fixture in
            try fixture.writeSettings(
                Data(
                    """
                    {"theme":"dark","statusLine":{
                    "type":"command","command":"printf synthetic"}}
                    """.utf8
                )
            )
            let manager = fixture.manager()
            try manager.enable()
            let metadata = try String(
                contentsOf: fixture.paths.metadataURL,
                encoding: .utf8
            )
            for forbidden in [
                "printf",
                "statusLine",
                "theme",
                "quota",
                "payload",
                "credential",
            ] {
                #expect(!metadata.contains(forbidden))
            }
            try manager.uninstall()
        }
    }

    private func withFixture(
        _ body: (Fixture) throws -> Void
    ) throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try body(fixture)
    }

    private func permissions(of url: URL) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return UInt16(
            try #require(
                attributes[.posixPermissions] as? NSNumber
            ).uint16Value
        )
    }
}

private struct Fixture {
    static let relayCommand =
        "'/synthetic/UMA.app/Contents/Helpers/ClaudeStatusLineRelay'"

    let root: URL
    let paths: ClaudeStatusLineConfigurationPaths

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "uma-m5-g2-config-\(UUID().uuidString)",
                isDirectory: true
            )
        paths = ClaudeStatusLineConfigurationPaths(
            homeDirectory: root.appendingPathComponent(
                "home",
                isDirectory: true
            ),
            applicationSupportDirectory: root.appendingPathComponent(
                "support",
                isDirectory: true
            )
        )
    }

    func manager() -> ClaudeStatusLineConfigurationManager {
        ClaudeStatusLineConfigurationManager(
            paths: paths,
            relayCommand: Self.relayCommand
        )
    }

    func writeSettings(
        _ data: Data,
        mode: UInt16 = 0o600,
        replacing: Bool = false
    ) throws {
        try FileManager.default.createDirectory(
            at: paths.settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if replacing,
           FileManager.default.fileExists(atPath: paths.settingsURL.path) {
            try FileManager.default.removeItem(at: paths.settingsURL)
        }
        try data.write(to: paths.settingsURL)
        #expect(chmod(paths.settingsURL.path, mode_t(mode)) == 0)
    }

    func settingsObject() throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: paths.settingsURL)
            ) as? [String: Any]
        )
    }
}
