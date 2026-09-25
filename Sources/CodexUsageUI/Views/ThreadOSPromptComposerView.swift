import SwiftUI
import AppKit
import Combine

@MainActor
enum ThreadOSPromptComposerPreferences {
    static let model = ApplicationPreferenceKey<String?>(optional: "threados.prompt.composer.model.v1")
    static let effort = ApplicationPreferenceKey<String?>(optional: "threados.prompt.composer.effort.v1")
}

enum ThreadOSPromptComposerCopyResult: Equatable {
    case copied
    case unavailable
    case clipboardFailure
}

/// Selection state for the target-free Leader prompt composer.
/// It uses only its own global preference keys and never reads project drafts.
@MainActor
final class ThreadOSPromptComposerForm: ObservableObject {
    @Published private(set) var selectedModel: String
    @Published private(set) var selectedEffort: String

    let catalog: ThreadOSModelCatalog?
    private let preferences: ApplicationPreferences

    init(catalog: ThreadOSModelCatalog?, preferences: ApplicationPreferences) {
        self.catalog = catalog
        self.preferences = preferences

        let models = catalog?.models.keys.sorted() ?? []
        let savedModel = preferences.value(for: ThreadOSPromptComposerPreferences.model)
        let model = savedModel.flatMap { models.contains($0) ? $0 : nil }
            ?? (models.contains("gpt-6-luna") ? "gpt-6-luna" : models.first ?? "")
        let efforts = catalog?.models[model]?.reasoningEfforts ?? []
        let savedEffort = preferences.value(for: ThreadOSPromptComposerPreferences.effort)
        selectedModel = model
        selectedEffort = savedEffort.flatMap { efforts.contains($0) ? $0 : nil }
            ?? (efforts.contains("medium") ? "medium" : efforts.first ?? "")
    }

    var modelOptions: [String] { catalog?.models.keys.sorted() ?? [] }
    var effortOptions: [String] { catalog?.models[selectedModel]?.reasoningEfforts ?? [] }
    var canGenerate: Bool { !selectedModel.isEmpty && effortOptions.contains(selectedEffort) }

    func selectModel(_ model: String) {
        guard modelOptions.contains(model), model != selectedModel else { return }
        selectedModel = model
        let efforts = effortOptions
        if !efforts.contains(selectedEffort) {
            selectedEffort = efforts.contains("medium") ? "medium" : efforts.first ?? ""
        }
        persistSelection()
    }

    func selectEffort(_ effort: String) {
        guard effortOptions.contains(effort), effort != selectedEffort else { return }
        selectedEffort = effort
        persistSelection()
    }

    func generateAndCopy(
        language: AppLanguage,
        to clipboard: any ThreadOSSettingsClipboard
    ) -> ThreadOSPromptComposerCopyResult {
        guard let catalog, canGenerate,
              let prompt = try? ThreadOSLeaderPrompt.make(
                model: selectedModel,
                effort: selectedEffort,
                language: language,
                catalog: catalog
              ) else {
            return .unavailable
        }
        return clipboard.write(prompt) ? .copied : .clipboardFailure
    }

    private func persistSelection() {
        preferences.set(selectedModel, for: ThreadOSPromptComposerPreferences.model)
        preferences.set(selectedEffort, for: ThreadOSPromptComposerPreferences.effort)
    }
}

/// A compact, independent surface for creating and copying a request to a receiving Leader.
/// It does not dispatch work or alter native model selection.
public struct ThreadOSPromptComposerView: View {
    @StateObject private var form: ThreadOSPromptComposerForm
    private let language: AppLanguage
    private let clipboard: any ThreadOSSettingsClipboard
    @State private var copyStatus: CopyStatus?

    private enum CopyStatus {
        case copied
        case failed
    }

    public init(
        language: AppLanguage = .english,
        preferences: ApplicationPreferences = .production,
        clipboard: any ThreadOSSettingsClipboard = SystemThreadOSSettingsClipboard()
    ) {
        self.language = language
        self.clipboard = clipboard
        let catalog = try? ThreadOSSettingsCodec.loadCatalog(
            revision: ThreadOSSettingsCodec.latestCatalogRevision
        )
        _form = StateObject(wrappedValue: ThreadOSPromptComposerForm(
            catalog: catalog,
            preferences: preferences
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy.title)
                    .font(.title2.weight(.semibold))
                Text(copy.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("uma.threados.prompt.description")

                Picker(copy.modelLabel, selection: Binding(
                    get: { form.selectedModel },
                    set: { form.selectModel($0) }
                )) {
                    if form.modelOptions.isEmpty {
                        Text(copy.unavailable).tag("")
                    }
                    ForEach(form.modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(form.modelOptions.isEmpty)
                .accessibilityIdentifier("uma.threados.prompt.model")

                Picker(copy.effortLabel, selection: Binding(
                    get: { form.selectedEffort },
                    set: { form.selectEffort($0) }
                )) {
                    if form.effortOptions.isEmpty {
                        Text(copy.unavailable).tag("")
                    }
                    ForEach(form.effortOptions, id: \.self) { effort in
                        Text(effortLabel(effort)).tag(effort)
                    }
                }
                .disabled(form.effortOptions.isEmpty)
                .accessibilityIdentifier("uma.threados.prompt.effort")

                Button(copy.generateAndCopy) {
                    switch form.generateAndCopy(language: language, to: clipboard) {
                    case .copied:
                        copyStatus = .copied
                    case .unavailable, .clipboardFailure:
                        copyStatus = .failed
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!form.canGenerate)
                .accessibilityIdentifier("uma.threados.prompt.generate-copy")

                if let copyStatus {
                    Text(copyStatus == .copied ? copy.copied : copy.failed)
                        .font(.callout)
                        .foregroundStyle(copyStatus == .copied ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("uma.threados.prompt.copy-status")
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var copy: Copy {
        Copy(language: language)
    }

    private func effortLabel(_ effort: String) -> String {
        guard language == .simplifiedChinese else { return effort }
        return ["low": "轻", "medium": "中", "high": "高", "xhigh": "额外高", "max": "最大", "ultra": "超高"][effort] ?? effort
    }

    private struct Copy {
        let language: AppLanguage
        var title: String { text("ThreadOS prompt", "ThreadOS 提示") }
        var description: String {
            text(
                "Choose a model and reasoning effort, then paste the request to the Leader for your development root. This does not change native selection.",
                "选择模型和思考档位后，将请求粘贴给负责你开发根目录的 Leader。本操作不会切换原生模型。"
            )
        }
        var modelLabel: String { text("Model", "模型") }
        var effortLabel: String { text("Reasoning effort", "思考档位") }
        var generateAndCopy: String { text("Generate and Copy for Leader", "生成并复制给 Leader") }
        var copied: String { text("Prompt copied.", "提示已复制。") }
        var failed: String { text("Prompt could not be copied.", "无法复制提示。") }
        var unavailable: String { text("Unavailable", "不可用") }
        private func text(_ english: String, _ chinese: String) -> String {
            language == .simplifiedChinese ? chinese : english
        }
    }
}
