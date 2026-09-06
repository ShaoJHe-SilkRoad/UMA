import Foundation
import Testing
@testable import CodexUsageUI

@MainActor struct ThreadOSSettingsSurfaceTests {
    @Test func preferencesRetainStableDraftIdentityAndConfiguration() {
        let preferences = ApplicationPreferences.inMemory()
        var draft = ThreadOSSettingsDraft(project: "TU1_FIXTURE", id: "cfg-001", revision: 1, preset: "custom", codingWorkers: 2, reviewWorkers: 4, tier: "priority", customRoles: customRoles)
        ThreadOSSettingsPreferences.save(draft, to: preferences)
        draft.changed()
        ThreadOSSettingsPreferences.save(draft, to: preferences)
        let reloaded = ThreadOSSettingsPreferences.load(from: preferences)
        #expect(reloaded.id == "cfg-001")
        #expect(reloaded.revision == 2)
        #expect(reloaded.project == "TU1_FIXTURE")
        #expect(reloaded.preset == "custom")
        #expect(reloaded.codingWorkers == 2 && reloaded.reviewWorkers == 4)
        #expect(reloaded.tier == "priority")
        #expect(reloaded.customRoles == customRoles)
    }

    @Test func malformedStoredDraftFallsBackWithoutClaimingConfiguredState() {
        let preferences = ApplicationPreferences.inMemory()
        let key = ApplicationPreferenceKey<Data?>(optionalData: "threados.settings.draft.v1")
        preferences.set(Data("not-json".utf8), for: key)
        let draft = ThreadOSSettingsPreferences.load(from: preferences)
        #expect(draft.project.isEmpty)
        #expect(draft.revision == 1)
        #expect(draft.preset == "astra-balanced")
    }

    @Test func invalidSavePreservesLastValidProjectDraft() {
        let preferences = ApplicationPreferences.inMemory()
        let valid = ThreadOSSettingsDraft(project: "TU1_FIXTURE", id: "cfg-001", revision: 1)
        ThreadOSSettingsPreferences.save(valid, to: preferences)
        var invalid = valid; invalid.revision = 0
        ThreadOSSettingsPreferences.save(invalid, to: preferences)
        #expect(ThreadOSSettingsPreferences.load(project: "TU1_FIXTURE", from: preferences) == valid)
    }

    @Test func customDefaultsIncludeEveryRoleAndCoderAutoOnlyForForeman() {
        #expect(Set(ThreadOSSettingsDraft.defaultCustomRoles.keys) == Set(ThreadOSRole.allCases))
        #expect(ThreadOSSettingsDraft.defaultCustomRoles[.foreman]?.model == "coder_auto")
        #expect(ThreadOSSettingsDraft.defaultCustomRoles[.codingWorker]?.model != "coder_auto")
    }

    @Test func formActionsCopyOnlyValidDraftsThroughInjectableClipboard() throws {
        let clipboard = TestClipboard()
        let draft = ThreadOSSettingsDraft(project: "TU1_FIXTURE", id: "cfg-001", revision: 1)
        try ThreadOSSettingsFormActions.copy(draft, to: clipboard)
        try ThreadOSSettingsFormActions.copy(draft, to: clipboard)
        #expect(clipboard.value?.hasPrefix("TOSCFG/1 ") == true)
        #expect(draft.revision == 1)
        #expect(throws: ThreadOSSettingsFormError.invalidDraft) {
            try ThreadOSSettingsFormActions.copy(.init(project: ""), to: clipboard)
        }
    }

    @Test func semanticEditsAdvanceExactlyOnceAndMaximumPreservesDraft() {
        var draft = ThreadOSSettingsDraft(project: "TU1_FIXTURE", id: "cfg-001", revision: 1_000_000)
        let original = draft
        #expect(!ThreadOSSettingsFormActions.edit(&draft) { $0.tier = "priority" })
        #expect(draft == original)
        draft.revision = 4
        #expect(ThreadOSSettingsFormActions.edit(&draft) { $0.tier = "priority" })
        #expect(draft.revision == 5)
        #expect(!ThreadOSSettingsFormActions.edit(&draft) { $0.tier = "priority" })
        #expect(draft.revision == 5)
    }

    @Test func sharedSemanticEditReportsNoopMaximumAndInvalidOutcomes() {
        var draft = ThreadOSSettingsDraft(project: "TU1_FIXTURE", id: "cfg-001", revision: 3)
        #expect(ThreadOSSettingsFormActions.semanticEdit(&draft) { $0.tier = "standard" } == .unchanged)
        #expect(ThreadOSSettingsFormActions.semanticEdit(&draft) { $0.id = "" } == .rejectedInvalidDraft)
        #expect(draft.revision == 3 && draft.id == "cfg-001")
        draft.revision = 1_000_000
        #expect(ThreadOSSettingsFormActions.semanticEdit(&draft) { $0.tier = "priority" } == .rejectedMaximumRevision)
        #expect(draft.tier == "standard")
    }

    @Test func actualFormStatePresentsAllNonConfigurationReceiptContainersAsLocalFacts() {
        let form = ThreadOSSettingsFormState(preferences: .inMemory())
        let containers: [(String, String)] = [
            ("{\"schema\":\"threados.settings-receipt.v1\",\"protocol\":\"TOSACK/1\",\"authority\":\"settings_do_not_grant_authority\",\"status\":\"mode_updated\",\"mode\":\"on\",\"effective_from\":\"observed\"}", "MODE_ON_OBSERVED_LOCAL_ONLY"), // fixture 17a
            ("{\"schema\":\"threados.settings-receipt.v1\",\"protocol\":\"TOSACK/1\",\"authority\":\"settings_do_not_grant_authority\",\"status\":\"mode_queued\",\"mode\":\"off\",\"effective_from\":\"idle\"}", "MODE_OFF_QUEUED_UNTIL_IDLE"),
            (receipt(status: "wave_started", fields: ["wave_id": "wave-1", "configured": validView]), "WAVE_STARTED_CONFIGURED_MODEL_UNOBSERVED"),
            ("{\"schema\":\"threados.settings-receipt.v1\",\"protocol\":\"TOSACK/1\",\"authority\":\"settings_do_not_grant_authority\",\"status\":\"wave_finished\",\"wave_id\":\"wave-1\",\"mode\":\"on\"}", "WAVE_FINISHED_LOCAL_ONLY"),
            (receipt(status: "status", fields: ["mode": "on", "pending_mode": NSNull(), "active": NSNull(), "pending": NSNull(), "running_wave": NSNull()]), "STATUS_LOCAL_ONLY"),
            ("{\"schema\":\"threados.settings-receipt.v1\",\"protocol\":\"TOSACK/1\",\"authority\":\"settings_do_not_grant_authority\",\"status\":\"error\",\"error\":\"MOVED_OR_UNBOUND_PROJECT\"}", "THREADOS_SETTINGS_ERROR")
        ]
        for (receipt, expected) in containers {
            form.receiveReceipt(receipt)
            let status = form.receiptStatus(catalog: nil, language: .english)
            #expect(status.contains(expected))
            #expect(status.contains("does not authenticate project identity"))
        }
    }

    @Test func actualFormStateRetainsValidReceiptUntilEditOrProjectSwitchAndRejectsFabricatedModelReceipt() throws {
        let preferences = ApplicationPreferences.inMemory()
        let first = ThreadOSSettingsDraft(project: "PROJECT_A", id: "cfg-001", revision: 1)
        let second = ThreadOSSettingsDraft(project: "PROJECT_B", id: "cfg-002", revision: 1)
        ThreadOSSettingsPreferences.save(first, to: preferences)
        ThreadOSSettingsPreferences.save(second, to: preferences)
        let form = ThreadOSSettingsFormState(preferences: preferences)
        form.receiveReceipt(modeOnReceipt)
        #expect(form.acceptedReceipt != nil)
        form.receiveReceipt("not a receipt")
        #expect(form.acceptedReceipt != nil)
        #expect(form.receiptStatus(catalog: nil, language: .english).contains("retaining the prior valid"))
        form.semanticEdit({ $0.tier = "priority" }, language: .english)
        #expect(form.acceptedReceipt == nil)
        form.receiveReceipt(modeOnReceipt)
        form.select(project: "PROJECT_B")
        #expect(form.draft.project == "PROJECT_B")
        #expect(form.acceptedReceipt == nil)
        form.receiveReceipt(fabricatedNativeModelReceipt)
        #expect(form.acceptedReceipt == nil) // fixture 17b: unsupported effective-model fabrication
    }

    @Test func actualFormStateCopyMessagesTiersAndPersistenceAreLanguageAware() {
        let preferences = ApplicationPreferences.inMemory()
        let form = ThreadOSSettingsFormState(preferences: preferences)
        form.copy(to: TestClipboard(), language: .english)
        #expect(form.message == "Cannot copy: select a valid project first.")
        form.newProject = "PROJECT_A"; form.createProject()
        #expect(form.draft.tier == "standard")
        form.semanticEdit({ $0.tier = "priority" }, language: .simplifiedChinese)
        let revision = form.draft.revision
        form.copy(to: FailingClipboard(), language: .simplifiedChinese)
        #expect(form.message.contains("剪贴板写入失败"))
        #expect(!form.message.contains("The local clipboard"))
        form.copy(to: TestClipboard(), language: .english)
        #expect(form.copiedRevision == revision)
        form.copy(to: TestClipboard(), language: .english)
        #expect(form.copiedRevision == revision) // repeated copy does not invent a revision rule
        let reload = ThreadOSSettingsFormState(preferences: preferences)
        #expect(reload.draft.tier == "priority")
        #expect(reload.draft.revision == revision)
    }

    @Test func actualFormStateRequiresFullMatchOnlyForConfigurationAcknowledgements() throws {
        let preferences = ApplicationPreferences.inMemory()
        let draft = ThreadOSSettingsDraft(project: "PROJECT_A", id: "cfg-001", revision: 1)
        ThreadOSSettingsPreferences.save(draft, to: preferences)
        let form = ThreadOSSettingsFormState(preferences: preferences)
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let view = try ThreadOSSettingsCodec.configurationView(form.draft, catalog: catalog)
        let data = try JSONEncoder().encode(view)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let ack = receipt(status: "pending_native_selection", fields: ["effective_from": "next-wave", "id": form.draft.id, "rev": form.draft.revision, "preset": form.draft.preset, "requested": object, "configured": object, "effective_observed": "unknown", "pending_native": ["CODING_WORKER", "FOREMAN", "LEADER", "QA", "REVIEWER"]])
        form.receiveReceipt(ack)
        #expect(form.receiptStatus(catalog: catalog, language: .english).contains("Pending native selection; effective model: UNKNOWN")) // fixture 18/19 semantics
        form.receiveReceipt(ack.replacingOccurrences(of: "cfg-001", with: "cfg-999"))
        #expect(form.receiptStatus(catalog: catalog, language: .english).contains("does not fully match"))
    }

    @Test func freshBalancedToCustomIsAtomicCatalogDerivedAndPersisted() throws {
        let preferences = ApplicationPreferences.inMemory()
        let form = makeForm(preferences: preferences)
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let original = form.draft
        #expect(original.customRoles.isEmpty)
        form.selectPreset("custom", catalog: catalog, language: .english)
        #expect(form.draft.preset == "custom")
        #expect(form.draft.id == original.id && form.draft.revision == original.revision + 1)
        #expect(Set(form.draft.customRoles.keys) == Set(ThreadOSRole.allCases))
        for role in ThreadOSRole.allCases {
            let spec = try #require(catalog.presets["astra-balanced"]?.roles[role.rawValue])
            #expect(form.draft.customRoles[role] == .init(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort))
        }
        #expect(form.draft.tier == "standard")
        #expect(ThreadOSSettingsFormState(preferences: preferences).draft == form.draft)
    }

    @Test func everyPresetAppliesCatalogCountsAndPresentsEveryActualRoleChoice() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let defaults = [("astra-economy", 1, 2), ("astra-balanced", 3, 3), ("astra-speed", 4, 3), ("astra-deep", 2, 4)]
        for tier in ["standard", "priority"] {
            let form = makeForm()
            form.semanticEdit({ $0.tier = tier }, language: .english)
            for (preset, coding, review) in defaults {
                let before = form.draft
                form.selectPreset(preset, catalog: catalog, language: .english)
                #expect(form.draft.id == before.id && form.draft.revision == before.revision + 1)
                #expect(form.draft.codingWorkers == coding && form.draft.reviewWorkers == review)
                #expect(form.draft.tier == tier)
                let rows = try form.rolePresentations(catalog: catalog)
                #expect(rows.map(\.role) == ThreadOSRole.allCases)
                for row in rows {
                    let spec = try #require(catalog.presets[preset]?.roles[row.id])
                    #expect(!row.isEditable)
                    #expect(row.selection == .init(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort))
                    #expect(row.resolved.model == spec.model && row.resolved.reasoningEffort == spec.reasoningEffort)
                    #expect(row.summary(language: .english).contains(spec.model))
                    #expect(row.summary(language: .english).contains(spec.reasoningEffort))
                    #expect(row.summary(language: .english).contains("effective native model: UNKNOWN"))
                }
            }
        }
    }

    @Test func customEditorsPersistAllRolesAndPreserveChoicesOnReentry() throws {
        let preferences = ApplicationPreferences.inMemory()
        let form = makeForm(preferences: preferences)
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        form.selectPreset("custom", catalog: catalog, language: .english)
        for role in ThreadOSRole.allCases {
            let before = form.draft.revision
            let model = form.draft.customRoles[role]?.model == "gpt-6-astra" ? "gpt-5.6-terra" : "gpt-6-astra"
            form.selectCustomModel(model, role: role, catalog: catalog, language: .english)
            form.selectCustomEffort("ultra", role: role, catalog: catalog, language: .english)
            #expect(form.draft.revision == before + 2)
            #expect(form.draft.customRoles[role] == .init(model: model, reasoningEffort: "ultra"))
        }
        let choices = form.draft.customRoles
        let reload = ThreadOSSettingsFormState(preferences: preferences)
        #expect(reload.draft == form.draft)
        reload.selectPreset("astra-economy", catalog: catalog, language: .english)
        reload.selectPreset("custom", catalog: catalog, language: .english)
        #expect(reload.draft.customRoles == choices)
        #expect(try reload.rolePresentations(catalog: catalog).allSatisfy(\.isEditable))
        let copied = TestClipboard()
        reload.copy(to: copied, language: .english)
        #expect(try ThreadOSSettingsCodec.draft(fromFrozenInput: #require(copied.value)).customRoles == choices)
    }

    @Test func foremanAutoRestoresVisibleCatalogFallbackAndCanonicalCopy() throws {
        let preferences = ApplicationPreferences.inMemory()
        let form = makeForm(preferences: preferences)
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        form.selectPreset("custom", catalog: catalog, language: .english)
        form.selectCustomModel("gpt-6-astra", role: .foreman, catalog: catalog, language: .english)
        form.selectCustomEffort("high", role: .foreman, catalog: catalog, language: .english)
        form.selectCustomModel("coder_auto", role: .foreman, catalog: catalog, language: .english)
        let rows = try form.rolePresentations(catalog: catalog)
        let foreman = try #require(rows.first { $0.role == .foreman })
        #expect(foreman.selection.model == "coder_auto")
        #expect(foreman.resolved == .init(model: catalog.selectionPolicy.coderAutoFallback.model, reasoningEffort: catalog.selectionPolicy.coderAutoFallback.reasoningEffort))
        #expect(foreman.summary(language: .english).contains("catalog fallback: gpt-5.6-terra / \(catalog.selectionPolicy.coderAutoFallback.reasoningEffort)"))
        #expect(foreman.summary(language: .simplifiedChinese).contains("目录回退"))
        for row in rows {
            #expect(row.modelOptions.contains("coder_auto") == (row.role == .foreman))
            #expect(!row.modelOptions.contains("gpt-5.6-sol"))
            #expect(row.effortOptions == (row.selection.model == "coder_auto" ? [catalog.selectionPolicy.coderAutoFallback.reasoningEffort] : catalog.models[row.resolved.model]?.reasoningEfforts))
        }
        #expect(ThreadOSSettingsFormState(preferences: preferences).draft.customRoles[.foreman]?.model == "coder_auto")
        let clipboard = TestClipboard()
        form.copy(to: clipboard, language: .english)
        let copy = try #require(clipboard.value)
        #expect(!copy.contains("coder_auto"))
        #expect(try ThreadOSSettingsCodec.draft(fromFrozenInput: copy).customRoles[.foreman] == foreman.resolved)
    }

    @Test func modelChangeAtomicallyChoosesAValidEffortFromThatModelsCatalog() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let constrained = ThreadOSModelCatalog(schema: catalog.schema, revision: catalog.revision, models: ["gpt-6-astra": .init(reasoningEfforts: ["high"]), "gpt-5.6-terra": .init(reasoningEfforts: ["low", "medium"])], presets: catalog.presets, selectionPolicy: catalog.selectionPolicy)
        let form = makeForm()
        form.selectPreset("custom", catalog: constrained, language: .english)
        let before = form.draft.revision
        form.selectCustomModel("gpt-5.6-terra", role: .leader, catalog: constrained, language: .english)
        #expect(form.draft.revision == before + 1)
        #expect(form.draft.customRoles[.leader] == .init(model: "gpt-5.6-terra", reasoningEffort: "low"))
        let row = try #require(form.rolePresentations(catalog: constrained).first { $0.role == .leader })
        #expect(row.effortOptions == ["low", "medium"])
        let valid = form.draft
        form.selectCustomEffort("ultra", role: .leader, catalog: constrained, language: .english)
        #expect(form.draft == valid)
    }

    @Test func missingUnknownOrInvalidRoleChoicesRejectWithoutMutatingDraftOrLocalProof() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let form = makeForm()
        form.copy(to: TestClipboard(), language: .english)
        form.receiveReceipt(modeOnReceipt)
        let before = form.draft
        for presetName in ["astra-balanced", "astra-economy"] {
            for unknownRole in [false, true] {
                var presets = catalog.presets
                let original = try #require(presets[presetName])
                var roles = original.roles
                if unknownRole { roles["UNKNOWN_ROLE"] = roles["LEADER"] } else { roles.removeValue(forKey: "QA") }
                presets[presetName] = .init(roles: roles, codingWorkers: original.codingWorkers, reviewWorkers: original.reviewWorkers, serviceTier: original.serviceTier)
                let invalid = ThreadOSModelCatalog(schema: catalog.schema, revision: catalog.revision, models: catalog.models, presets: presets, selectionPolicy: catalog.selectionPolicy)
                form.selectPreset(presetName == "astra-balanced" ? "custom" : presetName, catalog: invalid, language: .english)
                #expect(form.draft == before)
                #expect(form.copiedRevision == before.revision && form.acceptedReceipt != nil)
            }
        }
        form.selectPreset("unknown", catalog: catalog, language: .english)
        form.selectPreset("custom", catalog: nil, language: .english)
        #expect(form.draft == before)
        form.selectPreset("custom", catalog: catalog, language: .english)
        let custom = form.draft
        for invalidModel in ["coder_auto", "gpt-5.6-sol", "unknown-model"] {
            form.selectCustomModel(invalidModel, role: .leader, catalog: catalog, language: .english)
            #expect(form.draft == custom)
        }
        form.selectCustomEffort("none", role: .foreman, catalog: catalog, language: .english)
        form.semanticEdit({ $0.customRoles.removeValue(forKey: .qa) }, language: .english)
        #expect(form.draft == custom)
    }

    @Test func presetNoopRetainsOverridesAndMaximumRevisionRejectsCompleteTransition() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let form = makeForm()
        form.selectPreset("astra-economy", catalog: catalog, language: .english)
        form.semanticEdit({ $0.codingWorkers = 4; $0.reviewWorkers = 1 }, language: .english)
        let overridden = form.draft
        form.copy(to: TestClipboard(), language: .english)
        form.receiveReceipt(modeOnReceipt)
        form.selectPreset("astra-economy", catalog: catalog, language: .english)
        #expect(form.draft == overridden)
        #expect(form.copiedRevision == overridden.revision && form.acceptedReceipt != nil)
        #expect(try ThreadOSSettingsCodec.draft(fromFrozenInput: ThreadOSSettingsCodec.canonicalRequest(form.draft)).codingWorkers == 4)
        let preferences = ApplicationPreferences.inMemory()
        var maximum = overridden; maximum.revision = 1_000_000
        ThreadOSSettingsPreferences.save(maximum, to: preferences)
        let maxForm = ThreadOSSettingsFormState(preferences: preferences)
        maxForm.selectPreset("custom", catalog: catalog, language: .english)
        #expect(maxForm.draft == maximum)
        #expect(maxForm.message.contains("maximum revision"))
        maximum.preset = "custom"; maximum.customRoles = ThreadOSSettingsDraft.defaultCustomRoles
        ThreadOSSettingsPreferences.save(maximum, to: preferences)
        let maxCustom = ThreadOSSettingsFormState(preferences: preferences)
        maxCustom.selectCustomModel("gpt-5.6-terra", role: .leader, catalog: catalog, language: .english)
        maxCustom.selectCustomEffort("ultra", role: .qa, catalog: catalog, language: .english)
        #expect(maxCustom.draft == maximum)
    }

    @Test func actualPresetAndCustomActionsInvalidateStaleCopyAndReceiptButNoopsRetainThem() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let form = makeForm()
        let actions: [() -> Void] = [
            { form.selectPreset("astra-speed", catalog: catalog, language: .english) },
            { form.selectPreset("custom", catalog: catalog, language: .english) },
            { form.selectCustomModel("gpt-5.6-terra", role: .qa, catalog: catalog, language: .english) },
            { form.selectCustomEffort("ultra", role: .qa, catalog: catalog, language: .english) }
        ]
        for action in actions {
            form.copy(to: TestClipboard(), language: .english)
            form.receiveReceipt(modeOnReceipt)
            let revision = form.draft.revision
            action()
            #expect(form.draft.revision == revision + 1)
            #expect(form.copiedRevision == nil && form.acceptedReceipt == nil && form.receipt.isEmpty)
            form.copy(to: TestClipboard(), language: .english)
            form.receiveReceipt(modeOnReceipt)
            action()
            #expect(form.draft.revision == revision + 1)
            #expect(form.copiedRevision == form.draft.revision && form.acceptedReceipt != nil)
        }
    }

    @Test func actualViewWiresAllRoleControlsToSharedPresentationsAndActionsAlongsideQ2Controls() throws {
        let form = makeForm()
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        form.selectPreset("custom", catalog: catalog, language: .english)
        let rows = try form.rolePresentations(catalog: catalog)
        #expect(rows.count == 5 && rows.allSatisfy(\.isEditable))
        #expect(Set(rows.map(\.modelIdentifier)).count == 5 && Set(rows.map(\.effortIdentifier)).count == 5)
        // Source wiring plus execution of the same shared actions/presentation;
        // this deliberately makes no native UI or accessibility-session claim.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/CodexUsageUI/Views/ThreadOSSettingsView.swift"), encoding: .utf8)
        let view = try #require(source.range(of: "public struct ThreadOSSettingsView: View"))
        let body = String(source[view.lowerBound...])
        for wiring in ["        roleFields", "form.rolePresentations(catalog: catalog)", "ForEach(roles)", "role.summary(language: language)", "if role.isEditable", "selection: customModelBinding(role.role)", "selection: customEffortBinding(role.role)", "ForEach(role.modelOptions", "ForEach(role.effortOptions", ".accessibilityIdentifier(role.summaryIdentifier)", ".accessibilityIdentifier(role.modelIdentifier)", ".accessibilityIdentifier(role.effortIdentifier)", "form.selectPreset($0", "form.selectCustomModel($0", "form.selectCustomEffort($0", "uma.threados.service-tier", "uma.threados.copy", "uma.threados.receipt", "uma.threados.project-selector"] {
            #expect(body.contains(wiring), "Missing actual View wiring: \(wiring)")
        }
    }

    private func makeForm(preferences: ApplicationPreferences = .inMemory()) -> ThreadOSSettingsFormState {
        ThreadOSSettingsPreferences.save(.init(project: "PROJECT_A", id: "cfg-001", revision: 1), to: preferences)
        return ThreadOSSettingsFormState(preferences: preferences)
    }

    @MainActor private final class TestClipboard: ThreadOSSettingsClipboard {
        var value: String?
        func write(_ string: String) -> Bool { value = string; return true }
    }

    @MainActor private final class FailingClipboard: ThreadOSSettingsClipboard { func write(_ string: String) -> Bool { false } }

    private var modeOnReceipt: String { "{\"schema\":\"threados.settings-receipt.v1\",\"protocol\":\"TOSACK/1\",\"authority\":\"settings_do_not_grant_authority\",\"status\":\"mode_updated\",\"mode\":\"on\",\"effective_from\":\"observed\"}" }
    private var fabricatedNativeModelReceipt: String { "{\"schema\":\"threados.settings-receipt.v1\",\"protocol\":\"TOSACK/1\",\"authority\":\"settings_do_not_grant_authority\",\"status\":\"pending_native_selection\",\"effective_from\":\"next-wave\",\"id\":\"cfg-001\",\"rev\":1,\"preset\":\"astra-balanced\",\"requested\":{},\"configured\":{},\"effective_observed\":\"gpt-6-astra\",\"pending_native\":[]}" }

    private var validView: [String: Any] {
        let role = ["requested_model": "gpt-6-astra", "configured_model": "gpt-6-astra", "reasoning_effort": "high", "effective_observed": "unknown", "native_status": "pending_native_selection"]
        return ["catalog_revision": "astra-20260904.1", "preset": "astra-balanced", "roles": ["CODING_WORKER": role, "FOREMAN": role, "LEADER": role, "QA": role, "REVIEWER": role], "coding_workers": 2, "review_workers": 2, "tier": "standard", "apply": "next-wave"]
    }

    private func receipt(status: String, fields: [String: Any]) -> String {
        var object: [String: Any] = ["schema": "threados.settings-receipt.v1", "protocol": "TOSACK/1", "authority": "settings_do_not_grant_authority", "status": status]
        fields.forEach { object[$0.key] = $0.value }
        return String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }

    private var customRoles: [ThreadOSRole: ThreadOSRoleSelection] {
        [.leader: .init(model: "gpt-6-astra", reasoningEffort: "high"), .qa: .init(model: "gpt-6-astra", reasoningEffort: "high"), .foreman: .init(model: "gpt-5.6-terra", reasoningEffort: "medium"), .codingWorker: .init(model: "gpt-5.6-terra", reasoningEffort: "low"), .reviewer: .init(model: "gpt-5.6-terra", reasoningEffort: "medium")]
    }
}
