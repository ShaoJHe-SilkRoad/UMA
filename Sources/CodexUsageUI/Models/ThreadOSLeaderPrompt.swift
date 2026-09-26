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

/// Builds a target-free request for the receiving Leader to apply to its own team.
/// This text does not authorize dispatch or establish that a native selection changed.
public enum ThreadOSLeaderPrompt {
    public static let supportedModels = [
        "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"
    ]
    public static let supportedEfforts = ["low", "medium", "high", "xhigh"]

    public static func make(
        selections: [ThreadOSPromptRole: ThreadOSPromptSelection],
        language: AppLanguage
    ) throws -> String {
        guard selections.count == ThreadOSPromptRole.allCases.count,
              ThreadOSPromptRole.allCases.allSatisfy({ role in
                  guard let selection = selections[role] else { return false }
                  return supportedModels.contains(selection.model) && supportedEfforts.contains(selection.effort)
              }) else {
            throw ThreadOSLeaderPromptError.unsupportedSelection
        }

        let selectedValues = ThreadOSPromptRole.allCases.map { role in
            let selection = selections[role]!
            return "\(role.label(for: language)): \(selection.model) / \(selection.effort)"
        }.joined(separator: "\n")

        switch language {
        case .simplifiedChinese:
            return "作为接收 Leader，请确定你自己的用户创建的物理开发根目录，并在那里核实当前角色和任务绑定。请使用受支持的原生操作，仅将以下选择应用于你自己的当前团队：\n\(selectedValues)\nCoder Cluster 和 Reviewer Cluster 的选择应在受支持时涵盖各自当前 Foremen 及已配置的子工人默认值。请分别报告请求值、实际提交值；只有经过验证时才报告为生效值。如果原生控制无法改变你自己的当前回合模型，请明确说明，并报告用户选择仍为何值。本提示仅表达请求，不构成授权，也不能证明任何原生模型选择已经发生。"
        case .english:
            return "As the receiving Leader, determine your own user-created physical development root and verify your current role and task bindings there. Use supported native operations to apply the following selections only to your own current team:\n\(selectedValues)\nWhere supported, the Coder Cluster and Reviewer Cluster selections cover their current Foremen and configured child defaults. Report requested and actually submitted values separately; report a value as effective only when verified. If native controls cannot change your own current-turn model, say so and report which user selection remains. This prompt expresses a request only; it is not authorization and does not prove that any native model selection has occurred."
        }
    }

}
