import Testing
@testable import CodexUsageUI

struct ThreadOSLeaderPromptTests {
    private let selections: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-6.1-sol", effort: "medium"),
        .coderCluster: .init(model: "gpt-5.6-terra", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-5.6-terra", effort: "medium"),
        .qa: .init(model: "gpt-5.6-sol", effort: "high")
    ]
    private let variedSelections: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-5.6-terra", effort: "xhigh"),
        .coderCluster: .init(model: "gpt-6.1-sol", effort: "low"),
        .reviewerCluster: .init(model: "gpt-6-astra", effort: "high"),
        .qa: .init(model: "gpt-6-luna", effort: "medium")
    ]

    @Test func exposesExactlyFiveModelsAndFourEfforts() {
        #expect(ThreadOSLeaderPrompt.supportedModels == [
            "gpt-6.1-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"
        ])
        #expect(ThreadOSLeaderPrompt.supportedEfforts == ["low", "medium", "high", "xhigh"])
    }

    @Test func generatesChinesePromptMappingAllFourIndependentSelections() throws {
        let prompt = try ThreadOSLeaderPrompt.make(selections: selections, language: .simplifiedChinese)

        #expect(prompt.contains("Leader: gpt-6.1-sol / medium"))
        #expect(prompt.contains("Coder Cluster: gpt-5.6-terra / medium"))
        #expect(prompt.contains("Reviewer Cluster: gpt-5.6-terra / medium"))
        #expect(prompt.contains("QA: gpt-5.6-sol / high"))
        #expect(prompt.contains("用户创建的物理开发根目录"))
        #expect(prompt.contains("当前角色和任务绑定"))
        #expect(prompt.contains("将选择应用于你自己的当前团队"))
        #expect(prompt.contains("在受支持的项目管理设置通路中更新相关 Foremen 和子工人默认值"))
        #expect(prompt.contains("请求值、已提交值和经验证的生效值"))
        #expect(prompt.hasPrefix("现在请执行"))
        #expect(prompt.contains("粘贴此命令即表示用户已授权"))
        #expect(prompt.contains("不要再要求通用、逐角色或逐文件确认"))
        #expect(prompt.contains("准确说明具体限制并继续执行其他独立支持的角色"))
        #expect(prompt.contains("不要中断正在运行的回合"))
        #expect(prompt.contains("只通过当前任务的原生通信通知另外三个已核实绑定的角色线程：Coder Cluster、Reviewer Cluster 和 QA；不要通知 Leader 自己"))
        #expect(prompt.contains("不要向自己发送或重放此命令"))
        #expect(prompt.contains("请在当前任务中报告你自己的结果"))
        #expect(prompt.contains("model: \"gpt-5.6-terra\"`"))
        #expect(prompt.contains("thinking: \"medium\"`"))
        #expect(prompt.contains("model: \"gpt-5.6-sol\"`"))
        #expect(prompt.contains("thinking: \"high\"`"))
        #expect(prompt.contains("在当前任务使用原生 Model 与 Thinking 控件"))
        #expect(prompt.contains("将后续回合设为 \(expectedNativeParameterValues(selections[.leader]!))"))
        #expect(!prompt.contains("仅表达请求，不构成授权"))
        assertTargetFree(prompt)
    }

    @Test func generatesEnglishPromptMappingAllFourIndependentSelections() throws {
        let prompt = try ThreadOSLeaderPrompt.make(selections: selections, language: .english)

        #expect(prompt.contains("Leader: gpt-6.1-sol / medium"))
        #expect(prompt.contains("Coder Cluster: gpt-5.6-terra / medium"))
        #expect(prompt.contains("Reviewer Cluster: gpt-5.6-terra / medium"))
        #expect(prompt.contains("QA: gpt-5.6-sol / high"))
        #expect(prompt.contains("user-created physical development root"))
        #expect(prompt.contains("verify your current role and task bindings"))
        #expect(prompt.contains("apply these selections to your own current team"))
        #expect(prompt.contains("Update applicable Foremen and child defaults through the supported project-managed settings route"))
        #expect(prompt.contains("Distinguish requested, submitted, and verified-effective values"))
        #expect(prompt.hasPrefix("Execute these model and reasoning-effort settings now."))
        #expect(prompt.contains("Pasting this command is the user's authorization"))
        #expect(prompt.contains("Do not ask for general, per-role, or per-file reconfirmation"))
        #expect(prompt.contains("state the specific limitation accurately and continue with independently supported roles"))
        #expect(prompt.contains("Do not interrupt a running turn"))
        #expect(prompt.contains("only for the other three verified bound role threads: Coder Cluster, Reviewer Cluster, and QA; do not notify the Leader recipient itself"))
        #expect(prompt.contains("Do not send or replay this command to yourself"))
        #expect(prompt.contains("report your own result in this current task"))
        #expect(prompt.contains("model: \"gpt-5.6-terra\"`"))
        #expect(prompt.contains("thinking: \"medium\"`"))
        #expect(prompt.contains("model: \"gpt-5.6-sol\"`"))
        #expect(prompt.contains("thinking: \"high\"`"))
        #expect(prompt.contains("use this task's native Model and Thinking controls to set future turns to \(expectedNativeParameterValues(selections[.leader]!))"))
        #expect(!prompt.contains("request only; it is not authorization"))
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

    @Test func mapsEverySupportedModelAndEffortToItsOwnRoleInBothLanguages() throws {
        let distinctBaseline: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
            .leader: .init(model: "gpt-6.1-sol", effort: "low"),
            .coderCluster: .init(model: "gpt-5.6-terra", effort: "medium"),
            .reviewerCluster: .init(model: "gpt-6-luna", effort: "high"),
            .qa: .init(model: "gpt-5.6-sol", effort: "xhigh")
        ]
        let recipientRoles: [ThreadOSPromptRole] = [.coderCluster, .reviewerCluster, .qa]

        for targetRole in ThreadOSPromptRole.allCases {
            for model in ThreadOSLeaderPrompt.supportedModels {
                for effort in ThreadOSLeaderPrompt.supportedEfforts {
                    var current = distinctBaseline
                    current[targetRole] = .init(model: model, effort: effort)

                    for language in [AppLanguage.simplifiedChinese, .english] {
                        let prompt = try ThreadOSLeaderPrompt.make(selections: current, language: language)
                        let target = current[targetRole]!
                        #expect(prompt.contains("\(targetRole.label(for: language)): \(target.model) / \(target.effort)"))

                        for role in recipientRoles {
                            let assigned = current[role]!
                            #expect(prompt.contains(expectedNativeParameters(role, assigned, language)))
                        }

                        if targetRole == .leader {
                            let leaderArguments = expectedNativeParameterValues(target)
                            if language == .english {
                                #expect(prompt.contains("set your own Leader selection to \(leaderArguments)"))
                                #expect(prompt.contains("set future turns to \(leaderArguments)"))
                            } else {
                                #expect(prompt.contains("使用它将自己的 Leader 选择设为 \(leaderArguments)"))
                                #expect(prompt.contains("将后续回合设为 \(leaderArguments)"))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func variedRoleSelectionsDoNotReuseTheR2FixtureTuple() throws {
        let chinese = try ThreadOSLeaderPrompt.make(selections: variedSelections, language: .simplifiedChinese)
        let english = try ThreadOSLeaderPrompt.make(selections: variedSelections, language: .english)
        for (prompt, language) in [(chinese, AppLanguage.simplifiedChinese), (english, .english)] {
            for role in ThreadOSPromptRole.allCases {
                let selection = variedSelections[role]!
                #expect(prompt.contains("\(role.label(for: language)): \(selection.model) / \(selection.effort)"))
                if role != .leader {
                    #expect(prompt.contains(expectedNativeParameters(role, selection, language)))
                }
            }
        }

        #expect(chinese.contains("使用它将自己的 Leader 选择设为 \(expectedNativeParameterValues(variedSelections[.leader]!))"))
        #expect(chinese.contains("将后续回合设为 \(expectedNativeParameterValues(variedSelections[.leader]!))"))
        #expect(english.contains("set your own Leader selection to \(expectedNativeParameterValues(variedSelections[.leader]!))"))
        #expect(english.contains("set future turns to \(expectedNativeParameterValues(variedSelections[.leader]!))"))

        #expect(!chinese.contains("Coder Cluster `model: \"gpt-5.6-terra\"`, `thinking: \"medium\"`"))
        #expect(!chinese.contains("Reviewer Cluster `model: \"gpt-5.6-terra\"`, `thinking: \"medium\"`"))
        #expect(!chinese.contains("QA `model: \"gpt-5.6-sol\"`, `thinking: \"high\"`"))
        #expect(!chinese.contains("Leader `model: \"gpt-6.1-sol\"`, `thinking: \"medium\"`"))
        #expect(!english.contains("Coder Cluster `model: \"gpt-5.6-terra\"`, `thinking: \"medium\"`"))
        #expect(!english.contains("Reviewer Cluster `model: \"gpt-5.6-terra\"`, `thinking: \"medium\"`"))
        #expect(!english.contains("QA `model: \"gpt-5.6-sol\"`, `thinking: \"high\"`"))
        #expect(!english.contains("Leader `model: \"gpt-6.1-sol\"`, `thinking: \"medium\"`"))
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

    private func expectedNativeParameters(
        _ role: ThreadOSPromptRole,
        _ selection: ThreadOSPromptSelection,
        _ language: AppLanguage
    ) -> String {
        "\(role.label(for: language)) \(expectedNativeParameterValues(selection))"
    }

    private func expectedNativeParameterValues(_ selection: ThreadOSPromptSelection) -> String {
        "`model: \"\(selection.model)\"`, `thinking: \"\(selection.effort)\"`"
    }
}
