import Testing
@testable import CodexUsageUI

struct ThreadOSLeaderPromptTests {
    private let selections: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-6.1-sol", effort: "low"),
        .coderCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-6-astra", effort: "high"),
        .qa: .init(model: "gpt-5.6-terra", effort: "xhigh")
    ]

    @Test func exposesExactlyFiveModelsAndFourEfforts() {
        #expect(ThreadOSLeaderPrompt.supportedModels == [
            "gpt-6.1-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"
        ])
        #expect(ThreadOSLeaderPrompt.supportedEfforts == ["low", "medium", "high", "xhigh"])
    }

    @Test func generatesChinesePromptMappingAllFourIndependentSelections() throws {
        let prompt = try ThreadOSLeaderPrompt.make(selections: selections, language: .simplifiedChinese)

        #expect(prompt.contains("Leader: gpt-6.1-sol / low"))
        #expect(prompt.contains("Coder Cluster: gpt-6-luna / medium"))
        #expect(prompt.contains("Reviewer Cluster: gpt-6-astra / high"))
        #expect(prompt.contains("QA: gpt-5.6-terra / xhigh"))
        #expect(prompt.contains("用户创建的物理开发根目录"))
        #expect(prompt.contains("当前角色和任务绑定"))
        #expect(prompt.contains("仅将以下选择应用于你自己的当前团队"))
        #expect(prompt.contains("当前 Foremen 及已配置的子工人默认值"))
        #expect(prompt.contains("请求值、实际提交值"))
        #expect(prompt.contains("不能证明任何原生模型选择已经发生"))
        assertTargetFree(prompt)
    }

    @Test func generatesEnglishPromptMappingAllFourIndependentSelections() throws {
        let prompt = try ThreadOSLeaderPrompt.make(selections: selections, language: .english)

        #expect(prompt.contains("Leader: gpt-6.1-sol / low"))
        #expect(prompt.contains("Coder Cluster: gpt-6-luna / medium"))
        #expect(prompt.contains("Reviewer Cluster: gpt-6-astra / high"))
        #expect(prompt.contains("QA: gpt-5.6-terra / xhigh"))
        #expect(prompt.contains("user-created physical development root"))
        #expect(prompt.contains("verify your current role and task bindings"))
        #expect(prompt.contains("only to your own current team"))
        #expect(prompt.contains("current Foremen and configured child defaults"))
        #expect(prompt.contains("requested and actually submitted values separately"))
        #expect(prompt.contains("does not prove that any native model selection has occurred"))
        assertTargetFree(prompt)
    }

    @Test func everySupportedModelAndEffortCanAppearInSelection() throws {
        for model in ThreadOSLeaderPrompt.supportedModels {
            for effort in ThreadOSLeaderPrompt.supportedEfforts {
                var values = selections
                values[.leader] = .init(model: model, effort: effort)
                let prompt = try ThreadOSLeaderPrompt.make(selections: values, language: .english)
                #expect(prompt.contains("Leader: \(model) / \(effort)"))
            }
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
}
