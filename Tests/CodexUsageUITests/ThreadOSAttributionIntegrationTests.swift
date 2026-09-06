import Foundation
import Testing
@testable import CodexUsageUI

@Suite(.timeLimit(.minutes(1)))
struct ThreadOSAttributionIntegrationTests {
    @Test
    func identicalThreadAndTurnLabelsAcrossRootsDoNotRebind() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = sessionData(thread: "shared-thread", turns: [("shared-turn", 10, 30)])
        let intervals = try #require(candidateIntervals(in: data).first)
        let rows = [
            row(root: "a", task: "TU3", role: "Coder", interval: intervals),
            row(root: "b", task: "TU9", role: "Reviewer", interval: intervals)
        ]

        let snapshot = try read(data: data, in: directory, analytics: analytics(rows))
        #expect(snapshot.apiEquivalentCost?.observedTokens == 30)
        #expect(snapshot.threadOSAnalytics?.rows.isEmpty == true)
    }

    @Test
    func attributesTwoTurnsOfOnePersistentRoleSeparately() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = sessionData(thread: "persistent-role-thread", turns: [("turn-one", 10, 30), ("turn-two", 35, 65)])
        let intervals = candidateIntervals(in: data)
        #expect(intervals.count == 2)

        let snapshot = try read(data: data, in: directory, analytics: .init(
            sourceStatus: .available,
            rows: [
                row(root: "main", task: "TU3", role: "Coder", interval: intervals[0]),
                row(root: "main", task: "TU3", role: "Coder", interval: intervals[1])
            ],
            unavailableCount: 2,
            capturedAt: now
        ))
        let attributed = try #require(snapshot.threadOSAnalytics?.rows)
        let coverage = try #require(snapshot.threadOSAnalytics?.localLedgerCoverage)
        #expect(attributed.count == 2)
        #expect(Set(attributed.compactMap(\.intervalID)).count == 2)
        #expect(Set(attributed.compactMap(\.totalTokens)) == [20, 30])
        #expect(attributed.allSatisfy { $0.localRole == "Coder" && $0.taskID == "TU3" })
        #expect(coverage.knownLocalTokens == 65)
        #expect(coverage.matchedLocalTokens == 50)
        #expect(coverage.localUnassignedTokens == 15)
        #expect(snapshot.threadOSAnalytics?.unavailableCount == 2)
    }

    @Test
    func deduplicatesALogicalSessionPresentInLiveAndArchiveRoots() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = directory.appendingPathComponent("sessions", isDirectory: true)
        let archive = directory.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let data = sessionData(thread: "duplicate-thread", turns: [("duplicate-turn", 10, 30)])
        try data.write(to: live.appendingPathComponent("same.jsonl"))
        try data.write(to: archive.appendingPathComponent("same.jsonl"))

        let snapshot = CodexLocalActivityReader(
            sessionRoots: [live, archive],
            ledgerURL: directory.appendingPathComponent("ledger.json")
        ).read(now: now, threadOSAnalytics: .sourceGap(now: now))
        #expect(snapshot.discoveredFileCount == 2)
        #expect(snapshot.readableFileCount == 1)
        #expect(snapshot.tasks.count == 1)
        #expect(snapshot.apiEquivalentCost?.observedTokens == 30)
    }

    @Test
    func movesAndRenamesNativeSessionAcrossRootsWithoutRebillingThenAcceptsNewerHighWater() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = directory.appendingPathComponent("sessions", isDirectory: true)
        let archive = directory.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let ledger = directory.appendingPathComponent("ledger.json")
        let liveFile = live.appendingPathComponent("live-name.jsonl")
        try sessionData(thread: "persistent-native-session", turns: [("turn-one", 10, 30)]).write(to: liveFile)

        let initial = CodexLocalActivityReader(sessionRoots: [live, archive], ledgerURL: ledger)
            .read(now: now, threadOSAnalytics: .sourceGap(now: now))
        #expect(initial.apiEquivalentCost?.observedTokens == 30)

        let archivedFile = archive.appendingPathComponent("renamed-after-archive.jsonl")
        try FileManager.default.moveItem(at: liveFile, to: archivedFile)
        let moved = CodexLocalActivityReader(sessionRoots: [live, archive], ledgerURL: ledger)
            .read(now: now.addingTimeInterval(60), threadOSAnalytics: .sourceGap(now: now))
        #expect(moved.apiEquivalentCost?.observedTokens == 30)

        try sessionData(thread: "persistent-native-session", turns: [("turn-one", 10, 50)]).write(to: archivedFile)
        let restarted = CodexLocalActivityReader(sessionRoots: [live, archive], ledgerURL: ledger)
            .read(now: now.addingTimeInterval(120), threadOSAnalytics: .sourceGap(now: now))
        #expect(restarted.apiEquivalentCost?.observedTokens == 50)
    }

    @Test
    func adoptsExactTU2PathCheckpointBeforeArchiveWithoutRebillingHistoricalUsage() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = directory.appendingPathComponent("sessions", isDirectory: true)
        let archive = directory.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        let ledgerURL = directory.appendingPathComponent("ledger.json")
        let liveFile = live.appendingPathComponent("tu2-name.jsonl")
        try sessionData(thread: "tu2-native-session", turns: [("turn-one", 10, 30)]).write(to: liveFile)
        let legacyPathID = SessionMetadataScanner.stableID(
            for: liveFile,
            beneath: live,
            rootCategory: .init(root: live, ordinal: 0)
        )
        let historicalPrice = try #require(APIModelPrice.price(for: "gpt-5.6-terra", observedAt: now))
        let oldFormatLedger = """
        {"schemaVersion":1,"checkpoints":{"\(legacyPathID)":{"model":"gpt-5.6-terra","counts":{"inputTokens":30,"cachedInputTokens":0,"outputTokens":0,"totalTokens":30},"inheritedBaseline":null}},"records":[{"sessionID":"\(legacyPathID)","usageDay":"2026-09-06","model":"gpt-5.6-terra","counts":{"inputTokens":30,"cachedInputTokens":0,"outputTokens":0,"totalTokens":30},"price":{"version":"\(historicalPrice.version)","displayName":"\(historicalPrice.displayName)","inputPerMillion":\(historicalPrice.inputPerMillion),"cachedInputPerMillion":\(historicalPrice.cachedInputPerMillion),"outputPerMillion":\(historicalPrice.outputPerMillion)},"attributionIntervalID":null,"usd":0.000075}]}
        """
        try Data(oldFormatLedger.utf8).write(to: ledgerURL)

        let unchanged = CodexLocalActivityReader(sessionRoots: [live, archive], ledgerURL: ledgerURL)
            .read(now: now, threadOSAnalytics: .sourceGap(now: now))
        #expect(unchanged.apiEquivalentCost?.observedTokens == 30)
        let afterAdoption = try APICostLedgerStore(url: ledgerURL).load()
        #expect(afterAdoption.records.count == 1)
        #expect(afterAdoption.records[0].sessionID == legacyPathID)
        #expect(afterAdoption.records[0].model == "gpt-5.6-terra")
        #expect(afterAdoption.records[0].price == historicalPrice)

        try sessionData(thread: "tu2-native-session", turns: [("turn-one", 10, 50)]).write(to: liveFile)
        let higher = CodexLocalActivityReader(sessionRoots: [live, archive], ledgerURL: ledgerURL)
            .read(now: now.addingTimeInterval(60), threadOSAnalytics: .sourceGap(now: now))
        #expect(higher.apiEquivalentCost?.observedTokens == 50)
        let afterHigher = try APICostLedgerStore(url: ledgerURL).load()
        #expect(afterHigher.records.count == 2)
        #expect(afterHigher.records.first?.counts.totalTokens == 30)
        #expect(afterHigher.records.first?.price == historicalPrice)
        #expect(afterHigher.records.map { $0.counts.totalTokens }.sorted() == [20, 30])

        let archivedFile = archive.appendingPathComponent("renamed-after-tu2-upgrade.jsonl")
        try FileManager.default.moveItem(at: liveFile, to: archivedFile)
        let restarted = CodexLocalActivityReader(sessionRoots: [live, archive], ledgerURL: ledgerURL)
            .read(now: now.addingTimeInterval(120), threadOSAnalytics: .sourceGap(now: now))
        #expect(restarted.apiEquivalentCost?.observedTokens == 50)
        let afterRestart = try APICostLedgerStore(url: ledgerURL).load()
        #expect(afterRestart.records.count == 2)
        #expect(afterRestart.records.map { $0.counts.totalTokens }.sorted() == [20, 30])
    }

    @Test
    func retainsLegacyIntervalsWithUnknownPriceAndWithholdsUnavailableSource() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyData = sessionData(thread: "legacy-thread", turns: [("legacy-turn", 10, 30)], timestamp: 100)
        let interval = try #require(candidateIntervals(in: legacyData).first)
        let legacy = try read(data: legacyData, in: directory, analytics: analytics([
            row(root: "main", task: "TU3", role: "Coder", interval: interval)
        ]))
        let legacyRow = try #require(legacy.threadOSAnalytics?.rows.first)
        #expect(legacyRow.totalTokens == 20)
        #expect(legacyRow.isPriceKnown == false)
        #expect(legacyRow.apiEquivalentUSD == nil)
        #expect(legacy.apiEquivalentCost?.pricedTokens == 0)

        let unavailableDirectory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: unavailableDirectory) }
        let unavailable = try read(data: sessionData(thread: "unavailable-thread", turns: [("unavailable-turn", 10, 30)]), in: unavailableDirectory, analytics: .init(sourceStatus: .unavailable, rows: [], unavailableCount: 1, capturedAt: now))
        #expect(unavailable.threadOSAnalytics?.sourceStatus == .unavailable)
        #expect(unavailable.threadOSAnalytics?.rows.isEmpty == true)
    }

    @Test
    func lateAttributionOnlyConsumesTheNewHighWaterWindowAcrossSourceStatesAndRestart() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("late-attribution.jsonl")
        let ledgerURL = directory.appendingPathComponent("ledger.json")
        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)

        // The first 20-token interval is admitted only as aggregate usage.
        // A later COMPLETE export must never retroactively spend a new delta
        // to label those already-accounted tokens.
        try sessionData(thread: "late-thread", turn: "late-turn", checkpointTotals: [10, 30]).write(to: session)
        #expect(reader.read(now: now, threadOSAnalytics: .sourceGap(now: now)).apiEquivalentCost?.observedTokens == 30)

        try sessionData(thread: "late-thread", turn: "late-turn", checkpointTotals: [10, 30, 40]).write(to: session)
        let truncated = ThreadOSUsageAnalytics(sourceStatus: .truncated, rows: [], unavailableCount: 0, capturedAt: now)
        #expect(reader.read(now: now.addingTimeInterval(60), threadOSAnalytics: truncated).apiEquivalentCost?.observedTokens == 40)

        let completedData = sessionData(thread: "late-thread", turn: "late-turn", checkpointTotals: [10, 30, 40, 50])
        try completedData.write(to: session)
        let candidates = candidateIntervals(in: completedData).filter { $0.disposition == .candidate }
        let finalCandidate = try #require(candidates.last)
        let complete = analytics([row(root: "late", task: "TU3", role: "Coder", interval: finalCandidate)])
        let completed = reader.read(now: now.addingTimeInterval(120), threadOSAnalytics: complete)
        #expect(completed.apiEquivalentCost?.observedTokens == 50)
        #expect(completed.threadOSAnalytics?.rows.map(\.totalTokens) == [10])
        #expect(completed.threadOSAnalytics?.localLedgerCoverage?.knownLocalTokens == 50)
        #expect(completed.threadOSAnalytics?.localLedgerCoverage?.matchedLocalTokens == 10)
        #expect(completed.threadOSAnalytics?.localLedgerCoverage?.localUnassignedTokens == 40)

        let afterComplete = try APICostLedgerStore(url: ledgerURL).load()
        // Aggregate records are canonically coalesced by the immutable ledger
        // key (session, day, model, and price); their source-state segments
        // do not create new accounting identities. The 40 aggregate tokens
        // therefore remain one record, while only the exact 40->50 window is
        // attributed.
        #expect(afterComplete.records.map { $0.counts.totalTokens }.sorted() == [10, 40])
        let attributed = afterComplete.records.filter { $0.projection != nil }
        let aggregate = afterComplete.records.filter { $0.projection == nil }
        #expect(attributed.map { $0.counts.totalTokens } == [10])
        #expect(aggregate.map { $0.counts.totalTokens } == [40])
        let frozenPrices = afterComplete.records.map(\.price)

        // Repeated reads and a fresh reader retain the frozen aggregate lanes
        // and do not add another partition for the historical 10->30 or
        // 30->40 intervals.
        _ = reader.read(now: now.addingTimeInterval(180), threadOSAnalytics: complete)
        let restarted = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)
            .read(now: now.addingTimeInterval(240), threadOSAnalytics: complete)
        #expect(restarted.apiEquivalentCost?.observedTokens == 50)
        let afterRestart = try APICostLedgerStore(url: ledgerURL).load()
        #expect(afterRestart.records.map { $0.counts.totalTokens }.sorted() == [10, 40])
        #expect(afterRestart.records.map(\.price) == frozenPrices)
    }

    @Test
    func preservesPerIntervalModelSnapshotsAcrossStagedReadsAndRestart() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("two-models.jsonl")
        let ledgerURL = directory.appendingPathComponent("ledger.json")
        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)

        // The first complete turn is priced with its own validated Terra
        // snapshot; it must never be repriced when the next turn changes the
        // trailing summary model.
        let initialData = sessionData(
            thread: "two-model-thread",
            modeledTurns: [("turn-terra", "gpt-5.6-terra", 10, 30)]
        )
        try initialData.write(to: session)
        let firstInterval = try #require(candidateIntervals(in: initialData).first)
        let first = reader.read(
            now: now,
            threadOSAnalytics: analytics([
                row(root: "main", task: "TASK-A", role: "DEVELOPMENT", interval: firstInterval)
            ])
        )
        #expect(first.apiEquivalentCost?.observedTokens == 30)

        // The second valid interval intentionally uses a model without a
        // catalog price. Its 30-token projection remains observable but
        // unpriced, while the five-token counter gap crossing models is an
        // explicit UNKNOWN aggregate lane rather than a last-model estimate.
        let stagedData = sessionData(
            thread: "two-model-thread",
            modeledTurns: [
                ("turn-terra", "gpt-5.6-terra", 10, 30),
                ("turn-unpriced", "model-without-catalog-price", 35, 65)
            ]
        )
        try stagedData.write(to: session)
        let intervals = candidateIntervals(in: stagedData)
        #expect(intervals.count == 2)
        let stagedAnalytics = analytics([
            row(root: "main", task: "TASK-A", role: "DEVELOPMENT", interval: intervals[0]),
            row(root: "main", task: "TASK-B", role: "QA", interval: intervals[1])
        ])
        let unavailableLedgerURL = directory.appendingPathComponent("unavailable-ledger.json")
        let unavailableReader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: unavailableLedgerURL)
        try initialData.write(to: session)
        _ = unavailableReader.read(now: now.addingTimeInterval(58), threadOSAnalytics: .sourceGap(now: now))
        try stagedData.write(to: session)
        _ = unavailableReader.read(now: now.addingTimeInterval(59), threadOSAnalytics: .sourceGap(now: now))
        let unavailableLedger = try APICostLedgerStore(url: unavailableLedgerURL).load()
        #expect(unavailableLedger.records.filter { $0.model == "gpt-5.6-terra" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 30)
        #expect(unavailableLedger.records.filter { $0.model == "model-without-catalog-price" }.isEmpty)
        #expect(unavailableLedger.records.filter { $0.model == "UNKNOWN" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 35)
        #expect(unavailableLedger.records.first { $0.model == "UNKNOWN" }?.price == nil)
        try stagedData.write(to: session)
        let coldLedgerURL = directory.appendingPathComponent("cold-ledger.json")
        let cold = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: coldLedgerURL)
            .read(now: now.addingTimeInterval(59), threadOSAnalytics: stagedAnalytics)
        let coldRows = try #require(cold.threadOSAnalytics?.rows)
        #expect(Set(coldRows.map(\.taskID)) == ["TASK-A", "TASK-B"])
        #expect(cold.apiEquivalentCost?.observedTokens == 65)
        #expect(coldRows.first { $0.taskID == "TASK-A" }?.model == "gpt-5.6-terra")
        #expect(coldRows.first { $0.taskID == "TASK-A" }?.isPriceKnown == true)
        #expect(coldRows.first { $0.taskID == "TASK-B" }?.model == "model-without-catalog-price")
        #expect(coldRows.first { $0.taskID == "TASK-B" }?.isPriceKnown == false)
        let coldLedger = try APICostLedgerStore(url: coldLedgerURL).load()
        #expect(coldLedger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 65)
        #expect(coldLedger.records.filter { $0.model == "gpt-5.6-terra" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 20)
        #expect(coldLedger.records.filter { $0.model == "model-without-catalog-price" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 30)
        #expect(coldLedger.records.filter { $0.model == "UNKNOWN" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 15)
        #expect(coldLedger.records.first { $0.model == "UNKNOWN" }?.price == nil)
        let staged = reader.read(now: now.addingTimeInterval(60), threadOSAnalytics: stagedAnalytics)
        #expect(staged.apiEquivalentCost?.observedTokens == 65)
        let stagedRows = try #require(staged.threadOSAnalytics?.rows)
        #expect(stagedRows.count == 2)
        #expect(Set(stagedRows.map(\.taskID)) == ["TASK-A", "TASK-B"])
        #expect(Set(stagedRows.map(\.localRole)) == ["DEVELOPMENT", "QA"])
        #expect(stagedRows.first { $0.taskID == "TASK-A" }?.model == "gpt-5.6-terra")
        #expect(stagedRows.first { $0.taskID == "TASK-A" }?.isPriceKnown == true)
        #expect(stagedRows.first { $0.taskID == "TASK-B" }?.model == "model-without-catalog-price")
        #expect(stagedRows.first { $0.taskID == "TASK-B" }?.isPriceKnown == false)

        let ledger = try APICostLedgerStore(url: ledgerURL).load()
        #expect(ledger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 65)
        #expect(ledger.records.filter { $0.model == "gpt-5.6-terra" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 30)
        #expect(ledger.records.filter { $0.model == "model-without-catalog-price" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 30)
        #expect(ledger.records.filter { $0.model == "UNKNOWN" }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 5)
        #expect(ledger.records.first { $0.model == "UNKNOWN" }?.price == nil)
        let frozenRecords = ledger.records.map {
            "\($0.model):\($0.counts.totalTokens):\($0.price?.version ?? "UNKNOWN"):\($0.usd)"
        }.sorted()

        let restarted = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)
            .read(now: now.addingTimeInterval(120), threadOSAnalytics: stagedAnalytics)
        #expect(restarted.apiEquivalentCost?.observedTokens == 65)
        let afterRestart = try APICostLedgerStore(url: ledgerURL).load()
        #expect(afterRestart.records.map {
            "\($0.model):\($0.counts.totalTokens):\($0.price?.version ?? "UNKNOWN"):\($0.usd)"
        }.sorted() == frozenRecords)
    }

    @Test
    func retainsKnownSourceGapModelsAcrossAnAtoBtoAAppend() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("transition.jsonl")
        let initial = sessionData(
            thread: "transition-thread",
            modeledTurns: [("turn-a-initial", "gpt-5.6-terra", 10, 30)]
        )
        let append = Data(("\n" + [
            #"{"type":"task_started","timestamp":1784332901,"payload":{"turn_id":"turn-b-first-only"}}"#,
            #"{"type":"turn_context","timestamp":1784332902,"payload":{"turn_id":"turn-b-first-only","model":"gpt-5.6-sol"}}"#,
            tokenLine(1_784_332_903, total: 35),
            #"{"type":"task_complete","timestamp":1784332904,"payload":{"turn_id":"turn-b-first-only"}}"#,
            #"{"type":"task_started","timestamp":1784332905,"payload":{"turn_id":"turn-a-return"}}"#,
            #"{"type":"turn_context","timestamp":1784332906,"payload":{"turn_id":"turn-a-return","model":"gpt-5.6-terra"}}"#,
            tokenLine(1_784_332_907, total: 40),
            tokenLine(1_784_332_908, total: 70),
            #"{"type":"task_complete","timestamp":1784332909,"payload":{"turn_id":"turn-a-return"}}"#
        ].joined(separator: "\n") + "\n").utf8)

        let availableLedgerURL = directory.appendingPathComponent("available-ledger.json")
        let availableReader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: availableLedgerURL)
        try initial.write(to: session)
        let initialAvailable = availableReader.read(now: now, threadOSAnalytics: .sourceGap(now: now))
        #expect(initialAvailable.apiEquivalentCost?.observedTokens == 30)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: append)
        }
        let returnedInterval = try #require(candidateIntervals(in: try Data(contentsOf: session)).last)
        let available = availableReader.read(
            now: now.addingTimeInterval(60),
            threadOSAnalytics: analytics([row(root: "main", task: "TASK-A-RETURN", role: "QA", interval: returnedInterval)])
        )
        #expect(available.apiEquivalentCost?.observedTokens == 70)
        let availableLedger = try APICostLedgerStore(url: availableLedgerURL).load()
        #expect(availableLedger.records.first { $0.attributionIntervalID == nil && $0.model == "gpt-5.6-terra" }?.counts.totalTokens == 30)
        #expect(availableLedger.records.first { $0.attributionIntervalID != nil && $0.model == "gpt-5.6-terra" }?.counts.totalTokens == 30)
        #expect(availableLedger.records.first { $0.model == "UNKNOWN" }?.counts.totalTokens == 10)
        #expect(availableLedger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 70)

        let unavailableLedgerURL = directory.appendingPathComponent("unavailable-ledger.json")
        let unavailableReader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: unavailableLedgerURL)
        try initial.write(to: session)
        let initialUnavailable = unavailableReader.read(now: now.addingTimeInterval(120), threadOSAnalytics: .sourceGap(now: now))
        #expect(initialUnavailable.apiEquivalentCost?.observedTokens == 30)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: append)
        }
        let unavailable = unavailableReader.read(now: now.addingTimeInterval(180), threadOSAnalytics: .sourceGap(now: now))
        #expect(unavailable.apiEquivalentCost?.observedTokens == 70)
        let unavailableLedger = try APICostLedgerStore(url: unavailableLedgerURL).load()
        #expect(unavailableLedger.records.first { $0.attributionIntervalID == nil && $0.model == "gpt-5.6-terra" }?.counts.totalTokens == 30)
        #expect(unavailableLedger.records.first { $0.model == "UNKNOWN" }?.counts.totalTokens == 40)
        #expect(unavailableLedger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 70)
    }

    @Test
    func defersAnUnterminatedAppendFromAggregateAccountingUntilItsNewline() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("unterminated.jsonl")
        let ledgerURL = directory.appendingPathComponent("ledger.json")
        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)
        let initialData = Data([
            #"{"type":"session_meta","payload":{"id":"unterminated-thread"}}"#,
            #"{"type":"task_started","timestamp":1784332801,"payload":{"turn_id":"unterminated-turn"}}"#,
            #"{"type":"turn_context","timestamp":1784332802,"payload":{"turn_id":"unterminated-turn","model":"gpt-5.6-terra"}}"#,
            tokenLine(1_784_332_803, total: 10),
            tokenLine(1_784_332_804, total: 30)
        ].joined(separator: "\n").utf8)
        try initialData.write(to: session)

        let initial = reader.read(now: now, threadOSAnalytics: .sourceGap(now: now))
        #expect(initial.apiEquivalentCost?.observedTokens == 30)
        let firstCommittedData = Data((String(decoding: initialData, as: UTF8.self)
            + "\n" + tokenLine(1_784_332_900, total: 40) + "\n").utf8)
        let firstInterval = try #require(candidateIntervals(in: firstCommittedData).last)
        let mixedAppend = Data(("\n" + tokenLine(1_784_332_900, total: 40) + "\n" + tokenLine(1_784_332_901, total: 50)).utf8)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: mixedAppend)
        }
        let firstAnalytics = analytics([
            row(root: "main", task: "TASK-UNTERMINATED", role: "QA", interval: firstInterval)
        ])
        let atBoundary = reader.read(now: now.addingTimeInterval(60), threadOSAnalytics: firstAnalytics)
        #expect(atBoundary.apiEquivalentCost?.observedTokens == 40)
        let afterFirstBoundary = try APICostLedgerStore(url: ledgerURL).load()
        let firstAttributed = try #require(afterFirstBoundary.records.first { $0.attributionIntervalID != nil })
        #expect(firstAttributed.counts.totalTokens == 10)
        #expect(firstAttributed.model == "gpt-5.6-terra")
        #expect(firstAttributed.price != nil)

        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
        }
        let finalData = try Data(contentsOf: session)
        let secondInterval = try #require(candidateIntervals(in: finalData).last)
        #expect(secondInterval.turnDigest == firstInterval.turnDigest)
        let matchingAnalytics = analytics([
            // Both deltas belong to the same active local turn. The producer
            // contract permits exactly one canonical row for its thread/turn;
            // duplicate task rows deliberately fail closed rather than
            // splitting one turn into fabricated producer identities.
            row(root: "main", task: "TASK-UNTERMINATED", role: "QA", interval: firstInterval)
        ])
        let completed = reader.read(now: now.addingTimeInterval(120), threadOSAnalytics: matchingAnalytics)
        #expect(completed.apiEquivalentCost?.observedTokens == 50)
        let afterSecondBoundary = try APICostLedgerStore(url: ledgerURL).load()
        let attributedAfterSecondBoundary = afterSecondBoundary.records.filter { $0.attributionIntervalID != nil }
        #expect(attributedAfterSecondBoundary.count == 2)
        #expect(attributedAfterSecondBoundary.map { $0.counts.totalTokens }.sorted() == [10, 10])
        #expect(attributedAfterSecondBoundary.allSatisfy { $0.model == "gpt-5.6-terra" && $0.price != nil })
        let frozenAttributionPrices = attributedAfterSecondBoundary.map {
            "\($0.attributionIntervalID ?? "aggregate"):\($0.price?.version ?? "UNKNOWN"):\($0.usd)"
        }.sorted()
        let repeated = reader.read(now: now.addingTimeInterval(180), threadOSAnalytics: matchingAnalytics)
        #expect(repeated.apiEquivalentCost?.observedTokens == 50)
        let restarted = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)
            .read(now: now.addingTimeInterval(240), threadOSAnalytics: matchingAnalytics)
        #expect(restarted.apiEquivalentCost?.observedTokens == 50)
        let ledger = try APICostLedgerStore(url: ledgerURL).load()
        #expect(ledger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 50)
        #expect(ledger.records.filter { $0.attributionIntervalID != nil }.map {
            "\($0.attributionIntervalID ?? "aggregate"):\($0.price?.version ?? "UNKNOWN"):\($0.usd)"
        }.sorted() == frozenAttributionPrices)
    }

    @Test
    func syntheticChangedPathCacheReuseProbePrintsReproducibleMeasurements() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        var session = sessions.appendingPathComponent("cache-probe.jsonl")
        let input = sessionData(thread: "cache-probe", turns: [("cache-turn", 10, 30)])
        try input.write(to: session)
        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: directory.appendingPathComponent("ledger.json"))
        let started = Date()
        let first = reader.read(now: now, threadOSAnalytics: .sourceGap(now: now))
        let initialMetadata = try session.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let initialSignature = "\(try #require(initialMetadata.fileSize)):\(try #require(initialMetadata.contentModificationDate))"
        // `now` is deliberately unchanged: cache reuse is filesystem-signature
        // driven, never a clock/TTL behavior.
        let second = reader.read(now: now, threadOSAnalytics: .sourceGap(now: now))
        try sessionData(thread: "cache-probe", turns: [("cache-turn", 10, 50)]).write(to: session)
        let initialMTime = try #require(initialMetadata.contentModificationDate)
        let distinctMTime = initialMTime.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: distinctMTime], ofItemAtPath: session.path)
        try? session.removeCachedResourceValue(forKey: .fileSizeKey)
        try? session.removeCachedResourceValue(forKey: .contentModificationDateKey)
        let changedMetadata = try session.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let changedSignature = "\(try #require(changedMetadata.fileSize)):\(try #require(changedMetadata.contentModificationDate))"
        let changed = reader.read(now: now, threadOSAnalytics: .sourceGap(now: now))

        // The existing observer route supplies the same narrow changed-path
        // invalidation without a root scan or a time advance.
        try sessionData(thread: "cache-probe", turns: [("cache-turn", 10, 70)]).write(to: session)
        try FileManager.default.setAttributes([.modificationDate: distinctMTime.addingTimeInterval(60)], ofItemAtPath: session.path)
        let observer = reader.makeLocalActivityObserver(onChange: {})
        observer.notifyForTesting(.file(session))
        let observerChanged = reader.read(now: now, threadOSAnalytics: .sourceGap(now: now))
        let elapsedMilliseconds = Int(Date().timeIntervalSince(started) * 1_000)
        print("TOSUMA_CACHE_REUSE_PROBE input_bytes=\(input.count) read_count=4 initial_signature=\(initialSignature) changed_signature=\(changedSignature) elapsed_ms=\(elapsedMilliseconds)")
        #expect(first.apiEquivalentCost?.observedTokens == 30)
        #expect(second.apiEquivalentCost?.observedTokens == 30)
        #expect(changed.apiEquivalentCost?.observedTokens == 50)
        #expect(initialSignature != changedSignature)
        #expect(observerChanged.apiEquivalentCost?.observedTokens == 70)
    }

    @Test
    func boundedContinuationAdmitsOnlyCompleteContiguousAppendsPastPrefixAndTailBoundaries() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("continued.jsonl")
        let ledgerURL = directory.appendingPathComponent("ledger.json")
        // This first observation crosses the former 1,024-record prefix but
        // remains just below the one-megabyte continuation admission limit.
        let initial = paddedSessionData(thread: "continued-thread", turn: "continued-turn", through: 1_024, padding: 820)
        #expect(initial.count < 1_048_576)
        try initial.write(to: session)
        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledgerURL)
        #expect(reader.read(now: now, threadOSAnalytics: .sourceGap(now: now)).apiEquivalentCost?.observedTokens == 1_024)

        // An interrupted frame must not advance either the continuation offset
        // or attribution. Completing exactly that frame is a contiguous append
        // and moves the file through the old one-megabyte tail boundary.
        let appended = paddedTokenLine(now: 1_784_335_000, total: 1_025, padding: 120_000)
        let partial = Data(("\n" + appended).utf8)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: partial)
        }
        #expect(reader.read(now: now.addingTimeInterval(1), threadOSAnalytics: .sourceGap(now: now)).apiEquivalentCost?.observedTokens == 1_024)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
        }
        #expect((try session.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 1_048_576)
        let finalInterval = try #require(candidateIntervals(in: try Data(contentsOf: session)).last)
        let completed = reader.read(
            now: now.addingTimeInterval(2),
            threadOSAnalytics: analytics([row(root: "continued", task: "TU3", role: "Coder", interval: finalInterval)])
        )
        #expect(completed.apiEquivalentCost?.observedTokens == 1_025)
        #expect(completed.threadOSAnalytics?.rows.map(\.totalTokens) == [1])

        // A replacement with a new prefix cannot prove continuity. It is read
        // cold and therefore cannot reuse the previously admitted interval.
        let beforeReplacement = try APICostLedgerStore(url: ledgerURL).load().records
        try Data(repeating: 0x20, count: 1_048_600).write(to: session)
        _ = reader.read(now: now.addingTimeInterval(3), threadOSAnalytics: .sourceGap(now: now))
        let afterReplacement = try APICostLedgerStore(url: ledgerURL).load().records
        #expect(try canonicalLedgerRecords(afterReplacement) == canonicalLedgerRecords(beforeReplacement))
    }

    @Test
    func boundedContinuationProbeReportsConstantReadAndDecodeWorkAfterLargePrefix() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("growing.jsonl")
        let initial = paddedSessionData(thread: "growing-thread", turn: "growing-turn", through: 1_024, padding: 820)
        #expect(initial.count < 1_048_576)
        try initial.write(to: session)
        let initialRead = try #require(SessionMetadataScanner.readSummary(from: session, fileSize: initial.count))

        let fixedAppend = Data(("\n" + paddedTokenLine(now: 1_784_336_000, total: 1_025, padding: 120_000) + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: fixedAppend)
        }
        let finalSize = try #require(session.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let continued = try #require(SessionMetadataScanner.readAppendedSummary(
            from: session,
            fileSize: finalSize,
            previous: initialRead
        ))
        let maximumRead = 1_048_576 + fixedAppend.count + 2 * 64 * 1024
        let maximumDecoded = 1_048_576 + fixedAppend.count
        print("TOSUMA_CONTINUATION_IO_PROBE prefix_bytes=\(initial.count) append_bytes=\(fixedAppend.count) read_bytes=\(continued.bytesRead) decoded_bytes=\(continued.bytesDecoded)")
        #expect(continued.bytesRead <= maximumRead)
        #expect(continued.bytesDecoded <= maximumDecoded)
        #expect(continued.summary.totalTokens == 1_025)
    }

    @Test
    func continuationRejectsSameInodeHeaderRewriteOutsideBoundaryCheckpoint() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("rewritten-header.jsonl")
        let initial = paddedSessionData(thread: "trusted-thread", turn: "trusted-turn", through: 1_024, padding: 820)
        try initial.write(to: session)
        let initialRead = try #require(SessionMetadataScanner.readSummary(from: session, fileSize: initial.count))
        let identity = try #require(initialRead.fileIdentity)
        #expect(!initialRead.continuation!.contextWitnesses.isEmpty)

        let rewritten = String(decoding: initial, as: UTF8.self)
            .replacingOccurrences(of: "trusted-thread", with: "altered-thread")
        #expect(rewritten.utf8.count == initial.count)
        try Data(rewritten.utf8).write(to: session)
        if let handle = try? FileHandle(forWritingTo: session) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(("\n" + paddedTokenLine(now: 1_784_337_000, total: 1_025, padding: 120_000) + "\n").utf8))
        }
        let finalSize = try #require(session.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let currentIdentity = (try FileManager.default.attributesOfItem(atPath: session.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        #expect(currentIdentity == identity)
        #expect(SessionMetadataScanner.readAppendedSummary(from: session, fileSize: finalSize, previous: initialRead) == nil)
    }

    private let now = Date(timeIntervalSince1970: 1_784_332_800)

    @Test
    func hostileWireFieldsAreAbsentFromLocalLedgerAndSerializedSnapshot() throws {
        let plainLocal = String(decoding: sessionData(thread: "hostile-thread", turns: [("hostile-turn", 10, 20)]), as: UTF8.self)
        let data = Data(plainLocal
            .replacingOccurrences(of: #""id":"hostile-thread""#, with: #""id":"hostile-thread","prompt":"LOCAL_PRIVATE_PROMPT","account":"LOCAL_PRIVATE_ACCOUNT""#)
            .replacingOccurrences(of: #""model":"gpt-5.6-terra""#, with: #""model":"gpt-5.6-terra","tool_input":"LOCAL_PRIVATE_TOOL""#)
            .replacingOccurrences(of: #""type":"token_count""#, with: #""type":"token_count","body":"LOCAL_PRIVATE_BODY""#)
            .utf8)
        let interval = try #require(candidateIntervals(in: data).first)
        let thread = try #require(interval.nativeThreadDigest)
        let turn = try #require(interval.turnDigest)
        let wire = """
        {"schema":"threados.usage-attribution-export.v1","historical_only":true,"status":"COMPLETE","row_count":1,"unavailable_count":0,"rows":[{"schema":"threados.usage-attribution-wire.v1","status":"ELIGIBLE_HISTORICAL","observation":"validated historical journal observation","project_key":"TOSUMA","project_root_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","task_id":"TU3","local_role":"DEVELOPMENT","thread_digest":"\(thread)","turn_digest":"\(turn)","correlation_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","attempt_digest":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","destination_readback_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","acknowledgement_digest":"1111111111111111111111111111111111111111111111111111111111111111","message_digest":"2222222222222222222222222222222222222222222222222222222222222222","prompt":"PRIVATE_PROMPT","tool_input":"PRIVATE_TOOL","account":"PRIVATE_ACCOUNT","path":"/PRIVATE_PATH"}]}
        """
        let analytics = ThreadOSHistoricalAttributionDecoder.decode(Data(wire.utf8), now: now)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = try read(data: data, in: directory, analytics: analytics)

        let ledgerText = String(decoding: try Data(contentsOf: directory.appendingPathComponent("ledger.json")), as: UTF8.self)
        var usage = UsageSnapshot.empty(language: .english, now: now)
        usage.threadOSAnalytics = local.threadOSAnalytics
        let snapshotText = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        for secret in ["PRIVATE_PROMPT", "PRIVATE_TOOL", "PRIVATE_ACCOUNT", "PRIVATE_PATH", "LOCAL_PRIVATE_PROMPT", "LOCAL_PRIVATE_TOOL", "LOCAL_PRIVATE_ACCOUNT", "LOCAL_PRIVATE_BODY"] {
            #expect(!ledgerText.contains(secret))
            #expect(!snapshotText.contains(secret))
        }
        #expect(local.threadOSAnalytics?.rows.count == 1)
        #expect((local.apiEquivalentCost?.observedTokens ?? 0) > 0)
    }

    private func read(data: Data, in directory: URL, analytics: ThreadOSUsageAnalytics) throws -> CodexLocalActivitySnapshot {
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try data.write(to: sessions.appendingPathComponent("session.jsonl"))
        return CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: directory.appendingPathComponent("ledger.json")).read(now: now, threadOSAnalytics: analytics)
    }

    private func analytics(_ rows: [ThreadOSUsageAnalytics.Row]) -> ThreadOSUsageAnalytics {
        .init(sourceStatus: .available, rows: rows, unavailableCount: 0, capturedAt: now)
    }

    private func row(root: String, task: String, role: String, interval: ThreadOSLocalIntervalCandidate) -> ThreadOSUsageAnalytics.Row {
        .init(projectKey: "TOSUMA", projectRootDigest: String(repeating: root, count: 64).prefix(64).description, taskID: task, localRole: role, threadDigest: interval.nativeThreadDigest!, turnDigest: interval.turnDigest!, observation: "validated historical journal observation", waveID: nil)
    }

    private func candidateIntervals(in data: Data) -> [ThreadOSLocalIntervalCandidate] {
        ThreadOSLocalIntervalDecoder.decode(lines: data.split(separator: 0x0A).map(Data.init)).filter { $0.disposition == .candidate }
    }

    private func canonicalLedgerRecords(_ records: [APICostLedger.Record]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(records), as: UTF8.self)
    }

    private func sessionData(thread: String, turns: [(String, Int64, Int64)], timestamp: Int = 1_784_332_800) -> Data {
        var lines = [#"{"type":"session_meta","payload":{"id":"\#(thread)"}}"#]
        var time = timestamp
        for (turn, first, second) in turns {
            time += 1; lines.append(#"{"type":"task_started","timestamp":\#(time),"payload":{"turn_id":"\#(turn)"}}"#)
            time += 1; lines.append(#"{"type":"turn_context","timestamp":\#(time),"payload":{"turn_id":"\#(turn)","model":"gpt-5.6-terra"}}"#)
            time += 1; lines.append(tokenLine(time, total: first))
            time += 1; lines.append(tokenLine(time, total: second))
            time += 1; lines.append(#"{"type":"task_complete","timestamp":\#(time),"payload":{"turn_id":"\#(turn)"}}"#)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func sessionData(
        thread: String,
        modeledTurns: [(String, String, Int64, Int64)],
        timestamp: Int = 1_784_332_800
    ) -> Data {
        var lines = [#"{"type":"session_meta","payload":{"id":"\#(thread)"}}"#]
        var time = timestamp
        for (turn, model, first, second) in modeledTurns {
            time += 1; lines.append(#"{"type":"task_started","timestamp":\#(time),"payload":{"turn_id":"\#(turn)"}}"#)
            time += 1; lines.append(#"{"type":"turn_context","timestamp":\#(time),"payload":{"turn_id":"\#(turn)","model":"\#(model)"}}"#)
            time += 1; lines.append(tokenLine(time, total: first))
            time += 1; lines.append(tokenLine(time, total: second))
            time += 1; lines.append(#"{"type":"task_complete","timestamp":\#(time),"payload":{"turn_id":"\#(turn)"}}"#)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func sessionData(thread: String, turn: String, checkpointTotals: [Int64], timestamp: Int = 1_784_332_800) -> Data {
        var lines = [#"{"type":"session_meta","payload":{"id":"\#(thread)"}}"#]
        var time = timestamp
        time += 1; lines.append(#"{"type":"task_started","timestamp":\#(time),"payload":{"turn_id":"\#(turn)"}}"#)
        time += 1; lines.append(#"{"type":"turn_context","timestamp":\#(time),"payload":{"turn_id":"\#(turn)","model":"gpt-5.6-terra"}}"#)
        for total in checkpointTotals {
            time += 1; lines.append(tokenLine(time, total: total))
        }
        time += 1; lines.append(#"{"type":"task_complete","timestamp":\#(time),"payload":{"turn_id":"\#(turn)"}}"#)
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func tokenLine(_ timestamp: Int, total: Int64) -> String {
        #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"output_tokens":0,"total_tokens":\#(total)}}}}"#
    }

    private func paddedSessionData(thread: String, turn: String, through total: Int64, padding: Int) -> Data {
        var lines = [#"{"type":"session_meta","payload":{"id":"\#(thread)"}}"#]
        lines.append(#"{"type":"task_started","timestamp":1784332801,"payload":{"turn_id":"\#(turn)"}}"#)
        lines.append(#"{"type":"turn_context","timestamp":1784332802,"payload":{"turn_id":"\#(turn)","model":"gpt-5.6-terra"}}"#)
        for value in 1...total {
            lines.append(paddedTokenLine(now: 1_784_332_802 + Int(value), total: value, padding: padding))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func paddedTokenLine(now: Int, total: Int64, padding: Int) -> String {
        #"{"type":"event_msg","timestamp":\#(now),"private":"\#(String(repeating: "x", count: padding))","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"output_tokens":0,"total_tokens":\#(total)}}}}"#
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("threados-attribution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
