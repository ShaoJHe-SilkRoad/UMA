import Foundation
import CryptoKit
import Testing
@testable import CodexUsageUI

struct ThreadOSSettingsContractTests {
    @Test func latestCatalogAdds61SolWithoutChangingPinnedHistoryOrWorkers() throws {
        let legacy = try ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.legacyCatalogRevision)
        let prior = try ThreadOSSettingsCodec.loadCatalog(revision: "sol-luna-20260922.1")
        let current = try ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.latestCatalogRevision)
        #expect(legacy.revision == "astra-20260904.1")
        #expect(prior.revision == "sol-luna-20260922.1")
        #expect(prior.models["gpt-6-sol"]?.reasoningEfforts == ["low", "medium", "high", "xhigh"])
        #expect(current.revision == "sol-luna-20261001.1")
        #expect(current.models["gpt-6-sol"]?.reasoningEfforts == ["low", "medium", "high", "xhigh"])
        #expect(!FactoriumV2SettingsDraft.availableModels(catalog: current).contains("gpt-6-sol"))
        #expect(current.models["gpt-6.1-sol"]?.reasoningEfforts == ["low", "medium", "high", "xhigh"])
        #expect(FactoriumV2SettingsDraft.availableModels(catalog: current).contains("gpt-6.1-sol"))
        #expect(!FactoriumV2SettingsDraft.availableModels(catalog: current).contains("gpt-6-sol"))
        for preset in current.presets.values where !preset.roles.isEmpty {
            #expect(preset.roles["LEADER"]?.model == "gpt-6.1-sol")
            #expect(preset.roles["LEADER"]?.reasoningEffort == "high")
            #expect(preset.roles["QA"]?.model == "gpt-6.1-sol")
            #expect(preset.roles["QA"]?.reasoningEffort == "high")
            #expect(preset.roles["CODING_WORKER"]?.model == "gpt-6-luna")
            #expect(preset.roles["REVIEWER"]?.model == "gpt-6-luna")
        }
        #expect(FactoriumV2SettingsDraft.defaultRoles[.leader]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(FactoriumV2SettingsDraft.defaultRoles[.qa]?.selection == .init(model: "gpt-6.1-sol", effort: "high", speed: "standard"))
        #expect(FactoriumV2SettingsDraft.defaultRoles[.coder]?.selection == .init(model: "gpt-6-luna", effort: "medium", speed: "standard"))
        #expect(FactoriumV2SettingsDraft.defaultRoles[.reviewer]?.selection == .init(model: "gpt-6-luna", effort: "medium", speed: "standard"))
        #expect(FactoriumV2SettingsDraft.defaultRoles[.repair]?.selection.model == "gpt-5.6-terra")
    }
    @Test func frozenTU1FixtureHasAllCasesAndCanonicalBytes() throws {
        let fixture = try fixture()
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count == 38)
        #expect(cases.flatMap { $0["steps"] as? [[String: Any]] ?? [] }.count == 78)
        #expect(fixture["provenance"] as? String == "SYNTHETIC_LOCAL_SETTINGS_ORACLE_NOT_NATIVE_FACTORIUM")
        #expect(fixture["swift_execution"] as? String == "NOT_RUN")

        for step in cases.flatMap({ $0["steps"] as? [[String: Any]] ?? [] }) {
            guard let expected = step["expected"] as? [String: Any],
                  let request = expected["canonical_request_utf8"] as? String,
                  let hex = expected["canonical_request_hex"] as? String else { continue }
            #expect(request.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() == hex)
            #expect(request.hasPrefix("TOSCFG/1 "))
            #expect(!request.hasSuffix("\n"))
            #expect(request.unicodeScalars.allSatisfy { $0.value < 128 })
        }
    }

    @Test func canonicalSerializerMatchesEveryApplicableFrozenRequest() throws {
        let cases = try #require(fixture()["cases"] as? [[String: Any]])
        var exercised = 0
        for step in cases.flatMap({ $0["steps"] as? [[String: Any]] ?? [] }) {
            guard let expected = step["expected"] as? [String: Any],
                  let request = expected["canonical_request_utf8"] as? String,
                  let draft = try draft(fromCanonicalRequest: request) else { continue }
            #expect(try ThreadOSSettingsCodec.canonicalRequest(draft) == request)
            exercised += 1
        }
        #expect(exercised == 43) // Valid settings vectors only; rejection/state adapters remain external to UMA.
    }

    @Test func frozenApplyInputsAreStrictlyParsedBeforeCanonicalization() throws {
        let cases = try #require(fixture()["cases"] as? [[String: Any]])
        let statefulErrors: Set<String> = ["STALE_REVISION", "REQUEST_CONFLICT", "FOREIGN_PROJECT", "MOVED_OR_UNBOUND_PROJECT"]
        var valid = 0; var rejected = 0
        for step in cases.flatMap({ $0["steps"] as? [[String: Any]] ?? [] }) where step["op"] as? String == "apply" {
            let input = try #require(step["input"] as? String)
            let requiredError = step["required_error"] as? String
            if let requiredError, !statefulErrors.contains(requiredError) {
                do {
                    _ = try ThreadOSSettingsCodec.draft(fromFrozenInput: input)
                    Issue.record("Accepted frozen rejection: \(requiredError)")
                } catch let error as ThreadOSSettingsCodecError {
                    #expect(error.protocolCode == requiredError)
                }
                rejected += 1
            } else {
                let draft = try ThreadOSSettingsCodec.draft(fromFrozenInput: input)
                let expected = try #require(step["expected"] as? [String: Any])
                if let request = expected["canonical_request_utf8"] as? String {
                    #expect(try ThreadOSSettingsCodec.canonicalRequest(draft) == request, "input=\(input)")
                }
                valid += 1
            }
        }
        #expect(valid == 47)
        #expect(rejected == 17)
    }

    @Test func modeSerializerPreservesPinnedModeBytesAndRejectsUnsupportedForms() throws {
        #expect(try ThreadOSSettingsCodec.canonicalMode(mode: "on") == "TOSMODE/1 {\"mode\":\"on\"}")
        #expect(try ThreadOSSettingsCodec.canonicalMode(mode: "off", when: "idle") == "TOSMODE/1 {\"mode\":\"off\",\"when\":\"idle\"}")
        #expect(throws: ThreadOSSettingsCodecError.invalidMode) { try ThreadOSSettingsCodec.canonicalMode(mode: "off") }
        #expect(throws: ThreadOSSettingsCodecError.invalidMode) { try ThreadOSSettingsCodec.canonicalMode(mode: "on", when: "idle") }
    }

    @Test func receiptAdaptersDoNotPromoteConfiguredModelsToNativeProof() throws {
        let acknowledgements = try #require(fixture()["acknowledgements"] as? [[String: Any]])
        #expect(acknowledgements.count == 4)
        for acknowledgement in acknowledgements {
            let input = try #require(acknowledgement["input"] as? [String: Any])
            let text = try canonicalJSON(input)
            let expected = acknowledgement["schema_accepts"] as? Bool == true ? ThreadOSSettingsAcknowledgementPresentation.pendingNativeSelection : ThreadOSSettingsAcknowledgementPresentation.unsupported
            if acknowledgement["id"] as? String == "17a-mode-effective-state" { #expect(ThreadOSSettingsCodec.receiptPresentation(text) == .modeOnObservedLocalOnly) }
            else { #expect(ThreadOSSettingsCodec.receiptPresentation(text) == expected) }
            #expect(acknowledgement["native_model_proven"] as? Bool == false)
        }
    }

    @Test func receiptPresentationIsTypedAndNonGranting() throws {
        let acknowledgements = try #require(fixture()["acknowledgements"] as? [[String: Any]])
        let pending = try #require(acknowledgements.first { $0["id"] as? String == "18-pending-native-selection" }?["input"] as? [String: Any])
        #expect(ThreadOSSettingsCodec.receiptPresentation(try canonicalJSON(pending)) == .pendingNativeSelection)
    }

    @Test func everyFrozenReceiptRetainsNonGrantingAuthorityAndSupportedShape() throws {
        let cases = try #require(fixture()["cases"] as? [[String: Any]])
        var receipts = 0
        for step in cases.flatMap({ $0["steps"] as? [[String: Any]] ?? [] }) {
            guard let receipt = (step["expected"] as? [String: Any])?["receipt"] as? [String: Any] else { continue }
            #expect(receipt["authority"] as? String == "settings_do_not_grant_authority")
            #expect(ThreadOSSettingsCodec.receiptDisplay(try canonicalJSON(receipt)) != "UNSUPPORTED_RECEIPT_SHAPE")
            receipts += 1
        }
        #expect(receipts == 76)
    }

    @Test func allPresetOverridesAndOmittedDefaultsMatchTheCatalog() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        for name in catalog.presets.keys where name != "custom" {
            let defaults = try #require(catalog.presets[name])
            let minimal = "TOSCFG/1 {\"p\":\"P\",\"id\":\"cfg\",\"rev\":1,\"cat\":\"\(catalog.revision)\",\"preset\":\"\(name)\"}"
            let expanded = try ThreadOSSettingsCodec.draft(fromFrozenInput: minimal)
            #expect(expanded.codingWorkers == defaults.codingWorkers)
            #expect(expanded.reviewWorkers == defaults.reviewWorkers)
            #expect(expanded.tier == "standard")
            for cw in 1...4 { for rw in 1...4 {
                let draft = ThreadOSSettingsDraft(project: "P", id: "cfg", preset: name, codingWorkers: cw, reviewWorkers: rw)
                let parsed = try ThreadOSSettingsCodec.draft(fromFrozenInput: ThreadOSSettingsCodec.canonicalRequest(draft))
                #expect(parsed == draft)
                let view = try ThreadOSSettingsCodec.configurationView(parsed, catalog: catalog)
                #expect(view.codingWorkers == cw && view.reviewWorkers == rw)
            } }
        }
    }

    @Test func customAutoUsesCatalogPolicyAndRoundTripsWithoutEmittingSelectionToken() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog()
        let draft = ThreadOSSettingsDraft(project: "P", id: "cfg", preset: "custom", customRoles: ThreadOSSettingsDraft.defaultCustomRoles)
        #expect(draft.customRoles[.foreman]?.model == "coder_auto")
        let request = try ThreadOSSettingsCodec.canonicalRequest(draft)
        #expect(!request.contains("coder_auto"))
        let parsed = try ThreadOSSettingsCodec.draft(fromFrozenInput: request)
        #expect(parsed.customRoles[.foreman]?.model == catalog.selectionPolicy.coderAutoFallback.model)
        #expect(parsed.customRoles[.foreman]?.reasoningEffort == catalog.selectionPolicy.coderAutoFallback.reasoningEffort)
        #expect(try ThreadOSSettingsCodec.canonicalRequest(parsed) == request)
        // The explicit effort is retained, as in the pinned Python input parser.
        var override = draft
        override.customRoles[.foreman]?.reasoningEffort = "high"
        #expect(try ThreadOSSettingsCodec.draft(fromFrozenInput: ThreadOSSettingsCodec.canonicalRequest(override)).customRoles[.foreman]?.reasoningEffort == "high")
    }

    @Test func requestNegativeTypesStructureAndDecodedDuplicateKeysHaveExactErrors() throws {
        let base = "TOSCFG/1 {\"p\":\"P\",\"id\":\"cfg\",\"rev\":1,\"cat\":\"astra-20260904.1\",\"preset\":\"astra-balanced\"}"
        func rejects(_ input: String, _ expected: ThreadOSSettingsCodecError) {
            #expect(throws: expected) { try ThreadOSSettingsCodec.draft(fromFrozenInput: input) }
        }
        for suffix in [",\"rev\":2", ",\"\\u0072ev\":2", ",\"rev\"\n\t\r :2"] {
            rejects(String(base.dropLast()) + suffix + "}", .duplicateJSONKey)
        }
        for scalar in ["true", "false", "null", "\"1\"", "1.0", "1e0", "0", "5", "999999999999999999999999"] {
            rejects(String(base.dropLast()) + ",\"cw\":\(scalar)}", .invalidCodingWorkers)
            rejects(String(base.dropLast()) + ",\"rw\":\(scalar)}", .invalidReviewWorkers)
        }
        for scalar in ["true", "null", "\"1\"", "1.0", "0", "1000001"] {
            rejects(base.replacingOccurrences(of: "\"rev\":1", with: "\"rev\":\(scalar)"), .invalidRevision)
        }
        for scalar in ["true", "null", "1", "[]", "{}"] {
            rejects(String(base.dropLast()) + ",\"tier\":\(scalar)}", .unsupportedTier)
            rejects(String(base.dropLast()) + ",\"apply\":\(scalar)}", .invalidApply)
        }
        rejects(base.replacingOccurrences(of: "TOSCFG/1", with: "TOSCFG/2"), .invalidProtocolPrefix)
        rejects("TOSCFG/1 {", .invalidJSON)
        rejects("TOSCFG/1 []", .requestObjectRequired)
        rejects(base + " extra", .invalidJSON)
        rejects(base.replacingOccurrences(of: "\"id\":\"cfg\",", with: ""), .invalidRequestFields)
        rejects(String(base.dropLast()) + ",\"f\":[\"coder_auto\",\"medium\"]}", .invalidRoleConfiguration)
        rejects(base.replacingOccurrences(of: "astra-balanced", with: "custom"), .invalidRoleConfiguration)
        rejects(base.replacingOccurrences(of: "astra-20260904.1", with: "unknown"), .unsupportedPreset)
    }

    @Test func wholeDraftValidityAndRevisionLimitAreNonMutating() throws {
        let valid = ThreadOSSettingsDraft(project: "P", id: "cfg")
        #expect(valid.isLocallyValid)
        var bad = valid; bad.preset = "unknown"; #expect(!bad.isLocallyValid)
        bad = valid; bad.preset = "custom"; #expect(!bad.isLocallyValid)
        bad.customRoles = ThreadOSSettingsDraft.defaultCustomRoles
        #expect(bad.isLocallyValid)
        bad.customRoles[.leader]?.model = "unknown"; #expect(!bad.isLocallyValid)
        bad.customRoles = ThreadOSSettingsDraft.defaultCustomRoles
        bad.customRoles[.leader]?.reasoningEffort = "unknown"; #expect(!bad.isLocallyValid)
        bad.customRoles = ThreadOSSettingsDraft.defaultCustomRoles
        bad.customRoles[.leader]?.model = "coder_auto"; #expect(!bad.isLocallyValid)
        var maximum = valid; maximum.revision = 1_000_000
        let saved = maximum
        #expect(!maximum.canAdvanceRevision)
        let firstAdvance = maximum.changed()
        #expect(!firstAdvance)
        #expect(maximum == saved)
        maximum.revision = Int.max
        let secondAdvance = maximum.changed()
        #expect(!secondAdvance)
        #expect(maximum.revision == Int.max)
        #expect(!ThreadOSSettingsDraft.isToken("P\n"))
    }

    @Test func fixture18SelectionAndFixture19EffectiveUnknownAreIndependent() throws {
        let acks = try #require(fixture()["acknowledgements"] as? [[String: Any]])
        for id in ["18-pending-native-selection", "19-unknown-effective-model"] {
            let input = try #require(acks.first { $0["id"] as? String == id }?["input"] as? [String: Any])
            let projection = try #require(ThreadOSSettingsCodec.receiptProjection(try canonicalJSON(input)))
            #expect(projection.selection == .pendingNativeSelection)
            #expect(projection.effectiveModel == .unknown)
            #expect(!projection.authenticatesProject)
            #expect(projection.configured?.roles.values.allSatisfy { $0.effectiveObserved == .unknown } == true)
        }
    }

    @Test func receiptSchemaRejectsMutationsInEveryContainerAndRawDuplicateKeys() throws {
        let cases = try #require(fixture()["cases"] as? [[String: Any]])
        let receipts = cases.flatMap { $0["steps"] as? [[String: Any]] ?? [] }.compactMap { ($0["expected"] as? [String: Any])?["receipt"] as? [String: Any] }
        for receipt in receipts {
            for key in receipt.keys {
                var missing = receipt; missing.removeValue(forKey: key)
                #expect(ThreadOSSettingsCodec.receiptProjection(try canonicalJSON(missing)) == nil)
            }
            var extra = receipt; extra["extra"] = true
            #expect(ThreadOSSettingsCodec.receiptProjection(try canonicalJSON(extra)) == nil)
            let text = try canonicalJSON(receipt)
            for key in ["status", "\\u0073tatus"] {
                let duplicate = String(text.dropLast()) + ",\"\(key)\"\n\t :\"error\"}"
                #expect(ThreadOSSettingsCodec.receiptProjection(duplicate) == nil)
            }
            if text.contains("\"requested_model\":") {
                let duplicate = text.replacingOccurrences(of: "\"requested_model\":", with: "\"\\u0072equested_model\"\r\n :\"gpt-6-astra\",\"requested_model\":")
                #expect(ThreadOSSettingsCodec.receiptProjection(duplicate) == nil)
            }
            for mutation in receiptMutations(receipt) {
                #expect(ThreadOSSettingsCodec.receiptProjection(try canonicalJSON(mutation)) == nil)
            }
        }
    }

    /// Independently mutates each nested object; repeated role field names across sibling
    /// objects must remain legal while duplicates within one object are rejected.
    private func receiptMutations(_ object: [String: Any]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        for (key, value) in object {
            var replacements: [Any] = []
            if ["rev", "coding_workers", "review_workers"].contains(key) { replacements = [true, false, "1", NSNull(), 0, 1_000_001] }
            if ["preset", "status", "requested_model", "configured_model", "reasoning_effort", "catalog_revision", "schema", "protocol", "authority", "effective_from", "tier", "apply", "native_status", "mode", "pending_mode"].contains(key) { replacements += ["not-supported", true] }
            if ["id", "wave_id", "error"].contains(key) { replacements += ["bad token", "", "P\n", 1] }
            if key == "pending_native" { replacements += [[], ["LEADER"], true] as [Any] }
            if key == "effective_observed" { replacements += ["gpt-6-astra", ["LEADER": ["model": "gpt-6-astra"]]] }
            for replacement in replacements { var copy = object; copy[key] = replacement; output.append(copy) }
            if let nested = value as? [String: Any] {
                var extra = nested; extra["extra"] = true
                var copy = object; copy[key] = extra; output.append(copy)
                for nestedKey in nested.keys { var missing = nested; missing.removeValue(forKey: nestedKey); copy[key] = missing; output.append(copy) }
                for mutation in receiptMutations(nested) { copy[key] = mutation; output.append(copy) }
            }
        }
        return output
    }

    @Test func frozenRuntimeSemanticsAreSimulatedOnlyInTestsWithExactStateAndErrors() throws {
        let cases = try #require(fixture()["cases"] as? [[String: Any]])
        var operations: [String: Int] = [:]
        for scenario in cases {
            var runtime = FixtureRuntime()
            let steps = try #require(scenario["steps"] as? [[String: Any]])
            for step in steps {
                let op = try #require(step["op"] as? String)
                let expected = try #require(step["expected"] as? [String: Any])
                operations[op, default: 0] += 1
                let before = runtime.persisted
                do {
                    let receipt = try runtime.run(op, input: step["input"] as? String ?? "")
                    #expect(step["required_error"] == nil)
                    if let receipt {
                        #expect(try canonicalJSON(receipt) == canonicalJSON(#require(expected["receipt"] as? [String: Any])))
                        #expect(ThreadOSSettingsCodec.receiptProjection(try canonicalJSON(receipt)) != nil)
                    }
                } catch {
                    let code = (error as? ThreadOSSettingsCodecError)?.protocolCode ?? (error as? FixtureRuntime.Failure)?.code
                    #expect(code == step["required_error"] as? String)
                    #expect(code == (expected["receipt"] as? [String: Any])?["error"] as? String)
                    #expect(runtime.persisted == before)
                }
                if let unchanged = expected["settings_bytes_unchanged"] as? Bool { #expect((before == runtime.persisted) == unchanged) }
                if let state = expected["persisted_state_without_binding"] as? [String: Any] {
                    #expect(runtime.persisted == Data(try canonicalJSON(state).utf8))
                } else if expected["persisted_state_without_binding"] is NSNull { #expect(runtime.persisted == nil) }
                if op == "reload" { #expect(expected["module_reloaded"] as? Bool == true && runtime.persisted == before) }
                if op == "corrupt_binding" { #expect(expected["synthetic_binding_corrupted"] as? Bool == true && !runtime.bound) }
            }
        }
        #expect(operations == ["apply": 64, "start_wave": 4, "status": 2, "finish_wave": 2, "mode": 4, "reload": 1, "corrupt_binding": 1])
    }

    private func fixture() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "golden-fixtures", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func canonicalJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return try #require(String(data: data, encoding: .utf8))
    }

    private func draft(fromCanonicalRequest request: String) throws -> ThreadOSSettingsDraft? {
        guard request.hasPrefix("TOSCFG/1 "),
              let data = String(request.dropFirst("TOSCFG/1 ".count)).data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let project = value["p"] as? String,
              let id = value["id"] as? String,
              let revision = value["rev"] as? Int,
              let preset = value["preset"] as? String,
              let tier = value["tier"] as? String,
              let codingWorkers = value["cw"] as? Int,
              let reviewWorkers = value["rw"] as? Int else { return nil }
        var roles: [ThreadOSRole: ThreadOSRoleSelection] = [:]
        if preset == "custom" {
            for role in ThreadOSRole.allCases {
                guard let pair = value[role.requestKey] as? [String], pair.count == 2 else { return nil }
                roles[role] = .init(model: pair[0], reasoningEffort: pair[1])
            }
        }
        return .init(project: project, id: id, revision: revision, preset: preset, codingWorkers: codingWorkers, reviewWorkers: reviewWorkers, tier: tier, customRoles: roles)
    }
}

/// Synthetic specification exercise only. This type is test-target private and never
/// dispatches, persists native runtime state, binds a real project, or grants authority.
private struct FixtureRuntime {
    struct Failure: Error { let code: String; init(_ code: String) { self.code = code } }
    var bound = true
    var persisted: Data?
    private var state: [String: Any] = ["schema": "threados.settings-state.v1", "state_version": 1, "mode": "on", "pending_mode": NSNull(), "active": NSNull(), "pending": NSNull(), "running_wave": NSNull(), "waves": [String: Any](), "requests": [String: Any]()]
    private func bytes(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) }
    private func receipt(_ status: String, _ fields: [String: Any]) -> [String: Any] {
        fields.merging(["schema": "threados.settings-receipt.v1", "protocol": "TOSACK/1", "status": status, "authority": "settings_do_not_grant_authority"]) { _, new in new }
    }
    private func view(_ config: Any?) -> Any {
        guard let config = config as? [String: Any] else { return NSNull() }
        return config.filter { ["catalog_revision", "preset", "roles", "coding_workers", "review_workers", "tier", "apply"].contains($0.key) }
    }
    mutating func run(_ op: String, input: String) throws -> [String: Any]? {
        if op == "reload" {
            if let persisted { state = try #require(JSONSerialization.jsonObject(with: persisted) as? [String: Any]) }
            return nil
        }
        if op == "corrupt_binding" { bound = false; return nil }
        let original = state
        do {
            let result = try transition(op, input: input)
            if op != "status" { persisted = try bytes(state) }
            return result
        } catch { state = original; throw error }
    }
    private mutating func transition(_ op: String, input: String) throws -> [String: Any] {
        if op == "apply" {
            let catalog = try ThreadOSSettingsCodec.loadCatalog()
            let draft = try ThreadOSSettingsCodec.draft(fromFrozenInput: input, catalog: catalog)
            guard bound else { throw Failure("MOVED_OR_UNBOUND_PROJECT") }
            guard draft.project == "TU1_FIXTURE" else { throw Failure("FOREIGN_PROJECT") }
            let encodedView = try JSONEncoder().encode(ThreadOSSettingsCodec.configurationView(draft, catalog: catalog))
            let projected = try #require(JSONSerialization.jsonObject(with: encodedView) as? [String: Any])
            let config = projected.merging(["protocol": "TOSCFG/1", "project": draft.project, "id": draft.id, "rev": draft.revision]) { _, new in new }
            let digest = SHA256.hash(data: try bytes(config)).map { String(format: "%02x", $0) }.joined()
            var requests = try #require(state["requests"] as? [String: Any])
            var record = requests[draft.id] as? [String: Any] ?? ["highest_rev": 0, "revisions": [String: Any]()]
            var revisions = try #require(record["revisions"] as? [String: Any])
            if let existing = revisions[String(draft.revision)] as? [String: Any] {
                guard existing["digest"] as? String == digest else { throw Failure("REQUEST_CONFLICT") }
                return try #require(existing["receipt"] as? [String: Any])
            }
            guard draft.revision >= (record["highest_rev"] as? Int ?? 0) else { throw Failure("STALE_REVISION") }
            let output = receipt("pending_native_selection", ["effective_from": "next-wave", "id": draft.id, "rev": draft.revision, "preset": draft.preset, "requested": projected, "configured": projected, "effective_observed": "unknown", "pending_native": ThreadOSSettingsCodec.roleOrder.map(\.rawValue)])
            revisions[String(draft.revision)] = ["digest": digest, "receipt": output]
            record["revisions"] = revisions; record["highest_rev"] = draft.revision
            requests[draft.id] = record; state["requests"] = requests; state["pending"] = config
            return output
        }
        guard bound else { throw Failure("MOVED_OR_UNBOUND_PROJECT") }
        let running = state["running_wave"] as? [String: Any]
        switch op {
        case "mode":
            let request = try #require(JSONSerialization.jsonObject(with: Data(input.dropFirst("TOSMODE/1 ".count).utf8)) as? [String: Any])
            let mode = try #require(request["mode"] as? String)
            if mode == "off", request["when"] as? String != "idle" { throw Failure("MODE_OFF_REQUIRES_IDLE") }
            _ = try ThreadOSSettingsCodec.canonicalMode(mode: mode, when: request["when"] as? String)
            if mode == "off", running != nil { state["pending_mode"] = "off"; return receipt("mode_queued", ["mode": "off", "effective_from": "idle"]) }
            state["mode"] = mode; state["pending_mode"] = NSNull()
            return receipt("mode_updated", ["mode": mode, "effective_from": "observed"])
        case "start_wave":
            guard state["mode"] as? String == "on" else { throw Failure("MODE_OFF") }
            var waves = try #require(state["waves"] as? [String: Any])
            if let prior = waves[input] as? [String: Any] {
                guard prior["status"] as? String == "started" else { throw Failure("WAVE_ALREADY_FINISHED") }
                return try #require(prior["start_receipt"] as? [String: Any])
            }
            guard running == nil else { throw Failure("WAVE_ALREADY_RUNNING") }
            if let pending = state["pending"] as? [String: Any] { state["active"] = pending; state["pending"] = NSNull() }
            guard let active = state["active"] as? [String: Any] else { throw Failure("SETTINGS_REQUIRED") }
            state["running_wave"] = ["wave_id": input, "config": active, "mode": "on"]
            let output = receipt("wave_started", ["wave_id": input, "configured": view(active)])
            waves[input] = ["status": "started", "start_receipt": output, "finish_receipt": NSNull()]; state["waves"] = waves
            return output
        case "finish_wave":
            var waves = try #require(state["waves"] as? [String: Any])
            if let prior = waves[input] as? [String: Any], prior["status"] as? String == "finished" { return try #require(prior["finish_receipt"] as? [String: Any]) }
            guard running?["wave_id"] as? String == input else { throw Failure("WAVE_NOT_RUNNING") }
            state["running_wave"] = NSNull()
            if let pendingMode = state["pending_mode"] as? String { state["mode"] = pendingMode; state["pending_mode"] = NSNull() }
            let output = receipt("wave_finished", ["wave_id": input, "mode": try #require(state["mode"])])
            var prior = try #require(waves[input] as? [String: Any]); prior["status"] = "finished"; prior["finish_receipt"] = output; waves[input] = prior; state["waves"] = waves
            return output
        case "status":
            let wave: Any
            if let running { wave = ["wave_id": running["wave_id"] ?? NSNull(), "config": view(running["config"])] }
            else { wave = NSNull() }
            return receipt("status", ["mode": try #require(state["mode"]), "pending_mode": try #require(state["pending_mode"]), "active": view(state["active"]), "pending": view(state["pending"]), "running_wave": wave])
        default: throw Failure("UNSUPPORTED_TEST_OPERATION")
        }
    }
}
