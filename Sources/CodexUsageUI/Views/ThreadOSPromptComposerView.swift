import SwiftUI
import AppKit
import Combine

private struct ThreadOSPromptPopup: NSViewRepresentable {
    struct Option {
        let title: String
        let value: String
    }

    let label: String
    let identifier: String
    let options: [Option]
    let selection: String
    let onSelection: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = ThreadOSPromptFocusablePopUpButton(frame: .zero, pullsDown: false)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.refusesFirstResponder = false
        popup.focusRingType = .exterior
        popup.setAccessibilityLabel(label)
        popup.setAccessibilityIdentifier(identifier)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.onSelection = onSelection
        let current = popup.itemArray.map { ($0.title, $0.representedObject as? String ?? "") }
        if current.map(\.1) != options.map(\.value) || current.map(\.0) != options.map(\.title) {
            popup.removeAllItems()
            for option in options {
                popup.addItem(withTitle: option.title)
                popup.lastItem?.representedObject = option.value
            }
        }
        if let index = options.firstIndex(where: { $0.value == selection }) {
            popup.selectItem(at: index)
        }
        popup.setAccessibilityLabel(label)
        popup.setAccessibilityIdentifier(identifier)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelection: (String) -> Void

        init(onSelection: @escaping (String) -> Void) { self.onSelection = onSelection }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? String else { return }
            onSelection(value)
        }
    }
}

private final class ThreadOSPromptFocusablePopUpButton: NSPopUpButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }
}

private final class ThreadOSPromptFocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }
}

public final class ThreadOSPromptKeyViewLoopBoundaryView: NSView {
    var originalIncomingKeyViewForPromptLoop: NSView?
    var originalOutgoingKeyViewForPromptLoop: NSView?
}

public struct ThreadOSPromptKeyViewLoopBoundary: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = ThreadOSPromptKeyViewLoopBoundaryView(frame: .zero)
        view.isHidden = true
        view.setAccessibilityIdentifier("uma.threados.prompt.key-view-boundary")
        return view
    }

    public func updateNSView(_ view: NSView, context: Context) {}
}

private struct ThreadOSPromptKeyViewLoopAttachment: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.start(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.start(from: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private static let controlIdentifiers: [String] = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + ["uma.threados.prompt.generate-copy"]

        private var timer: Timer?
        private var pollCount = 0
        private var consecutiveLinkedPolls = 0
        private var originalLinks: [KeyViewLinkSnapshot] = []

        func start(from view: NSView) {
            guard timer == nil else { return }
            pollCount = 0
            consecutiveLinkedPolls = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self, weak view] timer in
                guard let self, let view else { timer.invalidate(); return }
                self.pollCount += 1
                if let window = view.window, self.link(in: window) {
                    self.consecutiveLinkedPolls += 1
                } else {
                    self.consecutiveLinkedPolls = 0
                }
                if self.pollCount >= 20 || self.consecutiveLinkedPolls >= 4 {
                    timer.invalidate()
                    self.timer = nil
                }
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            restoreOriginalLinks()
        }

        @discardableResult
        private func link(in window: NSWindow) -> Bool {
            guard let root = window.contentView,
                  let controls = Self.controls(in: root),
                  controls.allSatisfy({ $0.window === window }) else { return false }
            let shellBoundary = Self.allViews(in: root).first {
                $0.accessibilityIdentifier() == "uma.threados.prompt.key-view-boundary"
            }
            let anchor = shellBoundary ?? window.initialFirstResponder ?? root
            guard anchor.window === window else { return false }

            let linkedViews = [anchor] + controls
            if originalLinks.map(\.view).elementsEqual(linkedViews, by: { $0 === $1 }) {
                let expectedTargets = Array(controls.dropFirst()) + [returnTarget(for: shellBoundary != nil)]
                if zip(linkedViews, [controls[0]] + expectedTargets).allSatisfy({ $0.nextKeyView === $1 }) {
                    return true
                }
            } else {
                restoreOriginalLinks()
                originalLinks = linkedViews.map(KeyViewLinkSnapshot.init)
                if let boundary = anchor as? ThreadOSPromptKeyViewLoopBoundaryView {
                    boundary.originalIncomingKeyViewForPromptLoop = anchor.previousKeyView
                    boundary.originalOutgoingKeyViewForPromptLoop = originalLinks[0].originalNextView
                }
            }

            // Insert the composer controls into the existing key-view route.
            // Continue from Copy's own outgoing edge so SwiftUI's shell route
            // can reach toolbar controls and return to the rest of the window.
            let targets = [controls[0]] + Array(controls.dropFirst()) + [returnTarget(for: shellBoundary != nil)]
            for (view, next) in zip(linkedViews, targets) {
                view.nextKeyView = next
            }
            for (link, next) in zip(originalLinks, targets) {
                link.assignedNextView = next
            }
            return true
        }

        private func returnTarget(for shellBoundary: Bool) -> NSView? {
            let returnLinkIndex = shellBoundary ? 0 : originalLinks.count - 1
            return originalLinks[returnLinkIndex].originalNextView
        }

        private func restoreOriginalLinks() {
            for link in originalLinks.reversed() {
                guard let view = link.view, view.nextKeyView === link.assignedNextView else { continue }
                view.nextKeyView = link.originalNextView
            }
            originalLinks.removeAll()
        }

        private static func controls(in root: NSView?) -> [NSView]? {
            guard let root else { return nil }
            let byIdentifier = allViews(in: root).reduce(into: [String: NSView]()) { result, candidate in
                let identifier = candidate.accessibilityIdentifier()
                guard controlIdentifiers.contains(identifier) else { return }
                result[identifier] = candidate
            }
            let controls = controlIdentifiers.compactMap { byIdentifier[$0] }
            return controls.count == controlIdentifiers.count ? controls : nil
        }

        private static func allViews(in root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap(allViews(in:))
        }
    }

    @MainActor
    private final class KeyViewLinkSnapshot {
        weak var view: NSView?
        weak var originalNextView: NSView?
        weak var assignedNextView: NSView?

        init(_ view: NSView) {
            self.view = view
            originalNextView = view.nextKeyView
        }
    }
}

private struct ThreadOSPromptCopyButton: NSViewRepresentable {
    let title: String
    let identifier: String
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = ThreadOSPromptFocusableButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = .rounded
        button.bezelColor = .controlAccentColor
        button.controlSize = .regular
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.isEnabled = enabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }

        @objc func activate(_ sender: NSButton) { action() }
    }
}

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

                ThreadOSPromptCopyButton(
                    title: copy.generateAndCopy,
                    identifier: "uma.threados.prompt.generate-copy",
                    enabled: form.canGenerate
                ) {
                    switch form.generateAndCopy(language: language, to: clipboard) {
                    case .copied:
                        copyStatus = .copied
                    case .unavailable, .clipboardFailure:
                        copyStatus = .failed
                    }
                }
                .frame(minHeight: 24, alignment: .leading)

                if let copyStatus {
                    Text(copyStatus == .copied ? copy.copied : copy.failed)
                        .font(.callout)
                        .foregroundStyle(copyStatus == .copied ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("uma.threados.prompt.copy-status")
                }
                ThreadOSPromptKeyViewLoopAttachment()
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
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
                    ThreadOSPromptPopup(
                        label: copy.modelLabel,
                        identifier: "uma.threados.prompt.role.\(role.rawValue).model",
                        options: ThreadOSLeaderPrompt.supportedModels.map { .init(title: $0, value: $0) },
                        selection: form.selection(for: role).model,
                        onSelection: { form.selectModel($0, for: role) }
                    )
                    .frame(minHeight: 24, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.effortLabel).font(.caption).foregroundStyle(.secondary)
                    ThreadOSPromptPopup(
                        label: copy.effortLabel,
                        identifier: "uma.threados.prompt.role.\(role.rawValue).effort",
                        options: ThreadOSLeaderPrompt.supportedEfforts.map { .init(title: effortLabel($0), value: $0) },
                        selection: form.selection(for: role).effort,
                        onSelection: { form.selectEffort($0, for: role) }
                    )
                    .frame(minHeight: 24, alignment: .leading)
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
