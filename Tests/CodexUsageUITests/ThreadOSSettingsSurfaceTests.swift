import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import CodexUsageUI

@MainActor struct ThreadOSSettingsSurfaceTests {
    @Test func threadOSSettingsUsesVerticalReachabilityWithoutHorizontalOverflowAtMinimumWindowWidth() throws {
        let freshPreferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "TU4_FRESH"), to: freshPreferences)
        let preferences = ApplicationPreferences.inMemory()
        var custom = ThreadOSSettingsDraft(project: "TU4_LAYOUT", preset: "custom")
        custom.customRoles = ThreadOSSettingsDraft.defaultCustomRoles
        ThreadOSSettingsPreferences.save(custom, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "TU4_LAYOUT"), to: preferences)

        _ = NSApplication.shared
        for view in [
            ThreadOSSettingsView(language: .english, preferences: freshPreferences, initiallyExpandedWorkerGroups: [.coder]),
            ThreadOSSettingsView(language: .english, preferences: preferences, initiallyExpandedWorkerGroups: [.coder]),
        ] {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }

            host.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()

            // The attached host must not replace child control identifiers with
            // a common container identifier in the native accessibility tree.
            #expect(host.accessibilityIdentifier().isEmpty)

            let scrolls = descendants(of: host).compactMap { $0 as? NSScrollView }
            let outerScroll = try #require(scrolls.first { scroll in
                guard let document = scroll.documentView else { return false }
                return scroll.hasVerticalScroller
                    && document.frame.height > scroll.contentView.bounds.height
                    && document.frame.width <= scroll.contentView.bounds.width + 1
            })
            #expect(!outerScroll.hasHorizontalScroller)
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

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

    @Test func attributionBindingFormSavesOnlyVerifiedCurrentBytesAndClearsThroughPreferences() throws {
        let preferences = ApplicationPreferences.inMemory()
        let form = ThreadOSAttributionBindingFormState(preferences: preferences)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("threados-binding-sentinel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("helper-launched")
        let helper = directory.appendingPathComponent("helper.sh")
        try "#!/bin/sh\nprintf launched > '\(sentinel.path)'\n".data(using: .utf8)!.write(to: helper)
        form.interpreterPath = "/bin/sh"
        form.helperPath = helper.path
        form.runtimeRootPath = directory.path
        form.journalPath = directory.appendingPathComponent("journal.jsonl").path
        form.projectKey = "TOSUMA"
        form.projectRootDigest = String(repeating: "a", count: 64)
        form.interpreterSHA256 = try digest("/bin/sh")
        form.helperSHA256 = try digest(helper.path)
        form.save(language: .english)
        #expect(form.isSaved)
        #expect(form.message.contains("does not prove coverage"))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        let stored = try #require(preferences.value(for: ThreadOSHistoricalAttributionPreferences.binding))
        #expect(try JSONDecoder().decode(ThreadOSHistoricalAttributionBinding.self, from: stored).projectKey == "TOSUMA")

        form.helperSHA256 = String(repeating: "0", count: 64)
        form.save(language: .english)
        #expect(form.isSaved)
        #expect(form.message.localizedCaseInsensitiveContains("no exporter was started"))
        #expect(preferences.value(for: ThreadOSHistoricalAttributionPreferences.binding) == stored)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))

        form.clear(language: .simplifiedChinese)
        #expect(!form.isSaved)
        #expect(preferences.value(for: ThreadOSHistoricalAttributionPreferences.binding) == nil)
        #expect(form.message.contains("已清除"))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    private func digest(_ path: String) throws -> String {
        SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
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

    @Test func copyPayloadIsConfigurationOnlyAndAChangedDraftInvalidatesLocalProof() throws {
        let preferences = ApplicationPreferences.inMemory()
        let form = ThreadOSSettingsFormState(preferences: preferences)
        form.newProject = "SAFE_PROJECT"; form.createProject()
        let clipboard = TestClipboard()
        form.copy(to: clipboard, language: .english)
        let payload = try #require(clipboard.value)
        #expect(payload.hasPrefix("TOSCFG/1 "))
        for forbidden in ["prompt", "credential", "secret", "/Users/", "source code"] {
            #expect(!payload.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(form.copiedRevision == form.draft.revision)
        form.semanticEdit({ $0.tier = "priority" }, language: .english)
        #expect(form.copiedRevision == nil)
        #expect(form.receipt.isEmpty)
        #expect(form.acceptedReceipt == nil)
    }

    @Test func systemClipboardRestoresEveryPasteboardItemTypeWhenWriteFails() {
        let customType = NSPasteboard.PasteboardType("com.silkrd.uma.test.custom")
        let original = NSPasteboardItem()
        original.setData(Data("plain text".utf8), forType: .string)
        original.setData(Data([0x00, 0x01, 0x02]), forType: customType)
        let board = FailingPasteboard(items: [original])

        #expect(!SystemThreadOSSettingsClipboard(board: board).write("new request"))
        let restored = try! #require(board.pasteboardItems?.first)
        #expect(restored.types.contains(.string) && restored.types.contains(customType))
        #expect(restored.data(forType: .string) == Data("plain text".utf8))
        #expect(restored.data(forType: customType) == Data([0x00, 0x01, 0x02]))
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

    @Test func modelChangeRequiresAnExplicitEffortWhenTheSavedEffortIsUnavailable() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        var models = catalog.models
        models["gpt-6-astra"] = .init(reasoningEfforts: ["high"])
        models["gpt-5.6-terra"] = .init(reasoningEfforts: ["low", "medium"])
        let constrained = ThreadOSModelCatalog(schema: catalog.schema, revision: catalog.revision, models: models, presets: catalog.presets, selectionPolicy: catalog.selectionPolicy)
        let form = makeForm()
        form.selectPreset("custom", catalog: constrained, language: .english)
        let before = form.draft.revision
        form.selectCustomModel("gpt-5.6-terra", role: .leader, catalog: constrained, language: .english)
        #expect(form.draft.revision == before + 1)
        #expect(form.draft.customRoles[.leader] == .init(model: "gpt-5.6-terra", reasoningEffort: ""))
        let row = try #require(form.rolePresentations(catalog: constrained).first { $0.role == .leader })
        #expect(row.effortOptions == ["low", "medium"])
        #expect(row.summary(language: .english).contains("choose effort"))
        #expect(throws: (any Error).self) { try ThreadOSSettingsCodec.canonicalRequest(form.draft, catalog: constrained) }
        form.selectCustomEffort("medium", role: .leader, catalog: constrained, language: .english)
        #expect(form.draft.customRoles[.leader] == .init(model: "gpt-5.6-terra", reasoningEffort: "medium"))
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
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "PROJECT_A"), to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.draft.isLocallyValid)
        // This verifies source wiring only; the hosting test above covers actual AppKit layout.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/CodexUsageUI/Views/ThreadOSSettingsView.swift"), encoding: .utf8)
        let view = try #require(source.range(of: "public struct ThreadOSSettingsView: View"))
        let body = String(source[view.lowerBound...])
        for wiring in ["factoriumV2Content", "FactoriumV2Role.allCases", "roleCard(role)", "workerSlots(role: role)", "workerSummary(for: role)", "workerColumnHeadings", "workerRow(role: role, index: index, slot: slot)", "workerExpansionBinding(role)", "roleDisplayName(role)", "roleSymbol(role)", "Three stable slots are configuration capacity", "Disabled slots retain this saved draft", "uma.threados.v2.project-selector", "uma.threados.v2.generate-copy", "uma.threados.v2.footer-status", "footerStatus", "footerStatusOverride", "advanced.details", "Model · Thinking", "uma.threados.v2.raw-ack", "uma.threados.v2.coming-soon", "uma.threados.v2.speed-boundary", "VStack(spacing: 0)", "ViewThatFits(in: .horizontal)", ".pickerStyle(.segmented)", "let workerName = title", ".accessibilityLabel(title(\"Model for \\(workerName)\"", ".accessibilityLabel(title(\"Thinking for \\(workerName)\"", "uma.threados.v2.role.\\(role.rawValue).model", "uma.threados.v2.role.\\(role.rawValue).effort"] {
            #expect(body.contains(wiring), "Missing actual View wiring: \(wiring)")
        }
        #expect(!body.contains(".accessibilityIdentifier(\"uma.threados.settings\")"))
        #expect(!body.contains(".accessibilityIdentifier(\"uma.threados.v2.role.\\(role.rawValue)\")"))
    }

    @Test func factoriumV2SerializesTheCanonicalLocalRequest() throws {
        let draft = FactoriumV2SettingsDraft(project: "PROJECT_A", id: "v2-request", revision: 7)
        let request = try draft.canonicalRequest()
        #expect(request.hasPrefix("TOSCFG/2 "))
        let data = try #require(request.dropFirst("TOSCFG/2 ".count).data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["apply", "cat", "id", "p", "preset", "rev", "roles", "workers"])
        #expect(json["apply"] as? String == "next-wave")
        #expect(json["cat"] as? String == "sol-luna-20260922.1")
        #expect((json["roles"] as? [String: Any])?["leader"] as? [String: Bool] == ["preserve": true])
        let workers = try #require(json["workers"] as? [String: [[String: Any]]])
        #expect(workers["coder"]?.count == 3 && workers["reviewer"]?.count == 3)
        #expect(workers["coder"]?.allSatisfy { $0["enabled"] as? Bool == true && $0["model"] as? String == "inherit" && $0["effort"] as? String == "inherit" && $0["speed"] as? String == "inherit" } == true)
    }

    @Test func factoriumV2KeepsV1DraftsSeparateAndRequiresFourWorkerConfirmation() throws {
        let preferences = ApplicationPreferences.inMemory()
        let legacy = ThreadOSSettingsDraft(project: "PROJECT_A", id: "legacy-v1", codingWorkers: 4, reviewWorkers: 2)
        ThreadOSSettingsPreferences.save(legacy, to: preferences)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "PROJECT_A", from: preferences) == nil)
        #expect(throws: FactoriumV2SettingsError.legacyWorkerConfirmationRequired) {
            try FactoriumV2SettingsDraft.converted(from: legacy, confirmedFourWorkerConversion: false, id: "fresh-v2")
        }
        let converted = try FactoriumV2SettingsDraft.converted(from: legacy, confirmedFourWorkerConversion: true, id: "fresh-v2")
        ThreadOSSettingsPreferences.saveFactoriumV2(converted, to: preferences)
        #expect(ThreadOSSettingsPreferences.load(from: preferences).id == "legacy-v1")
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "PROJECT_A", from: preferences)?.id == "fresh-v2")
    }

    @Test func factoriumV2InheritedWorkerResolvesAgainstItsCurrentParent() {
        var draft = FactoriumV2SettingsDraft(project: "PROJECT_A")
        var coder = draft.roles[.coder]!.selection
        coder.effort = "high"
        draft.setSelection(coder, for: .coder)
        let inherited = draft.coderWorkers[0]
        #expect(draft.resolvedSlot(inherited, parent: .coder) == coder)
        draft.setSlotInheritance(false, at: 0, for: .coder)
        var custom = draft.coderWorkers[0].selection
        custom.effort = "low"
        draft.coderWorkers[0].selection = custom
        coder.effort = "medium"
        draft.setSelection(coder, for: .coder)
        #expect(draft.resolvedSlot(draft.coderWorkers[0], parent: .coder) == custom)
    }

    @Test func factoriumV2ConversionPreservesV1AndMapsCatalogSelectionsWithoutUsingRepairAsACodingWorkerAlias() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        var custom = ThreadOSSettingsDraft.defaultCustomRoles
        custom[.foreman] = .init(model: "gpt-5.6-terra", reasoningEffort: "high")
        custom[.codingWorker] = .init(model: "gpt-5.6-terra", reasoningEffort: "low")
        let legacy = ThreadOSSettingsDraft(project: "PROJECT_A", id: "legacy-v1", preset: "custom", codingWorkers: 2, reviewWorkers: 1, customRoles: custom)
        let converted = try FactoriumV2SettingsDraft.converted(from: legacy, confirmedFourWorkerConversion: false, id: "fresh-v2", catalog: catalog)
        #expect(converted.id == "fresh-v2" && converted.project == legacy.project)
        #expect(converted.roles[.coder]?.selection.effort == "high")
        #expect(converted.roles[.repair] == FactoriumV2SettingsDraft.defaultRoles[.repair])
        #expect(converted.coderWorkers.map(\.enabled) == [true, true, false])
        #expect(converted.coderWorkers.allSatisfy { !$0.inherits && $0.hasCustomSelection && $0.selection.effort == "low" })
        #expect(converted.reviewerWorkers.map(\.enabled) == [true, false, false])
    }

    @Test func factoriumV2RestoresLastProjectAndInvalidatesCopyForEditSwitchAndFailure() throws {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "PROJECT_A", id: "a"), to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "PROJECT_B", id: "b"), to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject("PROJECT_B", to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.selectedProject == "PROJECT_B")
        form.rawAcknowledgement = "stale"
        form.reportCopy(success: true, language: .english)
        #expect(form.copiedRevision == form.draft.revision)
        form.reportCopy(success: true, language: .english)
        #expect(form.copiedRevision == form.draft.revision)
        form.select(project: "PROJECT_A")
        #expect(form.copiedRevision == nil && form.rawAcknowledgement.isEmpty)
        form.reportCopy(success: false, language: .english)
        #expect(form.copiedRevision == nil)
        #expect(form.message.contains("could not be written"))
        form.reportCopy(success: true, language: .english)
        #expect(form.message.contains("Native selection remains unconfirmed"))
        let before = form.draft.revision
        form.edit { $0.roles[.repair]?.selection.effort = "low" }
        #expect(form.draft.revision == before + 1 && form.copiedRevision == nil)
        #expect(FactoriumV2FormState(preferences: preferences).selectedProject == "PROJECT_A")
    }

    @Test func factoriumV2AllOffWorkersAndCustomSlotValuesRemainValidAndRetained() throws {
        var draft = FactoriumV2SettingsDraft(project: "PROJECT_A", id: "v2-all-off")
        for index in 0..<3 {
            draft.coderWorkers[index].enabled = false
            draft.reviewerWorkers[index].enabled = false
        }
        draft.setSlotInheritance(false, at: 0, for: .coder)
        var selection = draft.coderWorkers[0].selection
        selection.effort = "high"
        draft.setSlotSelection(selection, at: 0, for: .coder)
        draft.setSlotInheritance(true, at: 0, for: .coder)
        draft.setSlotInheritance(false, at: 0, for: .coder)
        #expect(draft.coderWorkers[0].selection.effort == "high")
        let data = try #require(draft.canonicalRequest().dropFirst("TOSCFG/2 ".count).data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let workers = try #require(object["workers"] as? [String: [[String: Any]]])
        #expect(workers["coder"]?.allSatisfy { $0["enabled"] as? Bool == false } == true)
        #expect(workers["reviewer"]?.allSatisfy { $0["enabled"] as? Bool == false } == true)
    }

    @Test func factoriumV2HostedViewKeepsItsFixedCopyActionOutsideTheScrollableCards() throws {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "PROJECT_A"), to: preferences)
        _ = NSApplication.shared
        let host = NSHostingView(rootView: ThreadOSSettingsView(language: .english, preferences: preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 552), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        #expect(scroll.hasVerticalScroller && host.fittingSize.width > 0)
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

    @MainActor private final class FailingPasteboard: ThreadOSSettingsPasteboard {
        var pasteboardItems: [NSPasteboardItem]?
        init(items: [NSPasteboardItem]) { pasteboardItems = items }
        @discardableResult func clearContents() -> Int { pasteboardItems = []; return 1 }
        func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
            let partial = NSPasteboardItem(); partial.setString(string, forType: dataType)
            pasteboardItems = [partial]
            return false
        }
        func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
            pasteboardItems = objects.compactMap { $0 as? NSPasteboardItem }
            return true
        }
    }

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
