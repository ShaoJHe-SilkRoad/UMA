import Testing
@testable import CodexUsageUI

struct ThreadOSLeaderPromptTests {
    private func loadCatalog() throws -> ThreadOSModelCatalog {
        try ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.latestCatalogRevision)
    }

    @Test func generatesChinesePromptWithSelectedCatalogValuesAndSafeIntent() throws {
        let catalog = try loadCatalog()
        let prompt = try ThreadOSLeaderPrompt.make(
            model: "gpt-6-luna",
            effort: "medium",
            language: .simplifiedChinese,
            catalog: catalog
        )

        #expect(prompt.contains("gpt-6-luna"))
        #expect(prompt.contains("medium"))
        #expect(prompt.contains("接收 Leader"))
        #expect(prompt.contains("物理开发根目录"))
        #expect(prompt.contains("自行决定"))
        #expect(prompt.contains("原生派工或选择"))
        #expect(prompt.contains("报告实际结果"))
        #expect(prompt.contains("不表示任何原生选择已经生效"))
        #expect(!prompt.contains("TOSCFG/2"))
    }

    @Test func generatesEnglishPromptWithSelectedCatalogValuesAndSafeIntent() throws {
        let catalog = try loadCatalog()
        let prompt = try ThreadOSLeaderPrompt.make(
            model: "gpt-6-sol",
            effort: "high",
            language: .english,
            catalog: catalog
        )

        #expect(prompt.contains("gpt-6-sol"))
        #expect(prompt.contains("high"))
        #expect(prompt.contains("As the receiving Leader"))
        #expect(prompt.contains("physical development root"))
        #expect(prompt.contains("decide which tasks"))
        #expect(prompt.contains("native dispatch or selection"))
        #expect(prompt.contains("report the actual outcome"))
        #expect(prompt.contains("does not mean any native selection has taken effect"))
    }

    @Test func rejectsUnknownModelAndIllegalEffortCombination() throws {
        let catalog = try loadCatalog()
        #expect(throws: ThreadOSLeaderPromptError.unsupportedSelection) {
            try ThreadOSLeaderPrompt.make(
                model: "not-in-the-catalog",
                effort: "medium",
                language: .english,
                catalog: catalog
            )
        }

        #expect(throws: ThreadOSLeaderPromptError.unsupportedSelection) {
            try ThreadOSLeaderPrompt.make(
                model: "gpt-6-luna",
                effort: "not-a-catalog-effort",
                language: .simplifiedChinese,
                catalog: catalog
            )
        }
    }

    @Test func generatedPromptContainsNoProjectTaskIdPathOrRoleTargets() throws {
        let catalog = try loadCatalog()
        let prompt = try ThreadOSLeaderPrompt.make(
            model: "gpt-6-luna",
            effort: "medium",
            language: .english,
            catalog: catalog
        )
        let forbidden = [
            "TOSUMA",
            "project_key",
            "project_id",
            "task_id",
            "task-id",
            "taskId",
            "thread_id",
            "LEADER_TASK",
            "/Volumes/",
            "/Users/",
            "/private/",
            "TOSCFG/2",
            "\"p\"",
            "\"p\":",
            "Coder",
            "Reviewer",
            "QA",
            "Repair",
            "worker",
            "role_target",
            "worker_id",
            "host permission",
            "host authorization",
            "grant host",
            "宿主授权",
            "主机权限"
        ]

        for value in forbidden {
            #expect(!prompt.localizedCaseInsensitiveContains(value))
        }
    }
}
