import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2W-G2 WorkBuddy manual source")
struct M2WG2WorkBuddyManualSourceTests {
    @Test
    func draftValidationUsesTheAcceptedCreditModelWithoutInventingTotals() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let absolute = try WorkBuddyManualDraft(
            scope: .unknown,
            tier: .unknown,
            remainingText: "9223372036854775807",
            companionField: .none,
            companionText: ""
        ).validated(at: now)
        #expect(absolute.balance.remaining == Decimal(Int64.max))
        #expect(absolute.balance.used == nil)
        #expect(absolute.balance.total == nil)
        #expect(absolute.balance.normalizedRemainingFraction == nil)

        let used = try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .standard,
            remainingText: "3600",
            companionField: .used,
            companionText: "400"
        ).validated(at: now)
        #expect(used.balance.used == 400)
        #expect(used.balance.total == 4_000)
        #expect(used.balance.normalizedRemainingFraction == 0.9)
        #expect(used.balance.scope.poolIdentity == .buddyAISharedCredits)

        let total = try WorkBuddyManualDraft(
            scope: .enterpriseShared,
            tier: .enterprise,
            remainingText: "100",
            companionField: .total,
            companionText: "500"
        ).validated(at: now)
        #expect(total.balance.used == nil)
        #expect(total.balance.total == 500)
        #expect(total.balance.planTier == .enterprise)

        let fractional = try WorkBuddyManualDraft(
            remainingText: "2099.47",
            companionField: .none
        ).validated(at: now)
        #expect(fractional.balance.remaining == Decimal(string: "2099.47"))

        for invalid in ["-1", "1..5", "NaN", "inf", "1,000", " 1", "1 "] {
            #expect(throws: WorkBuddyManualValidationError.self) {
                try WorkBuddyManualDraft(
                    remainingText: invalid,
                    companionField: .none
                ).validated(at: now)
            }
        }
        #expect(throws: WorkBuddyManualValidationError.self) {
            try WorkBuddyManualDraft(
                remainingText: "9223372036854775808",
                companionField: .none
            ).validated(at: now)
        }
        #expect(throws: WorkBuddyManualValidationError.self) {
            try WorkBuddyManualDraft(
                remainingText: "1",
                companionField: .total,
                companionText: "0"
            ).validated(at: now)
        }
        #expect(throws: WorkBuddyManualValidationError.self) {
            try WorkBuddyManualDraft(
                remainingText: "2",
                companionField: .total,
                companionText: "1"
            ).validated(at: now)
        }
    }

    @Test
    func tierSuggestionsAreVersionedExplicitAndNeverAppliedByTierSelection() {
        #expect(WorkBuddyTierSuggestion.catalogVersion == "1.0")
        #expect(WorkBuddyTierSuggestion.effectiveDate == "2026-07-24")
        #expect(
            WorkBuddyTierSuggestion.publishedJuly2026.map(\.suggestedTotal)
                == [500, 4_000, 9_000, 50_000]
        )
        #expect(
            WorkBuddyTierSuggestion.publishedJuly2026.map(\.temporaryBonusCredits)
                == [0, 2_000, 5_000, 30_000]
        )

        var draft = WorkBuddyManualDraft(
            tier: .experience,
            remainingText: "25",
            companionField: .total,
            companionText: "100"
        )
        draft.tier = .flagship
        #expect(draft.companionText == "100")
    }

    @Test
    func persistenceIsBoundedPrivateVersionedAndRecoversFromBackup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workbuddy-manual-availability.json")
        let store = WorkBuddyManualAvailabilityStore(fileURL: url)
        let observation = try Self.observation(at: Date(timeIntervalSince1970: 1_800_000_000))
        let record = WorkBuddyManualPersistenceRecord(enabled: true, observation: observation)

        #expect(try await store.save(record))
        #expect(!(try await store.save(record)))
        #expect(await store.writeCount == 1)
        #expect(await store.load() == .valid(record))

        let data = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: await store.backupURL)
        #expect(try await store.save(record))
        #expect(await store.writeCount == 2)
        #expect(try Data(contentsOf: await store.backupURL) == data)

        try Data("corrupt backup".utf8).write(
            to: await store.backupURL,
            options: .atomic
        )
        #expect(try await store.save(record))
        #expect(await store.writeCount == 3)
        #expect(try Data(contentsOf: await store.backupURL) == data)

        try Data(
            repeating: 0x41,
            count: WorkBuddyManualAvailabilityStore.maximumRecordBytes + 1
        ).write(to: url, options: .atomic)
        #expect(try await store.save(record))
        #expect(await store.writeCount == 4)
        #expect(try Data(contentsOf: url) == data)
        #expect(!(try await store.save(record)))
        #expect(await store.writeCount == 4)

        #expect(data.count <= WorkBuddyManualAvailabilityStore.maximumRecordBytes)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in [
            "email", "accountId", "organization", "phone", "cookie", "token",
            "keychain", "screenshot", "html", "browser", "conversation", "taskContent",
            "rawPayload", "credential"
        ] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(text.contains(#""connectorID":"workbuddy.manualAvailability""#))
        #expect(text.contains(#""sourceMode":"manualConfirmation""#))
        #expect(text.contains(#""rawValue":"buddyAI.sharedCredits""#))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)

        try Data("corrupt".utf8).write(to: url, options: .atomic)
        #expect(await store.load() == .valid(record))

        var future = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        future["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
            .write(to: url, options: .atomic)
        #expect(await store.load() == .invalid(.unsupportedSchema))
    }

    @Test
    func lifecycleSeparatesDisableConfirmAndClearWithChangeOnlyWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let clock = TestDateClock(Date(timeIntervalSince1970: 1_800_000_000))
        let source = ManualWorkBuddyAvailabilitySource(
            store: persistence,
            now: { clock.value }
        )
        #expect((await source.load()).lifecycle == .unconfigured)
        #expect(try await source.setEnabled(true))
        #expect((await source.currentState()).lifecycle == .unconfigured)

        let first = try Self.observation(at: clock.value)
        #expect(try await source.save(first))
        let writesAfterSave = await persistence.writeCount
        let publicationsAfterSave = await source.publicationCount

        clock.value = clock.value.addingTimeInterval(60)
        let sameValuesNewTimestamp = try Self.observation(at: clock.value)
        #expect(!(try await source.save(sameValuesNewTimestamp)))
        #expect(await persistence.writeCount == writesAfterSave)
        #expect(await source.publicationCount == publicationsAfterSave)

        clock.value = clock.value.addingTimeInterval(60)
        #expect(try await source.confirmUnchanged(at: clock.value))
        let confirmed = try #require((await source.currentState()).observation)
        #expect(confirmed.balance.remaining == first.balance.remaining)
        #expect(confirmed.balance.used == first.balance.used)
        #expect(confirmed.balance.total == first.balance.total)
        #expect(confirmed.balance.observedAt == clock.value)

        #expect(try await source.setEnabled(false))
        let disabled = await source.currentState()
        #expect(disabled.lifecycle == .disabled)
        #expect(disabled.observation?.balance.observedAt == clock.value)
        #expect(try await source.setEnabled(true))
        let restored = await source.currentState()
        #expect(restored.lifecycle == .manualConfirmed)
        #expect(restored.observation?.balance.observedAt == clock.value)

        #expect(try await source.clear())
        let cleared = await source.currentState()
        #expect(cleared.lifecycle == .unconfigured)
        #expect(cleared.observation == nil)
        #expect(!FileManager.default.fileExists(atPath: (await persistence.fileURL).path))
        #expect(!FileManager.default.fileExists(atPath: (await persistence.backupURL).path))
        #expect(await persistence.load() == .missing)
        let publicationsAfterClear = await source.publicationCount
        let writesAfterClear = await persistence.writeCount
        #expect(!(try await source.clear()))
        #expect(await source.publicationCount == publicationsAfterClear)
        #expect(await persistence.writeCount == writesAfterClear)
    }

    @Test @MainActor
    func sourceMulticastsOneManualChangeToConnectorAndSettings() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(
                fileURL: directory.appendingPathComponent("manual.json")
            )
        )
        let connector = WorkBuddyAvailabilityConnector(source: source)
        let settings = WorkBuddySettingsModel(source: source)

        await connector.start()
        settings.start()
        let observation = try Self.observation(
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(try await source.save(observation))

        for _ in 0..<50 {
            let connectorValue = await connector.currentSnapshot()
                .channels.first?.availability.creditBalance
            if connectorValue == observation.balance,
               settings.savedObservation == observation {
                break
            }
            await Task.yield()
        }

        #expect(
            await connector.currentSnapshot()
                .channels.first?.availability.creditBalance == observation.balance
        )
        #expect(settings.savedObservation == observation)
        await connector.stop()
    }

    @Test
    func manualObservationRejectsMismatchedConfirmationTimestamp() throws {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let confirmedAt = observedAt.addingTimeInterval(60)
        let balance = try CreditBalance(
            validatingRemaining: Int64(10),
            scope: .buddyAISharedPersonal,
            planTier: .personal,
            observedAt: observedAt,
            provenance: .manualConfirmed(at: confirmedAt)
        )
        do {
            _ = try WorkBuddyManualObservation(
                scope: .personalShared,
                tier: .standard,
                balance: balance
            )
            Issue.record("A mismatched manual confirmation timestamp was accepted")
        } catch let error as WorkBuddyManualValidationError {
            #expect(error == .invalidManualRecord)
        }
    }

    @Test
    func connectorIsStableManualSharedPresentationAndRefreshIsACompleteNoOp() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let source = ManualWorkBuddyAvailabilitySource(store: persistence)
        let connector = WorkBuddyAvailabilityConnector(source: source)
        let genericStore = AgentConnectorSnapshotStore(
            url: directory.appendingPathComponent("connector-snapshots.json")
        )
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: genericStore
        )

        await registry.startPassiveConnectors()
        try await source.setEnabled(true)
        try await source.save(Self.observation(at: Date(timeIntervalSince1970: 1_800_000_000)))
        for _ in 0..<200 where (await registry.orderedSnapshots().first?.channels.first?.availability.creditBalance) == nil {
            await Task.yield()
        }

        let snapshot = try #require(await registry.orderedSnapshots().first)
        #expect(snapshot.id.rawValue == "workbuddy.manualAvailability")
        #expect(snapshot.providerName == "WorkBuddy")
        #expect(snapshot.state == .inactive)
        #expect(snapshot.freshness == .unavailable)
        #expect(snapshot.lastSuccessfulAt == nil)
        #expect(snapshot.channels.first?.provenance == .manualConfirmed)
        #expect(snapshot.channels.first?.availability?.sourceState == .manualConfirmed)
        #expect(snapshot.channels.first?.availability.creditBalance?.scope.poolIdentity == .buddyAISharedCredits)
        #expect(!snapshot.capabilities.contains(.hiddenFromProviderSurfaces))
        #expect(!snapshot.capabilities.contains(.hiddenFromDesktopAssistant))
        #expect(snapshot.capabilities.contains(.passiveLocalAvailability))
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: [snapshot],
            previousCards: [],
            language: .english
        )
        #expect(cards.map(\.id) == ["workbuddy.manualAvailability"])
        #expect(cards.allSatisfy { $0.isVisibleInDesktopAssistant })
        #expect(snapshot.channels.first?.coverageNote == "Manual snapshot · Shared with CodeBuddy")
        #expect(!FileManager.default.fileExists(atPath: (await genericStore.url).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: (await genericStore.backupURL).path
            )
        )

        let writes = await persistence.writeCount
        let publications = await source.publicationCount
        let confirmedAt = snapshot.channels.first?.availability.creditBalance?.observedAt
        for _ in 0..<20 {
            try await registry.refresh(connector.id, trigger: .manual)
        }
        let afterRefresh = try #require(await registry.orderedSnapshots().first)
        #expect(await persistence.writeCount == writes)
        #expect(await source.publicationCount == publications)
        #expect(afterRefresh.channels.first?.availability.creditBalance?.observedAt == confirmedAt)
        #expect((await genericStore.load()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: (await genericStore.url).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: (await genericStore.backupURL).path
            )
        )
        await registry.stopAll()
    }

    @Test
    func emptyManualStatesDoNotFabricateSnapshotMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(
                fileURL: directory.appendingPathComponent("manual.json")
            )
        )

        let unconfiguredConnector = WorkBuddyAvailabilityConnector(source: source)
        await unconfiguredConnector.start()
        let unconfigured = await unconfiguredConnector.currentSnapshot()
        #expect(unconfigured.channels.first?.coverageNote == nil)
        #expect(unconfigured.channels.first?.availability == .unavailable)
        await unconfiguredConnector.stop()

        try await source.setEnabled(true)
        let enabledConnector = WorkBuddyAvailabilityConnector(source: source)
        await enabledConnector.start()
        let enabledWithoutValue = await enabledConnector.currentSnapshot()
        #expect(enabledWithoutValue.channels.first?.coverageNote == nil)
        #expect(enabledWithoutValue.channels.first?.availability == .unavailable)
        await enabledConnector.stop()

        try await source.setEnabled(false)
        let disabledConnector = WorkBuddyAvailabilityConnector(source: source)
        await disabledConnector.start()
        let disabled = await disabledConnector.currentSnapshot()
        #expect(disabled.channels.first?.coverageNote == nil)
        #expect(disabled.channels.first?.availability == .unavailable)
        await disabledConnector.stop()
    }

    @Test @MainActor
    func usageStorePresentsManualStateWithoutCodexConsentAcrossSharedSurfaces() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let source = ManualWorkBuddyAvailabilitySource(store: persistence)
        let connector = WorkBuddyAvailabilityConnector(source: source)
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let defaults = UserDefaults(suiteName: "m2w-g2-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: defaults
        )

        try await source.setEnabled(true)
        try await source.save(Self.observation(at: Date(timeIntervalSince1970: 1_800_000_000)))
        for _ in 0..<50 where store.providerSnapshots.isEmpty {
            await Task.yield()
        }
        #expect(store.providerSnapshots.map(\.id.rawValue) == ["workbuddy.manualAvailability"])
        #expect(store.presentationCards.map(\.id) == ["workbuddy.manualAvailability"])
        #expect(store.assistantPresentationCards.map(\.id) == ["workbuddy.manualAvailability"])
        #expect(!store.hasPriorRealSnapshot)

        store.grantMonitorConsent()
        await store.disconnectAndForgetConsent()
        #expect(store.providerSnapshots.map(\.id.rawValue) == ["workbuddy.manualAvailability"])
        #expect(store.presentationCards.map(\.id) == ["workbuddy.manualAvailability"])
        #expect(store.assistantPresentationCards.map(\.id) == ["workbuddy.manualAvailability"])
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func persistedCodexResumeDoesNotWaitForPassiveSourceStartup() async throws {
        let primary = StartupOrderingConnector(
            rawID: "codex.local",
            passive: false,
            blocksStart: false
        )
        let passive = StartupOrderingConnector(
            rawID: "workbuddy.manualAvailability",
            passive: true,
            blocksStart: true
        )
        let registry = try AgentConnectorRegistry(connectors: [primary, passive])
        let suiteName = "m2w-g2-startup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: primary.id,
            consentDefaults: defaults
        )

        for _ in 0..<100 where await primary.performCount == 0 {
            await Task.yield()
        }
        #expect(await primary.performCount == 1)
        #expect(await passive.didEnterStart)
        #expect(!(await passive.didFinishStart))

        await passive.releaseStart()
        await store.stopAllConnectors()
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func connectorIDGrammarAdmitsStableWorkBuddyIDWithoutWeakeningBoundaries() {
        #expect(AgentConnectorID(rawValue: "workbuddy.manualAvailability") != nil)
        #expect(AgentConnectorID(rawValue: "workbuddy.manualavailability") != nil)
        #expect(
            AgentConnectorID(rawValue: "workbuddy.manualAvailability")
                != AgentConnectorID(rawValue: "workbuddy.manualavailability")
        )
        for invalid in [
            "Workbuddy.manualAvailability",
            "workbuddy..manualAvailability",
            "workbuddy.-manualAvailability",
            "workbuddy.manual_Availability",
            "workbuddy.manualAvailability."
        ] {
            #expect(AgentConnectorID(rawValue: invalid) == nil)
        }
    }

    @Test @MainActor
    func officialURLIsExactAllowlistedExplicitAndDeterministicallyInjected() {
        var opened: [URL] = []
        let action = WorkBuddyOfficialUsagePageAction { url in
            opened.append(url)
            return true
        }
        #expect(opened.isEmpty)
        #expect(action.request())
        #expect(opened == [WorkBuddyOfficialUsagePageAction.url])
        #expect(WorkBuddyOfficialUsagePageAction.url.absoluteString == "https://www.workbuddy.cn/docs/workbuddy/Usage")
        #expect(WorkBuddyOfficialUsagePageAction.isAllowed(WorkBuddyOfficialUsagePageAction.url))
        #expect(!WorkBuddyOfficialUsagePageAction.isAllowed(URL(string: "http://www.workbuddy.cn/docs/workbuddy/Usage")!))
        #expect(!WorkBuddyOfficialUsagePageAction.isAllowed(URL(string: "https://www.workbuddy.cn/docs/workbuddy/Usage?remaining=5")!))
        #expect(!WorkBuddyOfficialUsagePageAction.isAllowed(URL(string: "https://example.com/docs/workbuddy/Usage")!))
    }

    @Test
    func localizationAndSettingsSourceCoverRequiredAccessibilityConcepts() throws {
        #expect(AppLanguage.english.workBuddyManualConfirmation == "Manual confirmation")
        #expect(AppLanguage.simplifiedChinese.workBuddyManualConfirmation == "手动确认")
        #expect(AppLanguage.english.workBuddySharedWithCodeBuddy == "Shared with CodeBuddy")
        #expect(AppLanguage.simplifiedChinese.workBuddySharedWithCodeBuddy == "与 CodeBuddy 共享")
        #expect(AppLanguage.english.workBuddyAvailableCredits.contains("Credits"))
        #expect(AppLanguage.simplifiedChinese.workBuddyAvailableCredits.contains("Credits"))
        #expect(AppLanguage.english.workBuddyOfficialPageHint.contains("does not read"))
        #expect(AppLanguage.simplifiedChinese.workBuddyOfficialPageHint.contains("不会读取"))
        #expect(AppLanguage.english.workBuddyLastConfirmed == "Last confirmed")
        #expect(AppLanguage.simplifiedChinese.workBuddyLastConfirmed == "上次确认")

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: repository
                .appendingPathComponent("Sources/CodexUsageUI/Views/UsageSettingsCard.swift"),
            encoding: .utf8
        )
        #expect(settings.contains("ScrollView(.vertical)"))
        #expect(settings.contains("WorkBuddySettingsSection"))
        #expect(settings.contains(".accessibilityLabel"))
        #expect(settings.contains(".accessibilityHint"))
        #expect(settings.contains("clearIsArmed"))
        #expect(settings.contains("DatePicker"))
        #expect(settings.contains("workBuddyLastConfirmed"))

        let panel = try String(
            contentsOf: repository
                .appendingPathComponent("Sources/CodexUsageUI/Views/UsagePanelView.swift"),
            encoding: .utf8
        )
        #expect(panel.contains("!presentation.showsRealData"))
        #expect(panel.contains(".accessibilityLabel(store.language.showSettings)"))
    }

    @Test
    func g2SourceHasNoProviderNetworkProcessPollingOrBrowserReader() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativeFiles = [
            "Sources/CodexUsageUI/Services/ManualWorkBuddyAvailabilitySource.swift",
            "Sources/CodexUsageUI/Services/WorkBuddyManualAvailabilityStore.swift",
            "Sources/CodexUsageUI/Connectors/WorkBuddyAvailabilityConnector.swift"
        ]
        let source = try relativeFiles.map {
            try String(contentsOf: repository.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
        for forbidden in [
            "URLSession", "Process(", "Timer(", "DispatchSource",
            "FSEvent", "NSWorkspace.shared.open", "AXUIElement", "OneDrive",
            "Keychain", "cookie", "OCR"
        ] {
            #expect(!source.localizedCaseInsensitiveContains(forbidden))
        }
    }

    private static func observation(at date: Date) throws -> WorkBuddyManualObservation {
        try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .standard,
            remainingText: "3600",
            companionField: .used,
            companionText: "400"
        ).validated(at: date)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-m2w-g2-\(UUID().uuidString)", isDirectory: true)
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.volatileDomainNames.first ?? ""
    }
}

private final class TestDateClock: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

private actor StartupOrderingConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private let blocksStart: Bool
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private(set) var didEnterStart = false
    private(set) var didFinishStart = false
    private(set) var performCount = 0

    init(rawID: String, passive: Bool, blocksStart: Bool) {
        id = AgentConnectorID(rawValue: rawID)!
        self.blocksStart = blocksStart
        descriptor = AgentConnectorDescriptor(
            id: id,
            providerName: passive ? "WorkBuddy" : "Codex",
            officialSource: "test",
            sourceTier: passive ? .manualUserConfirmed : .officialLocalService,
            sourceVersion: "1",
            supportedScopes: [.account],
            capabilities: passive
                ? [.passiveLocalAvailability, .hiddenFromProviderSurfaces]
                : [.connect],
            configurationRequirements: [],
            privacyAllowlist: [],
            supportsRestore: !passive,
            supportsUninstall: false,
            unsupportedFields: []
        )!
    }

    func probe() async -> AgentConnectorProbe {
        .init(state: .inactive, safeFailure: nil)
    }

    func start() async {
        didEnterStart = true
        if blocksStart {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
        didFinishStart = true
    }

    func releaseStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func refresh() async {}

    func perform(_ command: AgentConnectorCommand) async {
        performCount += 1
        continuation?.yield(snapshot())
    }

    func stop() async {
        releaseStart()
        continuation?.finish()
        continuation = nil
    }

    func currentSnapshot() async -> AgentUsageSnapshot { snapshot() }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot())
        }
    }

    private func snapshot() -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: id,
            providerName: descriptor.providerName,
            state: .inactive,
            capturedAt: .distantPast,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: descriptor.capabilities,
            safeFailure: nil
        )
    }
}

private extension Optional where Wrapped == AgentAvailabilityValue {
    var creditBalance: CreditBalance? {
        self?.creditBalance
    }
}
