import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Factorium V2 local draft privacy")
@MainActor
struct FactoriumV2DraftPrivacyTests {
    @Test func currentDefaultsCatalogScopedModelChoicesAndEffortLabelsAreAccurate() throws {
        let currentCatalog = try ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.latestCatalogRevision)
        let historicalCatalog = try ThreadOSSettingsCodec.loadCatalog(revision: "sol-luna-20260922.1")
        #expect(FactoriumV2SettingsDraft.defaultRoles[.leader]?.preserve == false)
        #expect(FactoriumV2SettingsDraft.defaultRoles[.leader]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(FactoriumV2SettingsDraft.defaultRoles[.qa]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(!FactoriumV2SettingsDraft.availableModels(catalog: currentCatalog).contains("gpt-6-sol"))
        #expect(FactoriumV2SettingsDraft.availableModels(catalog: currentCatalog).contains("gpt-6.1-sol"))
        #expect(FactoriumV2SettingsDraft.availableModels(catalog: historicalCatalog).contains("gpt-6-sol"))
        #expect(!FactoriumV2SettingsDraft.availableModels(catalog: historicalCatalog).contains("gpt-6.1-sol"))
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("low", language: .english) == "Light")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("medium", language: .english) == "Medium")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("high", language: .english) == "High")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("xhigh", language: .english) == "Extra High")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("low", language: .simplifiedChinese) == "轻量")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("medium", language: .simplifiedChinese) == "中等")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("high", language: .simplifiedChinese) == "高")
        #expect(FactoriumV2SettingsDraft.effortDisplayLabel("xhigh", language: .simplifiedChinese) == "极高")
        #expect(FactoriumV2SettingsDraft.conversionPreview(language: .english).contains("unless Preserve is explicitly selected"))
        #expect(FactoriumV2SettingsDraft.conversionPreview(language: .simplifiedChinese).contains("除非明确选择保留"))
    }

    @Test func openingSelectedProjectMigratesOnlyLeaderAndQAAndKeepsRecoverableSnapshot() throws {
        let preferences = ApplicationPreferences.inMemory()
        var alpha = FactoriumV2SettingsDraft(project: "MIGRATE_ALPHA", catalogRevision: "sol-luna-20260922.1", id: "cfg-migrate-alpha")
        alpha.setSelection(.init(model: "gpt-6-sol", effort: "low", speed: "standard"), for: .leader)
        alpha.setSelection(.init(model: "gpt-6-sol", effort: "xhigh", speed: "standard"), for: .qa)
        let originalWorkers = alpha.coderWorkers
        var beta = FactoriumV2SettingsDraft(project: "MIGRATE_BETA", catalogRevision: ThreadOSSettingsCodec.latestCatalogRevision, id: "cfg-migrate-beta")
        beta.setSelection(.init(model: "gpt-6-luna", effort: "medium", speed: "standard"), for: .qa)
        ThreadOSSettingsPreferences.saveFactoriumV2(alpha, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2(beta, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject("MIGRATE_ALPHA", to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.draft.roles[.leader]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(form.draft.roles[.leader]?.preserve == false)
        #expect(form.draft.roles[.qa]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(form.draft.coderWorkers == originalWorkers)
        #expect(form.draft.revision == alpha.revision + 1)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: "MIGRATE_ALPHA", from: preferences) == alpha)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "MIGRATE_BETA", from: preferences) == beta)
        #expect(form.message.contains("migrated to GPT-6.1 Sol / High"))
        #expect(FactoriumV2FormState(preferences: preferences).message.isEmpty)

        let reopened = FactoriumV2FormState(preferences: preferences)
        #expect(reopened.draft == form.draft)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: "MIGRATE_ALPHA", from: preferences).count == 1)
    }

    @Test func currentCatalogLeaderPreserveAndRetainedModelSurviveReopening() throws {
        let preferences = ApplicationPreferences.inMemory()
        var draft = FactoriumV2SettingsDraft(project: "PRESERVE_CURRENT", id: "cfg-preserve-current")
        draft.roles[.leader] = .init(preserve: true, selection: .init(model: "gpt-6-astra", effort: "high", speed: "standard"))
        draft.roles[.qa] = .init(selection: .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)

        let opened = FactoriumV2FormState(preferences: preferences, language: .simplifiedChinese)
        #expect(opened.draft == draft)
        #expect(opened.message.isEmpty)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: draft.project, from: preferences).isEmpty)
        let reopened = FactoriumV2FormState(preferences: preferences)
        #expect(reopened.draft == draft)

        draft.roles[.leader] = .init(preserve: true, selection: .init(model: "gpt-6-sol", effort: "medium", speed: "standard"))
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        let preserveWithLegacyRetained = FactoriumV2FormState(preferences: preferences)
        #expect(preserveWithLegacyRetained.draft == draft)
        #expect(preserveWithLegacyRetained.draft.roles[.leader]?.preserve == true)
    }

    @Test func migrationAtRevisionLimitUsesNewIdentityAndPreservesOriginalDraft() throws {
        let preferences = ApplicationPreferences.inMemory()
        var source = FactoriumV2SettingsDraft(project: "MIGRATE_LIMIT", catalogRevision: "sol-luna-20260922.1", id: "cfg-limit-old", revision: 1_000_000)
        source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .leader)
        source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .qa)
        ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences, language: .simplifiedChinese)
        #expect(form.draft.id != source.id)
        #expect(form.draft.revision == 1)
        #expect(form.draft.catalogRevision == ThreadOSSettingsCodec.latestCatalogRevision)
        #expect(form.draft.roles[.leader]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)
        #expect(form.message.contains("新的请求标识"))
        #expect(try form.generatedRequest().settingsLine.contains("\"rev\":1"))
        #expect(FactoriumV2FormState(preferences: preferences).draft == form.draft)
    }

    @Test func currentCatalogSubmissionRejectsRetiredSolChildrenInEverySlotStateButKeepsHistory() throws {
        for enabled in [true, false] {
            var draft = FactoriumV2SettingsDraft(project: "CHILD_RETIRED_\(enabled ? "ON" : "OFF")")
            draft.coderWorkers[0].enabled = enabled
            draft.setSlotInheritance(false, at: 0, for: .coder)
            draft.setSlotSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), at: 0, for: .coder)
            #expect(throws: FactoriumV2SettingsError.invalidSelection) { try draft.canonicalRequest() }
        }

        var inheritedParent = FactoriumV2SettingsDraft(project: "CHILD_RETIRED_PARENT")
        inheritedParent.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .coder)
        #expect(throws: FactoriumV2SettingsError.invalidSelection) { try inheritedParent.canonicalRequest() }

        var luna = FactoriumV2SettingsDraft(project: "CHILD_LUNA_CONTROLS")
        luna.setSlotInheritance(true, at: 0, for: .coder)
        luna.setSlotSelection(.init(model: "gpt-6-luna", effort: "xhigh", speed: "standard"), at: 1, for: .coder)
        #expect(try luna.canonicalRequest().contains("gpt-6-luna"))

        var historicalRoles = FactoriumV2SettingsDraft.defaultRoles
        historicalRoles[.leader] = .init(selection: .init(model: "gpt-6-sol", effort: "high", speed: "standard"))
        historicalRoles[.qa] = .init(selection: .init(model: "gpt-6-sol", effort: "medium", speed: "standard"))
        var historical = FactoriumV2SettingsDraft(project: "CHILD_HISTORY", catalogRevision: "sol-luna-20260922.1", roles: historicalRoles)
        historical.setSlotInheritance(false, at: 0, for: .coder)
        historical.setSlotSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), at: 0, for: .coder)
        #expect(try historical.canonicalRequest().contains("\"gpt-6-sol\""))
    }

    @Test func multipleRetiredWorkerSelectionsCanBeRepairedOneAtATimeAcrossReopen() throws {
        let preferences = ApplicationPreferences.inMemory()
        var source = FactoriumV2SettingsDraft(project: "REPAIR_MULTI_SLOTS", catalogRevision: "sol-luna-20260922.1", id: "cfg-repair-multi-slots")
        source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .leader)
        source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .qa)
        for index in [0, 1] {
            source.setSlotInheritance(false, at: index, for: .coder)
            source.setSlotSelection(.init(model: "gpt-6-sol", effort: index == 0 ? "xhigh" : "medium", speed: "standard"), at: index, for: .coder)
        }
        source.coderWorkers[1].enabled = false
        #expect(try source.canonicalRequest().contains("\"gpt-6-sol\""))
        ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences, language: .english)
        let migrated = form.draft
        #expect(migrated.catalogRevision == ThreadOSSettingsCodec.latestCatalogRevision)
        #expect(migrated.roles[.leader]?.selection.model == "gpt-6.1-sol")
        #expect(migrated.coderWorkers[0].selection.model == "gpt-6-sol")
        #expect(!migrated.coderWorkers[1].enabled && migrated.coderWorkers[1].selection.model == "gpt-6-sol")
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)

        let blockedClipboard = TestClipboard()
        #expect(form.generateAndCopy(to: blockedClipboard, language: .english) == nil)
        #expect(blockedClipboard.value == nil)
        #expect(form.copiedRevision == nil && form.copiedArtifactSHA256 == nil)

        form.selectSlotModel("gpt-6-astra", at: 0, for: .coder)
        let firstRepair = form.draft
        #expect(firstRepair.revision == migrated.revision + 1)
        #expect(firstRepair.coderWorkers[0].selection.model == "gpt-6-astra")
        #expect(firstRepair.coderWorkers[0].selection.effort.isEmpty)
        #expect(firstRepair.coderWorkers[1] == migrated.coderWorkers[1])
        #expect(form.message.contains("Saved selections still need resolution"))
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: source.project, from: preferences) == firstRepair)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)
        #expect(throws: FactoriumV2SettingsError.invalidSelection) { try form.generatedRequest() }
        let stillBlocked = TestClipboard()
        #expect(form.generateAndCopy(to: stillBlocked, language: .english) == nil)
        #expect(stillBlocked.value == nil)

        let reopened = FactoriumV2FormState(preferences: preferences, language: .english)
        #expect(reopened.draft == firstRepair)
        #expect(reopened.message.contains("Saved selections still need resolution"))
        reopened.selectRoleModel("unknown-retired-injection", role: .repair)
        #expect(reopened.draft == firstRepair)
        #expect(reopened.message.contains("Choose a supported model and effort"))

        // This is the same public edit shape used by the effort picker binding.
        reopened.edit(allowIncompleteEffort: true) { candidate in
            var selection = candidate.workers(for: .coder)[0].selection
            selection.effort = "high"
            candidate.setSlotSelection(selection, at: 0, for: .coder)
        }
        let effortRepair = reopened.draft
        #expect(effortRepair.revision == firstRepair.revision + 1)
        #expect(effortRepair.coderWorkers[0].selection == .init(model: "gpt-6-astra", effort: "high", speed: "standard"))
        #expect(effortRepair.coderWorkers[1] == firstRepair.coderWorkers[1])
        #expect(!effortRepair.isLocallyValid)
        #expect(throws: FactoriumV2SettingsError.invalidSelection) { try reopened.generatedRequest() }
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: source.project, from: preferences) == effortRepair)

        let reopenedAfterEffort = FactoriumV2FormState(preferences: preferences, language: .english)
        #expect(reopenedAfterEffort.draft == effortRepair)
        reopenedAfterEffort.selectSlotModel("gpt-6-luna", at: 1, for: .coder)
        #expect(reopenedAfterEffort.draft.revision == effortRepair.revision + 1)
        #expect(reopenedAfterEffort.draft.coderWorkers[0] == effortRepair.coderWorkers[0])
        #expect(reopenedAfterEffort.draft.coderWorkers[1].selection.model == "gpt-6-luna")
        #expect(reopenedAfterEffort.draft.isLocallyValid)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)
        let allowedClipboard = TestClipboard()
        let generated = try #require(reopenedAfterEffort.generateAndCopy(to: allowedClipboard, language: .english))
        #expect(allowedClipboard.value == generated.text)
        #expect(reopenedAfterEffort.copiedRevision == reopenedAfterEffort.draft.revision)
    }

    @Test func incompleteDraftPersistenceRejectsMalformedStructure() throws {
        let preferences = ApplicationPreferences.inMemory()
        let valid = FactoriumV2SettingsDraft(project: "REPAIR_STRUCTURE", id: "cfg-repair-structure")
        ThreadOSSettingsPreferences.saveFactoriumV2(valid, to: preferences)

        var malformed = valid
        malformed.roles.removeValue(forKey: .qa)
        #expect(!malformed.isPersistableForLocalRepair)
        ThreadOSSettingsPreferences.saveFactoriumV2(malformed, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2LegacySnapshot(malformed, to: preferences)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: valid.project, from: preferences) == valid)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: valid.project, from: preferences) == nil)

        malformed = valid
        malformed.coderWorkers.removeLast()
        #expect(!malformed.isPersistableForLocalRepair)
        ThreadOSSettingsPreferences.saveFactoriumV2(malformed, to: preferences)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: valid.project, from: preferences) == valid)
    }

    @Test func partialRepairAtRevisionLimitRotatesIdentityAndRemainsEditableAfterReopen() throws {
        for sourceRevision in [999_998, 999_999] {
            let preferences = ApplicationPreferences.inMemory()
            var source = FactoriumV2SettingsDraft(
                project: "REPAIR_REVISION_LIMIT_\(sourceRevision)",
                catalogRevision: "sol-luna-20260922.1",
                id: "cfg-repair-revision-limit-\(sourceRevision)",
                revision: sourceRevision
            )
            source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .leader)
            source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .qa)
            source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .coder)
            source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .reviewer)
            for index in 0..<3 {
                source.setSlotInheritance(true, at: index, for: .coder)
                source.setSlotInheritance(true, at: index, for: .reviewer)
            }
            ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
            ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

            let form = FactoriumV2FormState(preferences: preferences)
            let migrationUsedNewIdentity = sourceRevision == 999_999
            #expect(form.draft.revision == (migrationUsedNewIdentity ? 1 : 999_999))
            #expect((form.draft.id != source.id) == migrationUsedNewIdentity)
            let oldIdentity = form.draft.id
            form.selectRoleModel("gpt-6-luna", role: .coder)
            let partial = form.draft
            #expect((partial.id != oldIdentity) == !migrationUsedNewIdentity)
            #expect(partial.revision == (migrationUsedNewIdentity ? 2 : 1))
            #expect(partial.roles[.reviewer]?.selection.model == "gpt-6-sol")
            #expect(form.message.contains(migrationUsedNewIdentity ? "Saved selections still need resolution" : "new request identity"))
            #expect(throws: FactoriumV2SettingsError.invalidSelection) { try form.generatedRequest() }
            #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: source.project, from: preferences) == partial)

            let reopened = FactoriumV2FormState(preferences: preferences)
            #expect(reopened.draft == partial)
            reopened.selectRoleModel("gpt-6-luna", role: .reviewer)
            #expect(reopened.draft.revision == (migrationUsedNewIdentity ? 3 : 2))
            #expect(reopened.draft.isLocallyValid)
            #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)
            #expect(try reopened.generatedRequest().settingsLine.contains("gpt-6-luna"))
        }
    }

    @Test func migrationPreservesExactStructurallySoundDraftWithInvalidEffortForRecovery() throws {
        for invalidRole in [FactoriumV2Role.leader, .qa] {
            let preferences = ApplicationPreferences.inMemory()
            var source = FactoriumV2SettingsDraft(
                project: "RECOVER_INVALID_EFFORT_\(invalidRole.rawValue.uppercased())",
                catalogRevision: "sol-luna-20260922.1",
                id: "cfg-recover-invalid-effort-\(invalidRole.rawValue)"
            )
            source.setSelection(.init(model: "gpt-6-sol", effort: "none", speed: "standard"), for: invalidRole)
            source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: invalidRole == .leader ? .qa : .leader)
            source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .coder)
            #expect(source.isPersistableForLocalRepair)
            #expect(!source.isLocallyValid)
            ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
            ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

            let migrated = FactoriumV2FormState(preferences: preferences)
            #expect(migrated.draft.roles[.leader]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
            #expect(migrated.draft.roles[.qa]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
            #expect(migrated.draft.roles[.coder]?.selection.model == "gpt-6-sol")
            #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)

            let reopened = FactoriumV2FormState(preferences: preferences)
            #expect(reopened.draft == migrated.draft)
            #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)
            #expect(throws: FactoriumV2SettingsError.invalidSelection) { try reopened.generatedRequest() }
        }
    }

    @Test func terminalInvalidCustomChildrenRemainRepairableAcrossEnabledStates() throws {
        for enabled in [true, false] {
            for revision in [999_999, 1_000_000] {
                let preferences = ApplicationPreferences.inMemory()
                var source = FactoriumV2SettingsDraft(project: "REPAIR_CHILD_LIMIT_\(enabled ? "ON" : "OFF")_\(revision)", id: "cfg-repair-child-limit-\(enabled ? "on" : "off")-\(revision)", revision: revision)
                for index in [0, 1] {
                    source.setSlotInheritance(false, at: index, for: .coder)
                    source.setSlotSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), at: index, for: .coder)
                }
                source.coderWorkers[1].enabled = enabled
                ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
                ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

                let form = FactoriumV2FormState(preferences: preferences)
                let oldID = form.draft.id
                form.selectSlotModel("gpt-6-luna", at: 0, for: .coder)
                #expect(form.draft.id != oldID)
                #expect(form.draft.revision == 1)
                #expect(form.draft.coderWorkers[1].enabled == enabled)
                #expect(form.draft.coderWorkers[1].selection.model == "gpt-6-sol")
                #expect(throws: FactoriumV2SettingsError.invalidSelection) { try form.generatedRequest() }

                let reopened = FactoriumV2FormState(preferences: preferences)
                #expect(reopened.draft == form.draft)
                reopened.selectSlotModel("gpt-6-luna", at: 1, for: .coder)
                #expect(reopened.draft.revision == 2)
                #expect(reopened.draft.isLocallyValid)
                #expect(reopened.draft.coderWorkers[1].enabled == enabled)
            }
        }
    }

    @Test func terminalInvalidInheritedParentsRemainRepairableOneAtATime() throws {
        for revision in [999_999, 1_000_000] {
            let preferences = ApplicationPreferences.inMemory()
            var source = FactoriumV2SettingsDraft(project: "REPAIR_PARENT_LIMIT_\(revision)", id: "cfg-repair-parent-limit-\(revision)", revision: revision)
            source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .coder)
            source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .reviewer)
            for index in 0..<3 {
                source.setSlotInheritance(true, at: index, for: .coder)
                source.setSlotInheritance(true, at: index, for: .reviewer)
            }
            ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
            ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

            let form = FactoriumV2FormState(preferences: preferences)
            let oldID = form.draft.id
            form.selectRoleModel("gpt-6-luna", role: .coder)
            let partial = form.draft
            #expect(partial.id != oldID && partial.revision == 1)
            #expect(partial.roles[.reviewer]?.selection.model == "gpt-6-sol")
            #expect(partial.coderWorkers.map(\.inherits) == [true, true, true])
            #expect(throws: FactoriumV2SettingsError.invalidSelection) { try form.generatedRequest() }

            let reopened = FactoriumV2FormState(preferences: preferences)
            #expect(reopened.draft == partial)
            reopened.selectRoleModel("gpt-6-luna", role: .reviewer)
            #expect(reopened.draft.revision == 2)
            #expect(reopened.draft.isLocallyValid)
            #expect(reopened.draft.reviewerWorkers.map(\.inherits) == [true, true, true])
        }
    }

    @Test func inheritedWorkerCanBeRepairedWhileAnotherRetiredSlotRemains() throws {
        let preferences = ApplicationPreferences.inMemory()
        var source = FactoriumV2SettingsDraft(project: "REPAIR_WITH_INHERITANCE", catalogRevision: "sol-luna-20260922.1", id: "cfg-repair-inheritance")
        source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .leader)
        source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .qa)
        for index in [0, 1] {
            source.setSlotInheritance(false, at: index, for: .coder)
            source.setSlotSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), at: index, for: .coder)
        }
        ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        let migrated = form.draft
        form.edit { $0.setSlotInheritance(true, at: 0, for: .coder) }
        let partial = form.draft
        #expect(partial.revision == migrated.revision + 1)
        #expect(partial.coderWorkers[0].inherits)
        #expect(partial.coderWorkers[0].selection.model == "gpt-6-sol")
        #expect(partial.coderWorkers[1] == migrated.coderWorkers[1])
        #expect(!partial.isLocallyValid)
        #expect(form.message.contains("request generation stays blocked"))
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: source.project, from: preferences) == partial)
        #expect(throws: FactoriumV2SettingsError.invalidSelection) { try form.generatedRequest() }
    }

    @Test func multipleRetiredInheritedParentsCanBeRepairedOneAtATimeAcrossReopen() throws {
        let preferences = ApplicationPreferences.inMemory()
        var source = FactoriumV2SettingsDraft(project: "REPAIR_MULTI_PARENTS", catalogRevision: "sol-luna-20260922.1", id: "cfg-repair-multi-parents")
        source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .leader)
        source.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .qa)
        source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .coder)
        source.setSelection(.init(model: "gpt-6-sol", effort: "medium", speed: "standard"), for: .reviewer)
        for index in 0..<3 {
            source.setSlotInheritance(true, at: index, for: .coder)
            source.setSlotInheritance(true, at: index, for: .reviewer)
        }
        #expect(try source.canonicalRequest().contains("\"gpt-6-sol\""))
        ThreadOSSettingsPreferences.saveFactoriumV2(source, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(source.project, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences, language: .simplifiedChinese)
        let migrated = form.draft
        form.selectRoleModel("gpt-6-luna", role: .coder)
        let firstRepair = form.draft
        #expect(firstRepair.revision == migrated.revision + 1)
        #expect(firstRepair.roles[.coder]?.selection.model == "gpt-6-luna")
        #expect(firstRepair.roles[.reviewer]?.selection.model == "gpt-6-sol")
        #expect(firstRepair.coderWorkers.map(\.inherits) == [true, true, true])
        #expect(firstRepair.reviewerWorkers.map(\.inherits) == [true, true, true])
        #expect(form.message.contains("已保存的选择仍需处理"))
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: source.project, from: preferences) == firstRepair)

        let reopened = FactoriumV2FormState(preferences: preferences, language: .simplifiedChinese)
        #expect(reopened.draft == firstRepair)
        #expect(reopened.message.contains("已保存的选择仍需处理"))
        reopened.selectRoleModel("gpt-6-luna", role: .reviewer)
        #expect(reopened.draft.revision == firstRepair.revision + 1)
        #expect(reopened.draft.roles[.reviewer]?.selection.model == "gpt-6-luna")
        #expect(reopened.draft.coderWorkers.map(\.inherits) == [true, true, true])
        #expect(reopened.draft.reviewerWorkers.map(\.inherits) == [true, true, true])
        #expect(reopened.draft.isLocallyValid)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: source.project, from: preferences) == source)
        #expect(try reopened.generatedRequest().settingsLine.contains("\"gpt-6-luna\""))
    }

    @Test func outgoingArtifactIsOneCanonicalConfigurationLine() throws {
        let preferences = ApplicationPreferences.inMemory()
        let draft = FactoriumV2SettingsDraft(project: "RESET_ALPHA", id: "cfg-reset-alpha")
        #expect(FactoriumV2Role.allCases.allSatisfy { draft.roles[$0]?.selection.speed == "standard" })
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)

        let first = try form.generatedRequest()
        let second = try form.generatedRequest()
        #expect(first == second)
        #expect(first.settingsLine.hasPrefix("TOSCFG/2 "))
        #expect(first.text == first.settingsLine && first.artifactSHA256.count == 64)

        form.reportCopy(first, success: true, language: .english)
        #expect(form.copiedArtifactSHA256 == first.artifactSHA256)
        form.edit { $0.roles[.repair]?.selection.effort = "low" }
        #expect(form.copiedRevision == nil)
        form.reportCopy(first, success: true, language: .english)
        #expect(form.copiedRevision == nil && form.message.contains("stale"))
        #expect(form.copiedArtifactSHA256 == nil)
    }

    @Test func staleOrForgedSingleLineCopyIsRejected() throws {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "COMPOSE_ALPHA", id: "cfg-compose-alpha"), to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        let first = try form.generatedRequest()
        form.reportCopy(first, success: true, language: .english)
        form.reportCopy(first, success: true, language: .english)
        #expect(form.copiedArtifactSHA256 == first.artifactSHA256)
        let forged = FactoriumV2GeneratedRequest(settingsLine: first.settingsLine, text: first.text + "\nforged", artifactSHA256: first.artifactSHA256)
        form.reportCopy(forged, success: true, language: .english)
        #expect(form.copiedRevision == nil)
        #expect(form.draft.revision == 1)
    }

    @Test func generatedV2RequestUsesOnlyTheConfigurationAllowlistAndCopyStateIsLocal() throws {
        let preferences = ApplicationPreferences.inMemory()
        var draft = FactoriumV2SettingsDraft(project: "PRIVACY_ALPHA", id: "cfg-privacy-alpha")
        draft.setSlotInheritance(false, at: 0, for: .coder)
        var slot = draft.coderWorkers[0].selection
        slot.effort = "high"
        draft.setSlotSelection(slot, at: 0, for: .coder)
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        let request = try form.generatedRequest()
        #expect(request.text.hasPrefix("TOSCFG/2 "))
        let data = try #require(request.text.dropFirst("TOSCFG/2 ".count).data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["apply", "cat", "id", "p", "preset", "rev", "roles", "workers"])
        #expect(object["p"] as? String == "PRIVACY_ALPHA")
        #expect(object["id"] as? String == "cfg-privacy-alpha")

        let roles = try #require(object["roles"] as? [String: [String: Any]])
        #expect(Set(roles.keys) == Set(FactoriumV2Role.allCases.map(\.rawValue)))
        for role in FactoriumV2Role.allCases.map(\.rawValue) {
            #expect(Set(try #require(roles[role]).keys) == ["model", "effort", "speed"])
        }
        let workers = try #require(object["workers"] as? [String: [[String: Any]]])
        #expect(Set(workers.keys) == ["coder", "reviewer"])
        for slots in workers.values {
            #expect(slots.count == 3)
            #expect(slots.allSatisfy { Set($0.keys) == ["enabled", "model", "effort", "speed"] })
        }
        for excluded in ["rawAcknowledgement", "receipt", "copiedRevision", "message", "selectedProject", "expandedGroups"] {
            #expect(!request.text.contains(excluded))
        }

        form.reportCopy(success: true, language: .english)
        #expect(form.copiedRevision == form.draft.revision)
        form.rawAcknowledgement = "TOSACK/2 local-only-test-input"
        form.edit { $0.roles[.repair]?.selection.effort = "low" }
        #expect(form.copiedRevision == nil && form.rawAcknowledgement.isEmpty && form.receipt == nil)
        let saved = try #require(ThreadOSSettingsPreferences.loadFactoriumV2(project: "PRIVACY_ALPHA", from: preferences))
        #expect(saved == form.draft)
        #expect(try saved.canonicalRequest().contains("TOSACK/2") == false)
    }

    @Test func v2DraftsAndWorkerExpansionRemainPerProjectAcrossSwitchAndReopen() throws {
        let preferences = ApplicationPreferences.inMemory()
        let alpha = FactoriumV2SettingsDraft(project: "PRIVACY_ALPHA", id: "cfg-privacy-alpha")
        var beta = FactoriumV2SettingsDraft(project: "PRIVACY_BETA", id: "cfg-privacy-beta")
        beta.setSlotInheritance(false, at: 1, for: .reviewer)
        var betaSlot = beta.reviewerWorkers[1].selection
        betaSlot.effort = "medium"
        beta.setSlotSelection(betaSlot, at: 1, for: .reviewer)
        ThreadOSSettingsPreferences.saveFactoriumV2(alpha, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2(beta, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups([.coder], project: "PRIVACY_ALPHA", to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups([.repair, .reviewer], project: "PRIVACY_BETA", to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject("PRIVACY_ALPHA", to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.selectedProject == "PRIVACY_ALPHA" && form.draft == alpha)
        form.edit { $0.roles[.coder]?.selection.effort = "low" }
        let editedAlpha = form.draft
        #expect(editedAlpha.revision == alpha.revision + 1)

        form.select(project: "PRIVACY_BETA")
        #expect(form.draft == beta)
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "PRIVACY_ALPHA", from: preferences) == [.coder])
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "PRIVACY_BETA", from: preferences) == [.repair, .reviewer])
        form.select(project: "PRIVACY_ALPHA")
        #expect(form.draft == editedAlpha)

        let reopened = FactoriumV2FormState(preferences: preferences)
        #expect(reopened.selectedProject == "PRIVACY_ALPHA" && reopened.draft == editedAlpha)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "PRIVACY_BETA", from: preferences) == beta)
    }

    @MainActor private final class TestClipboard: ThreadOSSettingsClipboard {
        var value: String?
        func write(_ string: String) -> Bool { value = string; return true }
    }
}
