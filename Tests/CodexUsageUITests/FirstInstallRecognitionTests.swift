import Foundation
import Testing
@testable import CodexUsageUI

/// Synthetic installations and empty stores; never launch a provider or read credentials.
@Suite(.timeLimit(.minutes(1)))
struct FirstInstallRecognitionTests {
    @Test(arguments: [
        "/Applications/Codex.app", "/Applications/ChatGPT.app",
        "/synthetic-user/Applications/Codex.app", "/synthetic-user/Applications/ChatGPT.app",
        "/synthetic-custom/OpenAI Renamed.app"
    ])
    func findsVerifiedInstallWithoutPreferencesOrCache(path: String) throws {
        let executable = path + "/Contents/Resources/codex"
        let resolver = fixture(apps: [], registered: [path], files: [path, executable])
        let start = ContinuousClock.now
        #expect(try resolver.resolve().path == executable)
        let elapsed = start.duration(to: .now)
        print("FIRST_INSTALL_FIXTURE discovery=\(elapsed)")
        #expect(elapsed < .seconds(1))
    }

    @Test
    func brokenInstallCannotMaskHealthyFallbackAndExplicitLocationHasPriority() throws {
        let broken = "/synthetic/Broken.app"
        let preferred = "/synthetic/Preferred.app"
        let fallback = "/synthetic/Fallback.app"
        let suffix = "/Contents/Resources/codex-cli/bin/codex"
        let files: Set<String> = [broken, preferred, preferred + suffix, fallback, fallback + suffix]
        #expect(try fixture(apps: [broken, preferred], registered: [fallback], files: files).resolve().path == preferred + suffix)
        #expect(try fixture(apps: [broken], registered: [fallback], files: files).resolve().path == fallback + suffix)
    }

    @Test(arguments: [false, true])
    func rejectsUnverifiedIdentityOrSignature(wrongBundle: Bool) {
        let path = "/synthetic/Lookalike.app"
        let resolver = CodexExecutableResolver(
            applicationPaths: [path], fileExists: { _ in true }, isExecutable: { _ in true },
            bundleIdentifier: { _ in wrongBundle ? "com.example.lookalike" : "com.openai.codex" },
            registeredApplicationPaths: { [] }, validSignature: { _ in wrongBundle }
        )
        #expect(throws: CodexUsageClientError(.codexApplicationNotFound)) { try resolver.resolve() }
    }

    @Test
    func distinguishesAbsentBrokenAndNonExecutableInstallations() {
        let app = "/synthetic/Codex.app"
        #expect(throws: CodexUsageClientError(.codexApplicationNotFound)) {
            try fixture(apps: [], files: []).resolve()
        }
        #expect(throws: CodexUsageClientError(.codexExecutableNotFound)) {
            try fixture(apps: [app], files: [app]).resolve()
        }
        #expect(throws: CodexUsageClientError(.codexExecutableNotExecutable)) {
            try fixture(apps: [app], files: [app, app + "/Contents/Resources/codex"], executable: false).resolve()
        }
    }

    @Test
    func rejectsSymlinkEscapingVerifiedBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Codex.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let external = root.appendingPathComponent("untrusted-codex")
        try Data().write(to: external)
        try FileManager.default.createSymbolicLink(at: resources.appendingPathComponent("codex"), withDestinationURL: external)
        let resolver = CodexExecutableResolver(
            applicationPaths: [app.path], isExecutable: { _ in true },
            bundleIdentifier: { _ in "com.openai.codex" }, registeredApplicationPaths: { [] }, validSignature: { _ in true }
        )
        #expect(throws: CodexUsageClientError(.codexExecutableNotFound)) { try resolver.resolve() }
    }

    @Test(arguments: [AgentSafeFailure.timedOut, .unsupported, .malformedResponse, .processExited, .authorizationRequired])
    func failedAdmissionRetainsRecoveryReasonWithoutAdmittingQuota(failure: AgentSafeFailure) {
        let record = ProviderSurfaceAdmissionRecord(
            id: CodexUsageConnector.connectorID, providerName: "Codex", priority: 0,
            admission: .hiddenCurrentReadFailed, loginOption: nil, safeFailure: failure
        )
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [], admissions: [record], monitoringEnabledIDs: [record.id],
            configuredOrDetectedIDs: [record.id], previousCards: [], language: .english
        )
        let state = reduction.inventory.provider(.codex)
        let expected: ProviderProductDiagnosticReason = switch failure {
        case .timedOut: .timedOut
        case .unsupported: .unsupported
        case .malformedResponse: .invalidData
        case .processExited: .processUnavailable
        case .authorizationRequired: .authorizationRequired
        default: .unknown
        }
        #expect(state?.diagnosticReason == expected)
        #expect(state?.primaryDisplayText == "—")
        #expect(reduction.inventory.quickPanelProviders.isEmpty)
        #expect(reduction.presentationCards.isEmpty)
    }

    @Test @MainActor
    func firstConnectionFailureSurvivesScannerAndStorePublicationAndRecovers() async throws {
        let client = RecoveringFirstInstallClient()
        let store = UsageStore(
            autoRefresh: false, previewOnly: false, language: .english,
            registry: AgentUsageRuntime.makeCodexRegistry(
                snapshotStore: nil, client: client, localActivityReader: EmptyFirstInstallLocalReader()
            ),
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: nil
        )
        store.grantMonitorConsent()
        await store.connectToLocalSession()
        #expect(store.lastFailure == .protocolIncompatible)
        #expect(store.lastError?.contains("Update Codex") == true)
        #expect(store.menuPercent == nil)
        #expect(store.productInventory.provider(.codex)?.diagnosticReason == .unsupported)

        await client.allowValidQuota()
        await store.refresh()
        #expect(store.menuPercent == 80)
        #expect(store.lastFailure == nil)
        #expect(store.lastError == nil)
        await store.stopAllConnectors()
    }

    @Test
    func claudeDesktopDiscoveryIncludesUserAndRegisteredLocationsWithoutFixtureHostFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let applications = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let isolated = ClaudeLocalSurfaceDetector(homeDirectory: home, applicationsDirectory: applications)
        #expect(!isolated.claudeDesktopInstalled)

        let userApp = home.appendingPathComponent("Applications/Claude.app")
        try FileManager.default.createDirectory(at: userApp, withIntermediateDirectories: true)
        #expect(isolated.claudeDesktopInstalled)
        try FileManager.default.removeItem(at: userApp)

        let renamed = root.appendingPathComponent("Custom/Assistant.app")
        try FileManager.default.createDirectory(at: renamed, withIntermediateDirectories: true)
        let registered = ClaudeLocalSurfaceDetector(
            homeDirectory: home, applicationsDirectory: applications,
            registeredApplicationPaths: { [renamed.path] },
            bundleIdentifier: { _ in "com.anthropic.claudefordesktop" }
        )
        #expect(registered.claudeDesktopInstalled)
        let wrongIdentity = ClaudeLocalSurfaceDetector(
            homeDirectory: home, applicationsDirectory: applications,
            registeredApplicationPaths: { [renamed.path] },
            bundleIdentifier: { _ in "com.example.lookalike" }
        )
        #expect(!wrongIdentity.claudeDesktopInstalled)
    }

    @Test
    func installedOfficialClientDiscoveryReadOnlyWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["AUV_TEST_INSTALLED_DISCOVERY"] == "1" else { return }
        let start = ContinuousClock.now
        let executable = try CodexExecutableResolver().resolve()
        print("INSTALLED_DISCOVERY executable=\(executable.path) elapsed=\(start.duration(to: .now))")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
    }

    @Test
    func installedAccountQuotaReadOnlyWhenExplicitlyEnabledAndAlreadyConsented() async throws {
        guard ProcessInfo.processInfo.environment["AUV_TEST_INSTALLED_ACCOUNT"] == "1" else { return }
        let defaults = try #require(UserDefaults(suiteName: "com.silkrd.uma"))
        try #require(CodexMonitorConsentDecision.load(from: defaults) == .granted)
        // No login, local-history reader, inference, or preference writes.
        let client = CodexAppServerClient()
        do {
            let start = ContinuousClock.now
            let first = try await client.fetchUsage()
            let firstElapsed = start.duration(to: .now)
            #expect(!first.rateLimits.windows.isEmpty)
            #expect(await client.connectionState() == .ready)
            let refreshStart = ContinuousClock.now
            let second = try await client.fetchUsage()
            #expect(!second.rateLimits.windows.isEmpty)
            print("INSTALLED_QUOTA first=\(firstElapsed) refresh=\(refreshStart.duration(to: .now)) windows=\(second.rateLimits.windows.count)")
            await client.disconnect()
        } catch {
            await client.disconnect()
            throw error
        }
    }

    private func fixture(
        apps: [String], registered: [String] = [], files: Set<String>, executable: Bool = true
    ) -> CodexExecutableResolver {
        CodexExecutableResolver(
            applicationPaths: apps, fileExists: { files.contains($0) }, isExecutable: { _ in executable },
            bundleIdentifier: { _ in "com.openai.codex" }, registeredApplicationPaths: { registered },
            validSignature: { _ in true }
        )
    }
}

private struct EmptyFirstInstallLocalReader: CodexLocalActivityReading {
    func read(now: Date) -> CodexLocalActivitySnapshot {
        .init(availability: .unavailable, source: "fixture", scope: "unavailable", capturedAt: now,
              discoveredFileCount: 0, readableFileCount: 0, excludedFileCount: 0,
              tasks: [], apiEquivalentCost: nil)
    }
}

private actor RecoveringFirstInstallClient: CodexUsageClient {
    private var validQuota = false
    func allowValidQuota() { validQuota = true }
    func checkLocalAccountAvailability() async throws -> Bool { true }
    func fetchUsage() async throws -> CodexLiveUsage {
        guard validQuota else { throw CodexUsageClientError(.protocolIncompatible) }
        return CodexLiveUsage(
            rateLimits: .init(planType: "PRO", windows: [
                .init(id: "five-hour", usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil)
            ]),
            availableResetCount: nil, lifetimeTokens: nil, dailyUsage: nil,
            recentActivityCount: 0, apiCostEstimate: nil, providerCapturedAt: Date()
        )
    }
    func disconnect() async {}
    func takeUsageRefreshRequest() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .idle }
}
