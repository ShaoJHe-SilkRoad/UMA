import Foundation
import Testing
@testable import CodexUsageUI

struct ThreadOSLeaderPromptTests {
    private let selections: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-6.1-sol", effort: "medium"),
        .coderCluster: .init(model: "gpt-5.6-terra", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-5.6-terra", effort: "medium"),
        // Was gpt-5.6-sol, which the current catalog does not carry, so every
        // case built on this fixture was refused before it asserted anything.
        .qa: .init(model: "gpt-6-luna", effort: "high")
    ]
    private let variedSelections: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-5.6-terra", effort: "xhigh"),
        .coderCluster: .init(model: "gpt-6.1-sol", effort: "low"),
        .reviewerCluster: .init(model: "gpt-6-astra", effort: "high"),
        .qa: .init(model: "gpt-6-luna", effort: "medium")
    ]

    /// Renamed from `exposesExactlySixModelsAndFourEfforts`: `ultra` arrived, so
    /// there are five efforts. What the lists advertise and what a selection is
    /// allowed to be are no longer the same question — the catalog decides the
    /// second, per model — which is why the tests below ask the catalog.
    @Test func exposesSixModelsAndFiveEfforts() {
        #expect(ThreadOSLeaderPrompt.supportedModels == [
            "gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"
        ])
        #expect(ThreadOSLeaderPrompt.supportedEfforts == ["low", "medium", "high", "xhigh", "ultra"])
    }

    /// Pairs the current catalog accepts, so a test iterates what is usable
    /// rather than the raw cross-product of the two advertised lists.
    private var catalogAllowedPairs: [(model: String, effort: String)] {
        ThreadOSLeaderPrompt.supportedModels.flatMap { model in
            ThreadOSLeaderPrompt.supportedEfforts
                .filter { ThreadOSCapabilities.catalogAllows(model: model, effort: $0) }
                .map { (model, $0) }
        }
    }

    @Test func generatesChinesePromptMappingAllFourIndependentSelections() throws {
        let prompt = try ThreadOSLeaderPrompt.make(selections: selections, language: .simplifiedChinese)
        try assertCommand(prompt, selections: selections)
    }

    @Test func generatesEnglishPromptMappingAllFourIndependentSelections() throws {
        let prompt = try ThreadOSLeaderPrompt.make(selections: selections, language: .english)
        try assertCommand(prompt, selections: selections)
    }

    /// Was a raw cross-product of the two lists. That held while every model
    /// offered the same efforts; `ultra` ended it, and a model the current
    /// catalog does not carry at all refuses every effort. The pairs the
    /// catalog allows must work, and a pair it refuses must be refused.
    @Test func everyCatalogAllowedModelAndEffortCanAppearInSelection() throws {
        let allowed = catalogAllowedPairs
        #expect(!allowed.isEmpty)
        for pair in allowed {
            var values = selections
            values[.leader] = .init(model: pair.model, effort: pair.effort)
            let prompt = try ThreadOSLeaderPrompt.make(selections: values, language: .english)
            try assertCommand(prompt, selections: values)
        }
        for model in ThreadOSLeaderPrompt.supportedModels {
            for effort in ThreadOSLeaderPrompt.supportedEfforts
            where !ThreadOSCapabilities.catalogAllows(model: model, effort: effort) {
                var values = selections
                values[.leader] = .init(model: model, effort: effort)
                #expect(throws: ThreadOSLeaderPromptError.unsupportedSelection) {
                    try ThreadOSLeaderPrompt.make(selections: values, language: .english)
                }
            }
        }
    }

    /// The baseline's QA role used `gpt-5.6-sol`, which the current catalog does
    /// not carry, so every case built on it was refused. It now uses a model
    /// that catalog has, and the loop walks catalog-allowed pairs for the same
    /// reason as the test above.
    @Test func mapsEveryCatalogAllowedModelAndEffortToItsOwnRoleInBothLanguages() throws {
        let distinctBaseline: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
            .leader: .init(model: "gpt-6.1-sol", effort: "low"),
            .coderCluster: .init(model: "gpt-5.6-terra", effort: "medium"),
            .reviewerCluster: .init(model: "gpt-6-luna", effort: "high"),
            .qa: .init(model: "gpt-6-astra", effort: "xhigh")
        ]
        for targetRole in ThreadOSPromptRole.allCases {
            for pair in catalogAllowedPairs {
                var current = distinctBaseline
                current[targetRole] = .init(model: pair.model, effort: pair.effort)

                for language in [AppLanguage.simplifiedChinese, .english] {
                    let prompt = try ThreadOSLeaderPrompt.make(selections: current, language: language)
                    try assertCommand(prompt, selections: current)
                }
            }
        }
    }

    @Test func variedRoleSelectionsDoNotReuseTheR2FixtureTuple() throws {
        let chinese = try ThreadOSLeaderPrompt.make(selections: variedSelections, language: .simplifiedChinese)
        let english = try ThreadOSLeaderPrompt.make(selections: variedSelections, language: .english)
        for prompt in [chinese, english] {
            try assertCommand(prompt, selections: variedSelections)
        }
    }

    @Test func rejectsMissingRoleAndUnsupportedModelOrEffort() {
        var missingRole = selections
        missingRole.removeValue(forKey: .qa)
        #expect(throws: ThreadOSLeaderPromptError.unsupportedSelection) {
            try ThreadOSLeaderPrompt.make(selections: missingRole, language: .english)
        }

        var unsupportedModel = selections
        unsupportedModel[.leader] = .init(model: "not-supported", effort: "medium")
        #expect(throws: ThreadOSLeaderPromptError.unsupportedSelection) {
            try ThreadOSLeaderPrompt.make(selections: unsupportedModel, language: .english)
        }

        var unsupportedEffort = selections
        unsupportedEffort[.qa] = .init(model: "gpt-6-sol", effort: "not-supported")
        #expect(throws: ThreadOSLeaderPromptError.unsupportedSelection) {
            try ThreadOSLeaderPrompt.make(selections: unsupportedEffort, language: .simplifiedChinese)
        }
    }

    private func assertTargetFree(_ prompt: String) {
        let forbidden = [
            "TOSUMA", "project_key", "project_id", "task_id", "task-id", "taskId",
            "thread_id", "LEADER_TASK", "/Volumes/", "/Users/", "/private/",
            "TOSCFG/2", "Repair", "worker_id", "role_target", "host authorization",
            "grant host", "宿主授权", "主机权限"
        ]
        for value in forbidden {
            #expect(!prompt.localizedCaseInsensitiveContains(value))
        }
    }

    private func assertCommand(
        _ prompt: String,
        selections: [ThreadOSPromptRole: ThreadOSPromptSelection]
    ) throws {
        let command = try #require(JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
        #expect(command["op"] as? String == "set_team_models")
        #expect(command["scope"] as? String == "receiving_leader_bound_root")
        let roles = try #require(command["roles"] as? [String: [String: String]])
        for role in ThreadOSPromptRole.allCases {
            let value = try #require(roles[role.rawValue])
            #expect(value["model"] == selections[role]?.model)
            #expect(value["thinking"] == selections[role]?.effort)
        }
        let execution = try #require(command["execution"] as? [String: Any])
        for field in [
            "parallel_native_dispatch", "only_bound_roles", "no_self_dispatch", "no_interrupt",
            "update_foremen_and_child_defaults", "no_routine_confirmation", "minimal_recording",
            "respect_host_restrictions"
        ] {
            #expect(execution[field] as? Bool == true)
        }
        #expect(execution["report_values"] as? [String] == ["requested", "submitted", "effective"])
        #expect(execution["leader_control"] as? String == "native_control_or_manual")
        assertTargetFree(prompt)
    }

}
