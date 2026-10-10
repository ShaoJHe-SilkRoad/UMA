import Foundation
import Testing
@testable import CodexUsageUI

@MainActor
struct ThreadOSUltraTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func metadata(_ efforts: Set<String>, age: Double = 0) -> ThreadOSCapabilities {
        .init(models: ["gpt-6.1-sol": efforts], observedAt: date.addingTimeInterval(-age), client: "synthetic", now: date)
    }
    @Test func exactWireAndPersistence() throws {
        let prefs = ApplicationPreferences.inMemory()
        let caps = metadata(["low", "medium", "high", "xhigh", "ultra"])
        let form = ThreadOSPromptComposerForm(preferences: prefs, capabilities: caps)
        let coder = form.selection(for: .coderCluster)
        form.selectEffort("ultra", for: .leader)
        let wire = try #require(form.generatedInstruction)
        let value = try #require(JSONSerialization.jsonObject(with: Data(wire.utf8)) as? [String: Any])
        let roles = try #require(value["roles"] as? [String: [String: String]])
        #expect(roles["leader"]?["thinking"] == "ultra")
        #expect(form.selection(for: .coderCluster) == coder)
        #expect(ThreadOSPromptComposerForm(preferences: prefs, capabilities: caps).generatedInstruction == wire)
        #expect(try ThreadOSLeaderPrompt.make(selections: form.selections, language: .simplifiedChinese, capabilities: caps) == wire)
        let clipboard = UltraClipboard()
        #expect(form.generateAndCopy(language: .english, to: clipboard) == .copied)
        #expect(clipboard.value == wire)
    }
    @Test func rejectsUnsupportedAndPreservesModel() {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory(), capabilities: metadata(["high", "ultra"]))
        form.selectEffort("ultra", for: .leader)
        let before = form.selection(for: .leader)
        form.selectModel("gpt-6-luna", for: .leader)
        #expect(form.selection(for: .leader) == before)
        #expect(form.selectionError != nil)
        #expect(form.ultraAvailability(for: .coderCluster) == .unsupported)
        form.selectEffort("ultra", for: .coderCluster)
        #expect(form.selection(for: .coderCluster).effort == "medium")
    }
    @Test func currentClientCanRejectUltra() {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory(), capabilities: metadata(["low", "medium", "high", "xhigh"]))
        form.selectEffort("ultra", for: .leader)
        #expect(form.selection(for: .leader).effort == "high")
        #expect(form.ultraAvailability(for: .leader) == .unsupported)
    }
    @Test(arguments: [ThreadOSCapabilities.unverified, ThreadOSCapabilities(models: ["gpt-6.1-sol": ["high"]], observedAt: Date(timeIntervalSince1970: 1), client: "stale")])
    func pendingOfflineIsExactAndTruthful(caps: ThreadOSCapabilities) throws {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory(), capabilities: caps)
        form.selectEffort("ultra", for: .leader)
        #expect(form.selection(for: .leader).effort == "ultra")
        #expect(form.canGenerate)
        #expect(form.ultraAvailability(for: .leader) == .unverified)
        #expect(form.statusMessage(language: .english)?.contains("pending verification") == true)
        #expect(try #require(form.generatedInstruction).contains("ultra"))
    }
    @Test func realCacheFormatsAndMalformedData() {
        let data = Data("{\"fetched_at\":\"2027-01-15T08:00:00Z\",\"client_version\":\"test\",\"models\":[{\"slug\":\"gpt-6-sol\",\"supported_reasoning_levels\":[{\"effort\":\"ultra\"}]}]}".utf8)
        let now = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
        #expect(ThreadOSCapabilities.decode(data, now: now).availability(model: "gpt-6-sol", effort: "ultra") == .supported)
        #expect(ThreadOSCapabilities.decode(Data("{}".utf8)).availability(model: "gpt-6-sol", effort: "ultra") == .unverified)
    }
    @Test func capabilityChangeBeforeCopyCannotProduceStaleSupportedInstruction() {
        var caps = metadata(["high", "ultra"])
        let form = ThreadOSPromptComposerForm(preferences: .inMemory(), capabilityProvider: { caps })
        form.selectEffort("ultra", for: .leader)
        caps = metadata(["high"])
        let clipboard = UltraClipboard()
        #expect(form.generateAndCopy(language: .english, to: clipboard) == .unavailable)
        #expect(clipboard.value == nil)
        #expect(form.selection(for: .leader).effort == "ultra")
    }
    @Test func malformedAndAmbiguousMetadataStayUnverified() throws {
        for rows: [[String: Any]] in [
            [["slug":"gpt-6-sol","supported_reasoning_levels":[["effort":"high"],["effort":42]]]],
            Array(repeating: ["slug":"gpt-6-sol","supported_reasoning_levels":[["effort":"ultra"]]], count: 3)
        ] {
            let data = try JSONSerialization.data(withJSONObject: ["fetched_at":"2027-01-15T08:00:00Z","models":rows])
            let now = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
            #expect(ThreadOSCapabilities.decode(data, now: now).availability(model:"gpt-6-sol",effort:"ultra") == .unverified)
        }
    }
    @Test func versionedUltraDraftRoundTripsWithoutChangingOldCatalog() throws {
        for model in ThreadOSLeaderPrompt.supportedModels {
            for effort in ThreadOSLeaderPrompt.supportedEfforts {
                var draft = FactoriumV2SettingsDraft(project:"SYNTHETIC_ULTRA",catalogRevision:ThreadOSSettingsCodec.ultraCatalogRevision)
                draft.roles[.qa]?.selection = .init(model:model,effort:effort,speed:"standard")
                if model == "gpt-6-luna" && effort == "ultra" {
                    #expect(throws:(any Error).self) { try draft.canonicalRequest() }
                } else {
                    let wire = try draft.canonicalRequest()
                    #expect(try FactoriumV2SettingsCodec.draft(fromWire:wire) == draft)
                    #expect(wire.contains("\"effort\":\"" + effort + "\""))
                }
            }
        }
    }
    @Test func immutableCatalogCompatibility() throws {
        let old = try ThreadOSSettingsCodec.loadCatalog(revision: "sol-luna-20261001.1")
        let new = try ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.ultraCatalogRevision)
        #expect(old.models["gpt-6.1-sol"]?.reasoningEfforts.contains("ultra") == false)
        #expect(new.models["gpt-6.1-sol"]?.reasoningEfforts.contains("ultra") == true)
        #expect(new.models["gpt-6-luna"]?.reasoningEfforts.contains("ultra") == false)
        #expect(ThreadOSPromptComposerForm.defaultSelections.values.allSatisfy { $0.effort != "ultra" })
    }
}
@MainActor private final class UltraClipboard: ThreadOSSettingsClipboard {
    var value: String?
    func write(_ value: String) -> Bool { self.value = value; return true }
    func read() -> String? { value }
}
