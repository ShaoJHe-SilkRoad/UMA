import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Installing the Safari Bridge AUV carries", .timeLimit(.minutes(1)))
@MainActor
struct ClaudeSafariBridgeInstallerTests {
    nonisolated private static let pinned = ClaudeSafariBridgeIdentity(build: "202611062222", generation: "gen-pinned")

    /// A folder standing in for one Mac: AUV with its Bridge inside, and an
    /// Applications folder for the copy.
    @MainActor
    private final class Disk {
        let root: URL
        let app: URL
        let bundled: URL
        let applications: URL
        var copies: [URL] = []
        var registered: [URL] = []
        var launched: [URL] = []
        var quits = 0
        var launchSucceeds = true

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("auv-bridge-\(UUID().uuidString)", isDirectory: true)
            app = root.appendingPathComponent("Applications/UMA.app", isDirectory: true)
            bundled = app.appendingPathComponent(ClaudeSafariBridgeInstaller.bundledRelativePath, isDirectory: true)
            applications = root.appendingPathComponent("home/Applications", isDirectory: true)
            try Self.makeBridge(at: bundled, identity: ClaudeSafariBridgeInstallerTests.pinned)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        static func makeBridge(at url: URL, identity: ClaudeSafariBridgeIdentity) throws {
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: NSDictionary = [
                "CFBundleIdentifier": "com.silkrd.uma.safarihost",
                "CFBundleVersion": identity.build,
                "UMARuntimeGenerationID": identity.generation,
            ]
            try info.write(to: contents.appendingPathComponent("Info.plist"))
        }

        func installer(runsFromApplications: Bool = true) -> ClaudeSafariBridgeInstaller {
            var installer = ClaudeSafariBridgeInstaller(
                bundledBridge: bundled,
                expected: ClaudeSafariBridgeInstallerTests.pinned,
                appBundle: app,
                runsFromApplications: runsFromApplications,
                installDirectory: applications,
                // Like Launch Services, only apps that exist on disk are listed.
                installedCopies: { [unowned self] in
                    copies.filter { FileManager.default.fileExists(atPath: $0.path) }
                }
            )
            installer.register = { [unowned self] in registered.append($0) }
            installer.launch = { [unowned self] url in
                launched.append(url)
                return launchSucceeds
            }
            installer.quitRunning = { [unowned self] in quits += 1 }
            installer.discard = { try FileManager.default.removeItem(at: $0) }
            return installer
        }
    }

    @Test("With no Bridge installed it is missing, or AUV must move to Applications first")
    func missing() throws {
        let disk = try Disk()
        #expect(disk.installer().status() == .missing)
        #expect(disk.installer(runsFromApplications: false).status() == .appNotInApplications)
    }

    @Test("Only the pinned build and generation count as ready")
    func pinned() throws {
        let disk = try Disk()
        let installed = disk.applications.appendingPathComponent("UMA Safari Bridge.app")
        try Disk.makeBridge(at: installed, identity: Self.pinned)
        disk.copies = [installed]
        #expect(disk.installer().status() == .ready)

        try Disk.makeBridge(at: installed, identity: .init(build: "202611062222", generation: "older"))
        #expect(disk.installer().status() == .outdated)
        try Disk.makeBridge(at: installed, identity: .init(build: "202611060253", generation: "gen-pinned"))
        #expect(disk.installer().status() == .outdated)
    }

    @Test("The copy inside AUV and one in the Trash are not an install")
    func ignoresOwnCopyAndTrash() throws {
        let disk = try Disk()
        let trashed = disk.root.appendingPathComponent("home/.Trash/UMA Safari Bridge.app")
        try Disk.makeBridge(at: trashed, identity: Self.pinned)
        disk.copies = [disk.bundled, trashed]
        #expect(disk.installer().status() == .missing)
    }

    @Test("Installing copies the Bridge to Applications, registers and starts it")
    func installs() async throws {
        let disk = try Disk()
        let installer = disk.installer()
        let target = try await installer.install()
        #expect(target == disk.applications.appendingPathComponent("UMA Safari Bridge.app", isDirectory: true))
        #expect(ClaudeSafariBridgeIdentity.of(app: target) == Self.pinned)
        #expect(disk.registered == [target])
        #expect(disk.launched == [target])
        #expect(disk.quits == 1)
        disk.copies = [target]
        #expect(installer.status() == .ready)
    }

    @Test("An outdated copy is replaced where it is")
    func replacesInPlace() async throws {
        let disk = try Disk()
        let elsewhere = disk.root.appendingPathComponent("Applications/UMA Safari Bridge.app")
        try Disk.makeBridge(at: elsewhere, identity: .init(build: "1", generation: "old"))
        disk.copies = [elsewhere]
        let target = try await disk.installer().install()
        #expect(target == elsewhere)
        #expect(ClaudeSafariBridgeIdentity.of(app: elsewhere) == Self.pinned)
        #expect(!FileManager.default.fileExists(atPath: disk.applications.path))
    }

    @Test("Nothing is copied while AUV runs from a temporary location")
    func refusesWhenTranslocated() async throws {
        let disk = try Disk()
        await #expect(throws: ClaudeSafariBridgeInstallError.appNotInApplications) {
            _ = try await disk.installer(runsFromApplications: false).install()
        }
        #expect(disk.launched.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: disk.applications.path))
    }

    @Test("A Bridge that will not start is reported")
    func reportsLaunchFailure() async throws {
        let disk = try Disk()
        disk.launchSucceeds = false
        await #expect(throws: ClaudeSafariBridgeInstallError.launchFailed) {
            _ = try await disk.installer().install()
        }
    }

    @Test("Both alerts and every failure read in both languages")
    func copy() {
        for language in [AppLanguage.english, .simplifiedChinese] {
            let text = ClaudeSafariBridgeCopy.installed(language: language)
            #expect(text.body.contains("claude.ai"))
            #expect(text.body.contains("UMA Browser Companion for Claude"))
            for error in [ClaudeSafariBridgeInstallError.appNotInApplications, .launchFailed, .copyFailed, .notBundled] {
                let (title, body) = ClaudeSafariBridgeCopy.failed(error, language: language)
                #expect(!title.isEmpty && !body.isEmpty)
            }
        }
    }

    @Test("Before the Bridge is set up, Claude's page asks for it and no sync runs")
    func modelAsksForBridge() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let suite = "auv-bridge-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: consent,
            safariIsRunning: { true }
        )
        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })

        let disk = try Disk()
        var shownInstalled = 0
        model.useSafariBridge(disk.installer(), alerts: ClaudeSafariBridgeAlerts(
            installed: { shownInstalled += 1; return false },
            failed: { _ in Issue.record("install should not fail") }
        ))
        #expect(model.agentControlState == .safariBridgeSetupRequired(.missing))
        #expect(!model.accuracySyncForRefreshAll())

        // The page's one button installs it, and then the page is back to normal.
        disk.copies = [disk.applications.appendingPathComponent("UMA Safari Bridge.app", isDirectory: true)]
        model.connectWithConsent()
        try await waitForClaudeValue(model.$safariBridgeStatus, matching: { $0 == .ready })
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        #expect(disk.launched.count == 1)
        #expect(shownInstalled == 1)
        if case .safariBridgeSetupRequired = model.agentControlState {
            Issue.record("the page still asks for the Bridge")
        }
    }
}
