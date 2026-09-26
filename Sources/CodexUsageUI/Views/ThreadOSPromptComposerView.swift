import SwiftUI
import AppKit
import Combine

@MainActor
enum ThreadOSPromptComposerPreferences {
    static let selections = ApplicationPreferenceKey<Data?>(optionalData: "threados.prompt.composer.role-selections.v2")
}

enum ThreadOSPromptComposerCopyResult: Equatable {
    case copied
    case unavailable
    case clipboardFailure
}

private struct PersistedPromptRoleSelection: Codable {
    let role: ThreadOSPromptRole
    let model: String
    let effort: String
}

private struct PersistedPromptSelections: Codable {
    let version: Int
    let selections: [PersistedPromptRoleSelection]
}

/// Four independent, global prompt selections. This store never reads or writes project drafts.
@MainActor
final class ThreadOSPromptComposerForm: ObservableObject {
    static let defaultSelections: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-6-luna", effort: "medium"),
        .coderCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .qa: .init(model: "gpt-6-sol", effort: "high")
    ]

    @Published private(set) var selections: [ThreadOSPromptRole: ThreadOSPromptSelection]
    private let preferences: ApplicationPreferences

    init(preferences: ApplicationPreferences) {
        self.preferences = preferences
        selections = Self.loadSelections(from: preferences) ?? Self.defaultSelections
    }

    var canGenerate: Bool {
        selections.count == ThreadOSPromptRole.allCases.count &&
            ThreadOSPromptRole.allCases.allSatisfy { role in
                guard let selection = selections[role] else { return false }
                return ThreadOSLeaderPrompt.supportedModels.contains(selection.model) &&
                    ThreadOSLeaderPrompt.supportedEfforts.contains(selection.effort)
            }
    }

    func selection(for role: ThreadOSPromptRole) -> ThreadOSPromptSelection {
        selections[role] ?? Self.defaultSelections[role]!
    }

    func selectModel(_ model: String, for role: ThreadOSPromptRole) {
        guard ThreadOSLeaderPrompt.supportedModels.contains(model) else { return }
        let current = selection(for: role)
        guard current.model != model else { return }
        selections[role] = .init(model: model, effort: current.effort)
        persistSelections()
    }

    func selectEffort(_ effort: String, for role: ThreadOSPromptRole) {
        guard ThreadOSLeaderPrompt.supportedEfforts.contains(effort) else { return }
        let current = selection(for: role)
        guard current.effort != effort else { return }
        selections[role] = .init(model: current.model, effort: effort)
        persistSelections()
    }

    func generateAndCopy(
        language: AppLanguage,
        to clipboard: any ThreadOSSettingsClipboard
    ) -> ThreadOSPromptComposerCopyResult {
        guard canGenerate,
              let prompt = try? ThreadOSLeaderPrompt.make(selections: selections, language: language) else {
            return .unavailable
        }
        return clipboard.write(prompt) ? .copied : .clipboardFailure
    }

    private static func loadSelections(from preferences: ApplicationPreferences) -> [ThreadOSPromptRole: ThreadOSPromptSelection]? {
        guard let data = preferences.value(for: ThreadOSPromptComposerPreferences.selections),
              let stored = try? JSONDecoder().decode(PersistedPromptSelections.self, from: data),
              stored.version == 1,
              stored.selections.count == ThreadOSPromptRole.allCases.count else { return nil }

        var decoded: [ThreadOSPromptRole: ThreadOSPromptSelection] = [:]
        for item in stored.selections {
            guard decoded[item.role] == nil,
                  ThreadOSLeaderPrompt.supportedModels.contains(item.model),
                  ThreadOSLeaderPrompt.supportedEfforts.contains(item.effort) else { return nil }
            decoded[item.role] = .init(model: item.model, effort: item.effort)
        }
        guard ThreadOSPromptRole.allCases.allSatisfy({ decoded[$0] != nil }) else { return nil }
        return decoded
    }

    private func persistSelections() {
        guard canGenerate else { return }
        let entries = ThreadOSPromptRole.allCases.map { role in
            let selection = selections[role]!
            return PersistedPromptRoleSelection(role: role, model: selection.model, effort: selection.effort)
        }
        guard let data = try? JSONEncoder().encode(PersistedPromptSelections(version: 1, selections: entries)) else { return }
        preferences.set(data as Data?, for: ThreadOSPromptComposerPreferences.selections)
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
        _form = StateObject(wrappedValue: ThreadOSPromptComposerForm(preferences: preferences))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy.title)
                    .font(.title2.weight(.semibold))
                Text(copy.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("uma.threados.prompt.description")

                ForEach(ThreadOSPromptRole.allCases, id: \.self) { role in
                    roleRow(role)
                    if role != .qa { Divider() }
                }

                Button(copy.generateAndCopy) {
                    switch form.generateAndCopy(language: language, to: clipboard) {
                    case .copied:
                        copyStatus = .copied
                    case .unavailable, .clipboardFailure:
                        copyStatus = .failed
                    }
                }
                .buttonStyle(.borderedProminent)
                .focusable()
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
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func roleRow(_ role: ThreadOSPromptRole) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role.label(for: language))
                .font(.headline)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.modelLabel).font(.caption).foregroundStyle(.secondary)
                    Picker(copy.modelLabel, selection: Binding(
                        get: { form.selection(for: role).model },
                        set: { form.selectModel($0, for: role) }
                    )) {
                        ForEach(ThreadOSLeaderPrompt.supportedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .focusable()
                    .labelsHidden()
                    .accessibilityLabel(copy.modelLabel)
                    .accessibilityIdentifier("uma.threados.prompt.role.\(role.rawValue).model")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.effortLabel).font(.caption).foregroundStyle(.secondary)
                    Picker(copy.effortLabel, selection: Binding(
                        get: { form.selection(for: role).effort },
                        set: { form.selectEffort($0, for: role) }
                    )) {
                        ForEach(ThreadOSLeaderPrompt.supportedEfforts, id: \.self) { effort in
                            Text(effortLabel(effort)).tag(effort)
                        }
                    }
                    .pickerStyle(.menu)
                    .focusable()
                    .labelsHidden()
                    .accessibilityLabel(copy.effortLabel)
                    .accessibilityIdentifier("uma.threados.prompt.role.\(role.rawValue).effort")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copy: Copy { Copy(language: language) }

    private func effortLabel(_ effort: String) -> String {
        guard language == .simplifiedChinese else { return ["xhigh": "Extra High"][effort] ?? effort }
        return ["low": "低", "medium": "中", "high": "高", "xhigh": "额外高"][effort] ?? effort
    }

    private struct Copy {
        let language: AppLanguage
        var title: String { text("ThreadOS prompt", "ThreadOS 提示") }
        var description: String {
            text(
                "Choose a model and reasoning effort for each role. Copy the request for the receiving Leader; this does not change native selection.",
                "为每个角色选择模型和思考档位，然后复制给接收 Leader。本操作不会切换原生模型。"
            )
        }
        var modelLabel: String { text("Model", "模型") }
        var effortLabel: String { text("Reasoning effort", "思考档位") }
        var generateAndCopy: String { text("Generate and Copy for Leader", "生成并复制给 Leader") }
        var copied: String { text("Prompt copied.", "提示已复制。") }
        var failed: String { text("Prompt could not be copied.", "无法复制提示。") }
        private func text(_ english: String, _ chinese: String) -> String {
            language == .simplifiedChinese ? chinese : english
        }
    }
}
