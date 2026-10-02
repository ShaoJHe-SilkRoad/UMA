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

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { revealPromptFocusInEnclosingScrollView() }
        return becameFirstResponder
    }
}

private final class ThreadOSPromptFocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { revealPromptFocusInEnclosingScrollView() }
        return becameFirstResponder
    }
}

private extension NSView {
    func revealPromptFocusInEnclosingScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        let focusRect = convert(bounds, to: scrollView.contentView).insetBy(dx: -6, dy: -6)
        guard !scrollView.contentView.bounds.contains(focusRect) else { return }
        _ = scrollView.contentView.scrollToVisible(focusRect)
    }
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
        private weak var keyLoopWindow: NSWindow?
        private var originalAutorecalculatesKeyViewLoop: Bool?

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
            restoreKeyViewLoopCalculation()
        }

        @discardableResult
        private func link(in window: NSWindow) -> Bool {
            guard let root = window.contentView,
                  let controls = Self.controls(in: root),
                  controls.allSatisfy({ $0.window === window }) else { return false }
            let shellBoundary = Self.allViews(in: root).first {
                $0.accessibilityIdentifier() == "uma.threados.prompt.key-view-boundary"
            }
            let preferredAnchor = shellBoundary ?? window.initialFirstResponder ?? root
            let anchor = controls.contains(where: { $0 === preferredAnchor }) ? root : preferredAnchor
            guard anchor.window === window else { return false }
            preserveExplicitKeyViewLoop(in: window)

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

        private func preserveExplicitKeyViewLoop(in window: NSWindow) {
            guard keyLoopWindow !== window else { return }
            restoreKeyViewLoopCalculation()
            keyLoopWindow = window
            originalAutorecalculatesKeyViewLoop = window.autorecalculatesKeyViewLoop
            window.autorecalculatesKeyViewLoop = false
        }

        private func restoreKeyViewLoopCalculation() {
            guard let window = keyLoopWindow,
                  let originalAutorecalculatesKeyViewLoop else { return }
            if !window.autorecalculatesKeyViewLoop {
                window.autorecalculatesKeyViewLoop = originalAutorecalculatesKeyViewLoop
                if originalAutorecalculatesKeyViewLoop {
                    window.recalculateKeyViewLoop()
                }
            }
            keyLoopWindow = nil
            self.originalAutorecalculatesKeyViewLoop = nil
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
    let status: String?
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    private var accessibilityLabel: String {
        status.map { "\(title), \($0)" } ?? title
    }

    func makeNSView(context: Context) -> NSButton {
        let button = ThreadOSPromptFocusableButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = .rounded
        button.bezelColor = .systemPurple
        button.controlSize = .regular
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.isEnabled = enabled
        button.setAccessibilityLabel(accessibilityLabel)
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
    static let legacySelections = ApplicationPreferenceKey<Data?>(optionalData: "threados.prompt.composer.legacy-role-selections.v1")
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
        .leader: .init(model: "gpt-6.1-sol", effort: "high"),
        .coderCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .qa: .init(model: "gpt-6.1-sol", effort: "high")
    ]

    @Published private(set) var selections: [ThreadOSPromptRole: ThreadOSPromptSelection]
    private let preferences: ApplicationPreferences

    init(preferences: ApplicationPreferences) {
        self.preferences = preferences
        let loaded = Self.loadSelections(from: preferences)
        selections = loaded.selections ?? Self.defaultSelections
    }

    var invalidRoles: Set<ThreadOSPromptRole> {
        Set(ThreadOSPromptRole.allCases.filter { role in
            guard let selection = selections[role] else { return true }
            return !ThreadOSLeaderPrompt.supportedModels.contains(selection.model)
                || !ThreadOSLeaderPrompt.supportedEfforts.contains(selection.effort)
        })
    }

    func statusMessage(language: AppLanguage) -> String? {
        let invalid = invalidRoles
        let validation = invalid.isEmpty ? nil : (language == .simplifiedChinese
            ? "以下已保存角色的模型或思考档位不受支持：\(invalid.sorted { $0.rawValue < $1.rawValue }.map { $0.label(for: language) }.joined(separator: "、"))。请在对应菜单中选择受支持的值；保留的选择不会被默认值替换。"
            : "Saved model or reasoning-effort values are unsupported for: \(invalid.sorted { $0.rawValue < $1.rawValue }.map { $0.label(for: language) }.joined(separator: ", ")). Choose a supported value in each role menu; saved choices are not replaced with defaults.")
        let messages = [validation].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
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

    private struct LoadResult {
        let selections: [ThreadOSPromptRole: ThreadOSPromptSelection]?
    }

    private static func loadSelections(from preferences: ApplicationPreferences) -> LoadResult {
        guard let data = preferences.value(for: ThreadOSPromptComposerPreferences.selections),
              let stored = try? JSONDecoder().decode(PersistedPromptSelections.self, from: data),
              stored.version == 1,
              stored.selections.count == ThreadOSPromptRole.allCases.count else { return .init(selections: nil) }

        var decoded: [ThreadOSPromptRole: ThreadOSPromptSelection] = [:]
        for item in stored.selections {
            guard decoded[item.role] == nil else { return .init(selections: nil) }
            decoded[item.role] = .init(model: item.model, effort: item.effort)
        }
        guard ThreadOSPromptRole.allCases.allSatisfy({ decoded[$0] != nil }) else { return .init(selections: nil) }
        return .init(selections: decoded)
    }

    private func persistSelections() {
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
        GeometryReader { geometry in
            let contentWidth = min(max(geometry.size.width - 32, 0), 1120)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(copy.title)
                            .font(.title2.weight(.semibold))
                    }
                    Text(copy.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("uma.threados.prompt.description")

                    if let status = form.statusMessage(language: language) {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(form.canGenerate ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("uma.threados.prompt.selection-status")
                    }

                    if contentWidth >= 680 {
                        HStack(alignment: .top, spacing: 24) {
                            roleSettingsColumn
                                .frame(minWidth: 400, maxWidth: .infinity, alignment: .topLeading)
                            settingsSummary
                                .frame(width: 240, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            roleSettingsColumn
                            settingsSummary
                        }
                    }

                    ThreadOSPromptKeyViewLoopAttachment()
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: 1152, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .tint(.purple)
        .onChange(of: form.selections) { _, _ in
            copyStatus = nil
        }
    }

    private var roleSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ThreadOSPromptRole.allCases, id: \.self) { role in
                roleRow(role)
            }
        }
    }

    private func roleRow(_ role: ThreadOSPromptRole) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: role.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.purple)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.label(for: language))
                        .font(.system(size: 14, weight: .semibold))
                    Text(role.responsibility(for: language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.modelLabel).font(.caption).foregroundStyle(.secondary)
                    modelPopup(for: role)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.effortLabel).font(.caption).foregroundStyle(.secondary)
                    effortPopup(for: role)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.055)))
    }

    private var settingsSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(copy.summaryTitle)
                .font(.system(size: 14, weight: .semibold))
            Text(copy.summaryCaveat)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("uma.threados.prompt.summary.caveat")

            ForEach(ThreadOSPromptRole.allCases, id: \.self) { role in
                let selection = form.selection(for: role)
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.label(for: language))
                        .font(.system(size: 12, weight: .medium))
                    Text(ThreadOSPromptComposerSummary.line(role: role, selection: selection, language: language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("uma.threados.prompt.summary.role.\(role.rawValue)")
                }
            }

            Text(copy.leaderScopeNote)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Text(copy.childInheritanceNote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ThreadOSPromptCopyButton(
                title: copy.generateAndCopy,
                identifier: "uma.threados.prompt.generate-copy",
                enabled: form.canGenerate,
                status: copyStatus.map { $0 == .copied ? copy.copied : copy.failed }
            ) {
                switch form.generateAndCopy(language: language, to: clipboard) {
                case .copied:
                    copyStatus = .copied
                case .unavailable, .clipboardFailure:
                    copyStatus = .failed
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)

            if let copyStatus {
                Text(copyStatus == .copied ? copy.copied : copy.failed)
                    .font(.system(size: 12))
                    .foregroundStyle(copyStatus == .copied ? Color.secondary : Color.orange)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(copyStatus == .copied ? copy.copied : copy.failed)
                    .accessibilityIdentifier("uma.threados.prompt.copy-status")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.055)))
    }

    private func modelPopup(for role: ThreadOSPromptRole) -> some View {
        ThreadOSPromptPopup(
            label: copy.modelLabel,
            identifier: "uma.threados.prompt.role.\(role.rawValue).model",
            options: modelOptions(for: role),
            selection: form.selection(for: role).model,
            onSelection: { form.selectModel($0, for: role) }
        )
        .frame(minHeight: 24, alignment: .leading)
    }

    private func effortPopup(for role: ThreadOSPromptRole) -> some View {
        ThreadOSPromptPopup(
            label: copy.effortLabel,
            identifier: "uma.threados.prompt.role.\(role.rawValue).effort",
            options: effortOptions(for: role),
            selection: form.selection(for: role).effort,
            onSelection: { form.selectEffort($0, for: role) }
        )
        .frame(minHeight: 24, alignment: .leading)
    }

    private var copy: Copy { Copy(language: language) }

    private func modelOptions(for role: ThreadOSPromptRole) -> [ThreadOSPromptPopup.Option] {
        let current = form.selection(for: role).model
        var models = ThreadOSLeaderPrompt.supportedModels.map {
            ThreadOSPromptPopup.Option(title: modelLabel($0), value: $0)
        }
        if !ThreadOSLeaderPrompt.supportedModels.contains(current) {
            let title = language == .simplifiedChinese
                ? "\(current)（已保存但不受支持，选择替代项）"
                : "\(current) (saved unsupported — choose replacement)"
            models.append(.init(title: title, value: current))
        }
        return models
    }

    private func modelLabel(_ model: String) -> String {
        ThreadOSPromptComposerSummary.modelLabel(model)
    }

    private func effortLabel(_ effort: String) -> String {
        if language == .simplifiedChinese {
            return ["low": "低", "medium": "中", "high": "高", "xhigh": "极高"][effort] ?? effort
        }
        return ["low": "Low", "medium": "Medium", "high": "High", "xhigh": "Ex High"][effort] ?? effort
    }

    private func effortOptions(for role: ThreadOSPromptRole) -> [ThreadOSPromptPopup.Option] {
        var values = ThreadOSLeaderPrompt.supportedEfforts.map { ThreadOSPromptPopup.Option(title: effortLabel($0), value: $0) }
        let current = form.selection(for: role).effort
        if !ThreadOSLeaderPrompt.supportedEfforts.contains(current) {
            let title = language == .simplifiedChinese
                ? "\(current)（已保存但不受支持，选择替代项）"
                : "\(current) (saved unsupported — choose replacement)"
            values.append(.init(title: title, value: current))
        }
        return values
    }

    private struct Copy {
        let language: AppLanguage
        var title: String { text("ThreadOS · Team models", "ThreadOS · 团队模型") }
        var description: String {
            text(
                "Choose settings, then copy the instruction to the Leader responsible for the development directory.",
                "选择后复制，粘贴给负责开发目录的 Leader。"
            )
        }
        var summaryTitle: String { text("Settings Summary", "设置摘要") }
        var summaryCaveat: String { text("Summary only. This is not a complete execution command.", "这里只是设置摘要，不是完整执行命令。") }
        var leaderScopeNote: String { text("Paste to a Leader to set the team it is responsible for.", "粘贴给哪个 Leader，就设置其所负责的团队。") }
        var childInheritanceNote: String { text("Child workers inherit their Cluster settings.", "子工人沿用所属 Cluster 设置。") }
        var modelLabel: String { text("Model", "模型") }
        var effortLabel: String { text("Thinking", "思考档位") }
        var generateAndCopy: String { text("Generate and Copy Instruction", "生成并复制指令") }
        var copied: String { text("Instruction copied.", "指令已复制。") }
        var failed: String { text("Could not copy. Check clipboard access.", "复制失败，请检查剪贴板权限。") }
        private func text(_ english: String, _ chinese: String) -> String {
            language == .simplifiedChinese ? chinese : english
        }
    }
}

private extension ThreadOSPromptRole {
    var symbolName: String {
        switch self {
        case .leader: return "person.2.fill"
        case .coderCluster: return "wrench.and.screwdriver.fill"
        case .reviewerCluster: return "doc.text.magnifyingglass"
        case .qa: return "checkmark.seal.fill"
        }
    }

    func responsibility(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.leader, .simplifiedChinese): return "规划与协调"
        case (.coderCluster, .simplifiedChinese): return "实现与集成"
        case (.reviewerCluster, .simplifiedChinese): return "独立代码审查"
        case (.qa, .simplifiedChinese): return "验证与验收"
        case (.leader, .english): return "Planning and coordination"
        case (.coderCluster, .english): return "Implementation and integration"
        case (.reviewerCluster, .english): return "Independent code review"
        case (.qa, .english): return "Verification and acceptance"
        }
    }
}

@MainActor
enum ThreadOSPromptComposerSummary {
    static func modelLabel(_ model: String) -> String {
        [
            "gpt-6.1-sol": "GPT-6.1 Sol",
            "gpt-6-sol": "GPT-6 Sol",
            "gpt-6-luna": "GPT-6 Luna",
            "gpt-6-astra": "GPT-6 Astra",
            "gpt-5.6-sol": "GPT-5.6 Sol",
            "gpt-5.6-terra": "GPT-5.6 Terra"
        ][model] ?? model
    }

    static func line(role: ThreadOSPromptRole, selection: ThreadOSPromptSelection, language: AppLanguage) -> String {
        "\(role.label(for: language)) · \(modelLabel(selection.model)) / \(effortLabel(selection.effort, language: language))"
    }

    static func lines(
        from selections: [ThreadOSPromptRole: ThreadOSPromptSelection],
        language: AppLanguage
    ) -> [String] {
        ThreadOSPromptRole.allCases.map { role in
            line(
                role: role,
                selection: selections[role] ?? ThreadOSPromptComposerForm.defaultSelections[role]!,
                language: language
            )
        }
    }

    private static func effortLabel(_ effort: String, language: AppLanguage) -> String {
        if language == .simplifiedChinese {
            return ["low": "低", "medium": "中", "high": "高", "xhigh": "极高"][effort] ?? effort
        }
        return ["low": "Low", "medium": "Medium", "high": "High", "xhigh": "Ex High"][effort] ?? effort
    }
}
