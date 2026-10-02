import Foundation

public enum ThreadOSLeaderPromptError: Error, Equatable {
    case unsupportedSelection
}

public enum ThreadOSPromptRole: String, CaseIterable, Hashable, Sendable, Codable {
    case leader
    case coderCluster
    case reviewerCluster
    case qa

    func label(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.leader, .simplifiedChinese): return "Leader"
        case (.coderCluster, .simplifiedChinese): return "Coder Cluster"
        case (.reviewerCluster, .simplifiedChinese): return "Reviewer Cluster"
        case (.qa, .simplifiedChinese): return "QA"
        case (.leader, .english): return "Leader"
        case (.coderCluster, .english): return "Coder Cluster"
        case (.reviewerCluster, .english): return "Reviewer Cluster"
        case (.qa, .english): return "QA"
        }
    }
}

public struct ThreadOSPromptSelection: Equatable, Sendable, Codable {
    public let model: String
    public let effort: String

    public init(model: String, effort: String) {
        self.model = model
        self.effort = effort
    }
}

/// Builds a target-free executable instruction for the receiving Leader to apply its own team settings.
public enum ThreadOSLeaderPrompt {
    public static let supportedModels = [
        "gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"
    ]
    public static let supportedEfforts = ["low", "medium", "high", "xhigh"]

    public static func make(
        selections: [ThreadOSPromptRole: ThreadOSPromptSelection],
        language _: AppLanguage
    ) throws -> String {
        guard selections.count == ThreadOSPromptRole.allCases.count,
              ThreadOSPromptRole.allCases.allSatisfy({ role in
                  guard let selection = selections[role] else { return false }
                  return supportedModels.contains(selection.model) && supportedEfforts.contains(selection.effort)
        }) else {
            throw ThreadOSLeaderPromptError.unsupportedSelection
        }

        let roles = Dictionary(uniqueKeysWithValues: ThreadOSPromptRole.allCases.map { role in
            let selection = selections[role]!
            return (role.rawValue, ["model": selection.model, "thinking": selection.effort])
        })
        let command: [String: Any] = [
            "op": "set_team_models",
            "scope": "receiving_leader_bound_root",
            "roles": roles,
            "execution": [
                "parallel_native_dispatch": true,
                "only_bound_roles": true,
                "no_self_dispatch": true,
                "no_interrupt": true,
                "update_foremen_and_child_defaults": true,
                "no_routine_confirmation": true,
                "minimal_recording": true,
                "respect_host_restrictions": true,
                "report_values": ["requested", "submitted", "effective"],
                "leader_control": "native_control_or_manual"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: command, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ThreadOSLeaderPromptError.unsupportedSelection
        }
        return json
    }

#if false // Superseded by the compact JSON command above.
    private static func legacyPrompt(
        selections: [ThreadOSPromptRole: ThreadOSPromptSelection],
        language: AppLanguage
    ) -> String {

        let selectedValues = ThreadOSPromptRole.allCases.map { role in
            let selection = selections[role]!
            return "\(role.label(for: language)): \(selection.model) / \(selection.effort)"
        }.joined(separator: "\n")
        let nativeParameters = nativeParameterAssignments(selections: selections, language: language)
        let leaderParameters = nativeParameterValues(for: selections[.leader]!)

        switch language {
        case .simplifiedChinese:
            return "现在请执行以下模型和思考档位设置。作为接收 Leader，请确定你自己的用户创建的物理开发根目录，并在那里核实当前角色和任务绑定。使用受支持的原生操作，将选择应用于你自己的当前团队：\n\(selectedValues)\n只通过当前任务的原生通信通知另外三个已核实绑定的角色线程：Coder Cluster、Reviewer Cluster 和 QA；不要通知 Leader 自己。对这些角色及后续原生调用，必须把各自的选择作为真实原生参数传入，而不只是写在消息正文中：\(nativeParameters)。在受支持的项目管理设置通路中更新相关 Foremen 和子工人默认值；遇到已有值冲突时不得静默覆盖。不要中断正在运行的回合，也不要发送仅用于显示切换的空状态回合。不要向自己发送或重放此命令，也不要发起自我定向模型/状态回合来切换设置；请在当前任务中报告你自己的结果。仅在确实存在受支持的原生未来回合模型与思考档位控件时，使用它将自己的 Leader 选择设为 \(leaderParameters)。若此控件不可用，准确说明限制，并向 Founder 给出这项具体手动操作：在当前任务使用原生 Model 与 Thinking 控件，将后续回合设为 \(leaderParameters)；这只是操作说明，不是重新申请授权。不要用新的 Leader 默认值或全局默认值替代。粘贴此命令即表示用户已授权这项有界设置操作；不要再要求通用、逐角色或逐文件确认，也不要停在检查或计划。逐项区分请求值、已提交值和经验证的生效值。遇到主机限制、拒绝、不支持的组合或不可用的原生控制时，准确说明具体限制并继续执行其他独立支持的角色，不要静默替换或声称已生效。不得超出本团队模型与思考档位设置范围，也不得更改全局设置、调用 Sage 或开展产品开发。"
        case .english:
            return "Execute these model and reasoning-effort settings now. As the receiving Leader, determine your own user-created physical development root and verify your current role and task bindings there. Use supported native operations to apply these selections to your own current team:\n\(selectedValues)\nUse native communication in this task only for the other three verified bound role threads: Coder Cluster, Reviewer Cluster, and QA; do not notify the Leader recipient itself. For these roles and subsequent native calls, pass each role's own selections as actual native parameters, not only in message text: \(nativeParameters). Update applicable Foremen and child defaults through the supported project-managed settings route; do not silently overwrite conflicting existing values. Do not interrupt a running turn or send an empty status-only turn to display a switch. Do not send or replay this command to yourself, and do not initiate a self-directed model/status turn to switch settings; report your own result in this current task. Only if an actually supported native future-turn Model and Thinking control exists, use it to set your own Leader selection to \(leaderParameters). If unavailable, state that limitation accurately and give the Founder this concrete manual action: use this task's native Model and Thinking controls to set future turns to \(leaderParameters); this is an operational instruction, not a request for reauthorization. Do not substitute a new Leader default or global default. Pasting this command is the user's authorization for this bounded settings operation. Do not ask for general, per-role, or per-file reconfirmation, and do not stop after inspection or planning. Distinguish requested, submitted, and verified-effective values for each role. If a host restriction, refusal, unsupported combination, or unavailable native control blocks a change, state the specific limitation accurately and continue with independently supported roles; do not silently substitute a value or claim activation. Keep the scope to these team model and effort settings; do not change global settings, invoke Sage, or start product development."
        }
    }

    private static func nativeParameterAssignments(
        selections: [ThreadOSPromptRole: ThreadOSPromptSelection],
        language: AppLanguage
    ) -> String {
        [ThreadOSPromptRole.coderCluster, .reviewerCluster, .qa].map { role in
            let selection = selections[role]!
            return "\(role.label(for: language)) \(nativeParameterValues(for: selection))"
        }.joined(separator: language == .english ? "; " : "；")
    }

    private static func nativeParameterValues(for selection: ThreadOSPromptSelection) -> String {
        "`model: \"\(selection.model)\"`, `thinking: \"\(selection.effort)\"`"
    }
#endif

}
