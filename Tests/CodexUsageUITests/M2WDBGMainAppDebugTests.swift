import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WDBG-G1 manual availability debug")
struct M2WDBGMainAppDebugTests {
    @Test
    func configurationModelOffersAnExplicitAllThreeValuesMode() throws {
        #expect(WorkBuddyCreditCompanionField.allCases.count == 4)
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let observation = try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .standard,
            remainingText: "3600",
            companionField: .usedAndTotal,
            companionText: "400",
            explicitTotalText: "4000"
        ).validated(at: confirmedAt)
        #expect(observation.balance.remaining == 3_600)
        #expect(observation.balance.used == 400)
        #expect(observation.balance.total == 4_000)
        #expect(observation.resolvedEntryMode == .usedAndTotal)
        #expect(WorkBuddyManualDraft.from(observation).companionField == .usedAndTotal)

        #expect(throws: WorkBuddyManualValidationError.self) {
            try WorkBuddyManualDraft(
                remainingText: "3600",
                companionField: .usedAndTotal,
                companionText: "400",
                explicitTotalText: "3999"
            ).validated(at: confirmedAt)
        }
    }

    @Test
    func debugStoreOverrideIsBundleAndPathConstrained() throws {
        let fileManager = FileManager.default
        let parent = temporaryDirectory("debug-store-boundary")
        defer { try? fileManager.removeItem(at: parent) }
        let root = parent.appendingPathComponent("uma-m2wdbg-runtime")
        let stores = root.appendingPathComponent("stores")
        try fileManager.createDirectory(
            at: stores,
            withIntermediateDirectories: true
        )
        let allowed = stores.appendingPathComponent("manual.json").path
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor.m2wdbg.abc",
                environment: ["UMA_M2WDBG_MANUAL_STORE": allowed],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: root
            )?.path == canonicalPath(allowed)
        )
        let snapshots = stores.appendingPathComponent("snapshots.json").path
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor.m2wdbg.abc",
                environment: ["UMA_M2WDBG_SNAPSHOT_STORE": snapshots],
                variable: "UMA_M2WDBG_SNAPSHOT_STORE",
                allowedRoot: root
            )?.path == canonicalPath(snapshots)
        )
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor",
                environment: ["UMA_M2WDBG_MANUAL_STORE": allowed],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: root
            ) == nil
        )
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "evil.com.kevinchen.CodexUsageMonitor.m2wdbg.abc",
                environment: ["UMA_M2WDBG_MANUAL_STORE": allowed],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: root
            ) == nil
        )
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: nil,
                environment: ["UMA_M2WDBG_MANUAL_STORE": allowed],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: root
            ) == nil
        )
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor.not-m2wdbg.abc",
                environment: ["UMA_M2WDBG_MANUAL_STORE": allowed],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: root
            ) == nil
        )
        for rejected in [
            "/Users/example/private.json",
            root.appendingPathComponent("../outside.json").path,
            stores.appendingPathComponent("manual.plist").path
        ] {
            #expect(
                UsageMonitorRuntime.m2wdbgStoreURL(
                    bundleIdentifier: "com.kevinchen.CodexUsageMonitor.m2wdbg.abc",
                    environment: ["UMA_M2WDBG_MANUAL_STORE": rejected],
                    variable: "UMA_M2WDBG_MANUAL_STORE",
                    allowedRoot: root
                ) == nil
            )
        }

        let rootTarget = parent.appendingPathComponent("root-target")
        try fileManager.createDirectory(
            at: rootTarget,
            withIntermediateDirectories: true
        )
        let symlinkRoot = parent.appendingPathComponent("root-link")
        try fileManager.createSymbolicLink(
            at: symlinkRoot,
            withDestinationURL: rootTarget
        )
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor.m2wdbg.abc",
                environment: [
                    "UMA_M2WDBG_MANUAL_STORE":
                        symlinkRoot.appendingPathComponent("manual.json").path
                ],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: symlinkRoot
            ) == nil
        )

        let outside = parent.appendingPathComponent("outside.json")
        try Data("outside".utf8).write(to: outside)
        let symlinkLeaf = stores.appendingPathComponent("linked.json")
        try fileManager.createSymbolicLink(
            at: symlinkLeaf,
            withDestinationURL: outside
        )
        #expect(
            UsageMonitorRuntime.m2wdbgStoreURL(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor.m2wdbg.abc",
                environment: ["UMA_M2WDBG_MANUAL_STORE": symlinkLeaf.path],
                variable: "UMA_M2WDBG_MANUAL_STORE",
                allowedRoot: root
            ) == nil
        )
    }

    @Test
    @MainActor
    func debugRuntimeRequiresBothIsolatedStoresBeforeConstruction() throws {
        let fileManager = FileManager.default
        let parent = temporaryDirectory("debug-runtime-boundary")
        defer { try? fileManager.removeItem(at: parent) }
        let root = parent.appendingPathComponent("uma-m2wdbg-runtime")
        let stores = root.appendingPathComponent("stores")
        try fileManager.createDirectory(
            at: stores,
            withIntermediateDirectories: true
        )
        let bundleIdentifier =
            "com.kevinchen.CodexUsageMonitor.m2wdbg.integration"
        let manual = stores.appendingPathComponent("manual.json").path
        let snapshots = stores.appendingPathComponent("snapshots.json").path

        #expect(throws: UsageMonitorRuntimeError.self) {
            _ = try UsageMonitorRuntime.live(
                bundleIdentifier: bundleIdentifier,
                environment: [:],
                allowedRoot: root
            )
        }
        #expect(throws: UsageMonitorRuntimeError.self) {
            _ = try UsageMonitorRuntime.live(
                bundleIdentifier: bundleIdentifier,
                environment: ["UMA_M2WDBG_MANUAL_STORE": manual],
                allowedRoot: root
            )
        }
        #expect(throws: UsageMonitorRuntimeError.self) {
            _ = try UsageMonitorRuntime.live(
                bundleIdentifier: bundleIdentifier,
                environment: ["UMA_M2WDBG_SNAPSHOT_STORE": snapshots],
                allowedRoot: root
            )
        }
        _ = try UsageMonitorRuntime.live(
            bundleIdentifier: bundleIdentifier,
            environment: [
                "UMA_M2WDBG_MANUAL_STORE": manual,
                "UMA_M2WDBG_SNAPSHOT_STORE": snapshots
            ],
            allowedRoot: root
        )
    }

    private func canonicalPath(_ path: String) -> String {
        let lexicalURL = URL(fileURLWithPath: path).standardizedFileURL
        return lexicalURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(lexicalURL.lastPathComponent)
            .path
    }

    @Test
    func unchangedSaveRepairsMissingRecoveryWithoutChangingConfirmation() async throws {
        let directory = temporaryDirectory("duplicate-repair")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let source = ManualWorkBuddyAvailabilitySource(store: store)
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try observation(remaining: 3_600, used: 400, at: firstDate)

        #expect(try await source.save(first))
        let backupURL = await store.backupURL
        try FileManager.default.removeItem(at: backupURL)

        let duplicate = try observation(
            remaining: 3_600,
            used: 400,
            at: firstDate.addingTimeInterval(600)
        )
        #expect(!(try await source.save(duplicate)))
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(await store.writeCount == 2)
        #expect(
            (await source.currentState()).observation?.balance.observedAt
                == firstDate
        )
        #expect(await source.publicationCount == 2)
    }

    @Test
    func repeatedManualOperationsHaveExactWriteAndPublicationCounts() async throws {
        let directory = temporaryDirectory("repeated")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let clock = DebugDateClock(Date(timeIntervalSince1970: 1_800_000_000))
        let source = ManualWorkBuddyAvailabilitySource(
            store: store,
            now: { clock.value }
        )
        #expect((await source.load()).lifecycle == .unconfigured)

        for index in 0..<20 {
            clock.value = clock.value.addingTimeInterval(60)
            let next = try observation(
                remaining: Int64(4_000 - index),
                used: Int64(index),
                at: clock.value
            )
            #expect(try await source.save(next))
            #expect((await source.currentState()).observation == next)
        }
        let confirmedValues = try #require(
            (await source.currentState()).observation
        )

        for _ in 0..<10 {
            clock.value = clock.value.addingTimeInterval(60)
            #expect(try await source.confirmUnchanged(at: clock.value))
            let current = try #require(
                (await source.currentState()).observation
            )
            #expect(current.balance.remaining == confirmedValues.balance.remaining)
            #expect(current.balance.used == confirmedValues.balance.used)
            #expect(current.balance.total == confirmedValues.balance.total)
            #expect(current.balance.observedAt == clock.value)
        }

        for _ in 0..<5 {
            #expect(try await source.setEnabled(false))
            #expect((await source.currentState()).lifecycle == .disabled)
            #expect(try await source.setEnabled(true))
            #expect((await source.currentState()).lifecycle == .manualConfirmed)
        }

        for index in 0..<5 {
            #expect(try await source.clear())
            #expect((await source.currentState()).observation == nil)
            clock.value = clock.value.addingTimeInterval(60)
            let next = try observation(
                remaining: Int64(3_000 - index),
                used: Int64(1_000 + index),
                at: clock.value
            )
            #expect(try await source.save(next))
            #expect((await source.currentState()).observation == next)
        }

        #expect(await store.writeCount == 50)
        #expect(await source.publicationCount == 51)
        let fileURL = await store.fileURL
        let backupURL = await store.backupURL
        for url in [fileURL, backupURL] {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect((attributes[.size] as? NSNumber)?.intValue ?? .max <= 8_192)
        }
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        #expect(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
                == 0o700
        )
    }

    @Test
    func invalidInputAndPersistenceRecoveryMatrixFailsClosed() async throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let invalidDrafts: [WorkBuddyManualDraft] = [
            .init(remainingText: "", companionField: .none),
            .init(remainingText: "-1", companionField: .none),
            .init(remainingText: "1.5", companionField: .none),
            .init(
                remainingText: "9223372036854775808",
                companionField: .none
            ),
            .init(
                remainingText: "1",
                companionField: .total,
                companionText: "0"
            ),
            .init(
                remainingText: "2",
                companionField: .total,
                companionText: "1"
            ),
            .init(
                remainingText: "0",
                companionField: .usedAndTotal,
                companionText: "2",
                explicitTotalText: "1"
            ),
            .init(
                remainingText: "1",
                companionField: .usedAndTotal,
                companionText: "2",
                explicitTotalText: "4"
            ),
            .init(
                remainingText: "1",
                companionField: .none,
                includesExpiry: true,
                expiry: confirmedAt
            )
        ]
        for draft in invalidDrafts {
            #expect(throws: WorkBuddyManualValidationError.self) {
                try draft.validated(at: confirmedAt)
            }
        }

        let directory = temporaryDirectory("faults")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("manual.json")
        let store = WorkBuddyManualAvailabilityStore(fileURL: fileURL)
        let record = WorkBuddyManualPersistenceRecord(
            enabled: true,
            observation: try observation(
                remaining: 3_600,
                used: 400,
                at: confirmedAt
            )
        )
        #expect(try await store.save(record))
        let validData = try await store.encodedData(for: record)
        let backupURL = await store.backupURL

        try Data("corrupt".utf8).write(to: fileURL, options: .atomic)
        #expect(await store.load() == .valid(record))
        try validData.prefix(12).write(to: fileURL, options: .atomic)
        #expect(await store.load() == .valid(record))

        var future = try #require(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        future["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
            .write(to: fileURL, options: .atomic)
        #expect(await store.load() == .invalid(.unsupportedSchema))

        let invalidPool = Data(
            String(decoding: validData, as: UTF8.self)
                .replacingOccurrences(
                    of: "buddyAI.sharedCredits",
                    with: "other.pool"
                )
                .utf8
        )
        try invalidPool.write(to: fileURL, options: .atomic)
        try invalidPool.write(to: backupURL, options: .atomic)
        #expect(await store.load() == .invalid(.corruptPersistence))

        try Data("{}".utf8).write(to: fileURL, options: .atomic)
        try Data("{".utf8).write(to: backupURL, options: .atomic)
        #expect(await store.load() == .invalid(.corruptPersistence))

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.removeItem(at: backupURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        #expect(await store.load() == .invalid(.corruptPersistence))
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.removeItem(at: backupURL)

        #expect(try await store.save(record))
        #expect(await store.load() == .valid(record))
        for url in [fileURL, backupURL] {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test
    func tenRelaunchesPreserveManualValuesAndLifecycle() async throws {
        let directory = temporaryDirectory("relaunch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("manual.json")
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = try observation(
            remaining: 3_600,
            used: 400,
            at: confirmedAt,
            expiry: confirmedAt.addingTimeInterval(86_400)
        )
        let initial = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(fileURL: fileURL)
        )
        #expect(try await initial.save(expected))

        for _ in 0..<10 {
            let relaunched = ManualWorkBuddyAvailabilitySource(
                store: WorkBuddyManualAvailabilityStore(fileURL: fileURL)
            )
            let state = await relaunched.load()
            #expect(state.lifecycle == .manualConfirmed)
            #expect(state.enabled)
            #expect(state.observation == expected)
        }

        let disabledSource = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(fileURL: fileURL)
        )
        #expect(try await disabledSource.setEnabled(false))
        let disabledRelaunch = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(fileURL: fileURL)
        )
        #expect((await disabledRelaunch.load()).lifecycle == .disabled)

        #expect(try await disabledRelaunch.clear())
        let emptyRelaunch = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(fileURL: fileURL)
        )
        #expect((await emptyRelaunch.load()).lifecycle == .unconfigured)
    }

    @Test @MainActor
    func sharedRefreshUsesOnlyCodexAndLeavesWorkBuddyUntouched() async throws {
        let directory = temporaryDirectory("shared-refresh")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let source = ManualWorkBuddyAvailabilitySource(store: persistence)
        let workBuddy = WorkBuddyAvailabilityConnector(source: source)
        let codex = DebugPrimaryConnector()
        let registry = try AgentConnectorRegistry(connectors: [codex, workBuddy])
        let suiteName = "uma-m2wdbg-refresh-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: codex.id,
            consentDefaults: defaults
        )

        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let manual = try observation(
            remaining: 3_600,
            used: 400,
            at: confirmedAt
        )
        #expect(try await source.save(manual))
        await waitUntil {
            store.presentationCards.map(\.id)
                == ["codex.local", "workbuddy.manualAvailability"]
        }

        let writes = await persistence.writeCount
        let publications = await source.publicationCount
        let initialRefreshes = await codex.refreshCount
        for _ in 0..<20 {
            await store.refresh()
        }

        #expect(await codex.refreshCount - initialRefreshes == 20)
        #expect(await persistence.writeCount == writes)
        #expect(await source.publicationCount == publications)
        #expect(
            (await source.currentState()).observation?.balance.observedAt
                == confirmedAt
        )
        #expect(
            store.presentationCards.map(\.id)
                == ["codex.local", "workbuddy.manualAvailability"]
        )
        #expect(
            store.assistantPresentationCards.map(\.id)
                == ["codex.local", "workbuddy.manualAvailability"]
        )
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func staleEditedSettingsDraftCannotOverwriteANewerSavedRecord() async throws {
        let directory = temporaryDirectory("stale-draft")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(
                fileURL: directory.appendingPathComponent("manual.json")
            )
        )
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try observation(remaining: 3_600, used: 400, at: firstDate)
        let newer = try observation(
            remaining: 3_000,
            used: 1_000,
            at: firstDate.addingTimeInterval(60)
        )
        #expect(try await source.save(first))

        let model = WorkBuddySettingsModel(source: source, now: {
            firstDate.addingTimeInterval(120)
        })
        model.start()
        await waitUntil { model.savedObservation == first }

        model.draft.remainingText = "3500"
        model.draft.companionField = .used
        model.draft.companionText = "500"

        #expect(try await source.save(newer))
        await waitUntil { model.savedObservation == newer }
        model.save()
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect((await source.currentState()).observation == newer)
        #expect(model.validationError == .staleDraft)
    }

    private func observation(
        remaining: Int64,
        used: Int64?,
        at date: Date,
        scope: WorkBuddyManualScope = .personalShared,
        tier: WorkBuddyPlanTier = .standard,
        expiry: Date? = nil
    ) throws -> WorkBuddyManualObservation {
        var draft = WorkBuddyManualDraft(
            scope: scope,
            tier: tier,
            remainingText: String(remaining),
            companionField: used == nil ? .none : .used,
            companionText: used.map(String.init) ?? "",
            includesExpiry: expiry != nil,
            expiry: expiry ?? date.addingTimeInterval(86_400)
        )
        if used == nil {
            draft.companionField = .none
        }
        return try draft.validated(at: date)
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "uma-m2wdbg-\(suffix)-\(UUID().uuidString)",
                isDirectory: true
            )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }
}

private final class DebugDateClock: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

private actor DebugPrimaryConnector: AgentUsageConnector {
    nonisolated let id = AgentConnectorID(rawValue: "codex.local")!
    nonisolated let descriptor: AgentConnectorDescriptor
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private(set) var refreshCount = 0
    private(set) var performCount = 0

    init() {
        descriptor = AgentConnectorDescriptor(
            id: id,
            providerName: "Codex",
            officialSource: "synthetic test connector",
            sourceTier: .officialLocalService,
            sourceVersion: "1",
            supportedScopes: [.account],
            capabilities: [.connect, .rateLimits, .accountUsage],
            configurationRequirements: [],
            privacyAllowlist: [],
            supportsRestore: false,
            supportsUninstall: false,
            unsupportedFields: []
        )!
    }

    func probe() async -> AgentConnectorProbe {
        .init(state: .ready, safeFailure: nil)
    }

    func start() async {
        continuation?.yield(snapshot())
    }

    func refresh() async {
        refreshCount += 1
        continuation?.yield(snapshot())
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        await refresh()
    }

    func perform(_ command: AgentConnectorCommand) async {
        performCount += 1
        continuation?.yield(snapshot())
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        snapshot()
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot())
        }
    }

    private func snapshot() -> AgentUsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentUsageSnapshot(
            id: id,
            providerName: "Codex",
            state: .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: now,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "seven-day",
                            kind: .sevenDay,
                            usedPercent: 56,
                            isUnlimited: false,
                            resetsAt: now.addingTimeInterval(86_400)
                        )
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.rateLimits, .accountUsage],
            safeFailure: nil
        )
    }
}
