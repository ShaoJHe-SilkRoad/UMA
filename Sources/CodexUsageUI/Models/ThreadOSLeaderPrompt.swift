import Foundation

public enum ThreadOSLeaderPromptError: Error, Equatable {
    case unsupportedSelection
}

/// Builds a target-free request for a receiving Leader to review manually.
/// This text does not dispatch work or establish that a native selection changed.
public enum ThreadOSLeaderPrompt {
    public static func make(
        model: String,
        effort: String,
        language: AppLanguage,
        catalog: ThreadOSModelCatalog
    ) throws -> String {
        guard let supportedEfforts = catalog.models[model]?.reasoningEfforts,
              supportedEfforts.contains(effort) else {
            throw ThreadOSLeaderPromptError.unsupportedSelection
        }

        switch language {
        case .simplifiedChinese:
            return "作为接收 Leader，请评估将模型 \(model) 与思考档位 \(effort) 应用于你判断适用的当前任务。请先核实你负责的物理开发根目录和其中的当前任务，再自行决定此请求适用范围。若之后需要原生派工或选择，请通过受支持的原生操作进行，并报告实际结果。本提示只表达请求，不表示任何原生选择已经生效。"
        case .english:
            return "As the receiving Leader, please consider applying model \(model) with reasoning effort \(effort) to the current task or tasks you determine are in scope. First verify the physical development root you are responsible for and the active tasks there, then decide which tasks, if any, this request applies to. If native dispatch or selection is appropriate later, use supported native controls and report the actual outcome. This prompt expresses a request only; it does not mean any native selection has taken effect."
        }
    }
}
