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
        popup.font = .systemFont(ofSize: 13)
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

    override func keyDown(with event: NSEvent) {
        // A focused Copy button accepts ordinary Return/Enter, including Shift.
        // Command, Control and Option combinations retain normal key handling.
        // Keep this scoped to the actual first responder; a global key
        // equivalent would copy while an unrelated control owns focus.
        if (event.keyCode == 36 || event.keyCode == 76), isEnabled,
           window?.firstResponder === self,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            performClick(self)
            return
        }
        super.keyDown(with: event)
    }

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

        private var routeRetry: ThreadOSPromptKeyViewRouteRetryController?
        private weak var attachmentView: NSView?
        private weak var observedWindow: NSWindow?
        private var hasObservedWindow = false
        private var originalLinks: [KeyViewLinkSnapshot] = []
        private weak var keyLoopWindow: NSWindow?
        private var originalAutorecalculatesKeyViewLoop: Bool?

        func start(from view: NSView) {
            if attachmentView !== view {
                routeRetry?.stop()
                routeRetry = nil
                hasObservedWindow = false
            }
            attachmentView = view
            let currentWindow = view.window
            if hasObservedWindow, observedWindow !== currentWindow {
                restoreOriginalLinks()
                restoreKeyViewLoopCalculation()
                routeRetry?.reset()
            } else if routeRetry == nil {
                routeRetry = ThreadOSPromptKeyViewRouteRetryController { [weak self] in
                    self?.pollKeyViewRoute() ?? false
                }
                routeRetry?.start()
            }
            observedWindow = currentWindow
            hasObservedWindow = true
        }

        func stop() {
            routeRetry?.stop()
            routeRetry = nil
            attachmentView = nil
            observedWindow = nil
            hasObservedWindow = false
            restoreOriginalLinks()
            restoreKeyViewLoopCalculation()
        }

        private func pollKeyViewRoute() -> Bool {
            guard let view = attachmentView, let window = view.window else { return false }
            return link(in: window)
        }

        @discardableResult
        private func link(in window: NSWindow) -> Bool {
            guard let root = window.contentView,
                  let controls = Self.controls(in: root),
                  controls.allSatisfy({ $0.window === window }) else { return false }
            let shellBoundary = Self.allViews(in: root).first {
                $0.accessibilityIdentifier() == "uma.threados.prompt.key-view-boundary"
            }
            let shellViews = Self.allViews(in: root)
            let shellOutgoingTarget = shellBoundary.flatMap { _ in
                shellViews.first {
                    $0.accessibilityIdentifier() == "uma.main.navigation" && $0.canBecomeKeyView
                }
            }
            let shellSettings = shellBoundary.flatMap { _ in
                shellViews.first {
                    $0.accessibilityIdentifier() == "uma.main.settings" && $0.canBecomeKeyView
                }
            }
            guard shellBoundary == nil || (shellOutgoingTarget != nil && shellSettings != nil) else { return false }
            let preferredAnchor = shellBoundary ?? window.initialFirstResponder ?? root
            let anchor = controls.contains(where: { $0 === preferredAnchor }) ? root : preferredAnchor
            guard anchor.window === window else { return false }
            preserveExplicitKeyViewLoop(in: window)
            // Replacing the SwiftUI content inside the same NSWindow clears its
            // initial responder. Restore the new root before linking Tab routes.
            if window.initialFirstResponder == nil {
                window.initialFirstResponder = anchor
            }

            // The shell's AppKit route can be recalculated while SwiftUI builds
            // its toolbar. Own the complete ThreadOS cycle, including both
            // visible toolbar controls, so neither endpoint can point to itself.
            let linkedViews = [anchor] + controls + [shellOutgoingTarget, shellSettings].compactMap { $0 }
            let linksMatch = originalLinks.map(\.view).elementsEqual(linkedViews, by: { $0 === $1 })
            if !linksMatch {
                restoreOriginalLinks()
                originalLinks = linkedViews.map(KeyViewLinkSnapshot.init)
                if let boundary = anchor as? ThreadOSPromptKeyViewLoopBoundaryView {
                    boundary.originalIncomingKeyViewForPromptLoop = anchor.previousKeyView
                    boundary.originalOutgoingKeyViewForPromptLoop = originalLinks[0].originalNextView
                }
            }
            let outgoingTarget = shellBoundary == nil ? originalLinks[controls.count].originalNextView : shellOutgoingTarget
            let targets = [controls[0]] + Array(controls.dropFirst()) + [outgoingTarget]
                + (shellBoundary == nil ? [] : [shellSettings, anchor])
            if linksMatch {
                if zip(linkedViews, targets).allSatisfy({ $0.nextKeyView === $1 }) {
                    return true
                }
            }

            for (view, next) in zip(linkedViews, targets) {
                view.nextKeyView = next
            }
            for (link, next) in zip(originalLinks, targets) {
                link.assignedNextView = next
            }
            return true
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

/// Retries a changing SwiftUI key-view route for a bounded period. The caller
/// resets the budget only when the representable attaches to a different window.
@MainActor
final class ThreadOSPromptKeyViewRouteRetryController: NSObject {
    private let interval: TimeInterval
    private let maximumPolls: Int
    private let requiredSuccesses: Int
    private let poll: () -> Bool
    private var timer: Timer?
    private(set) var pollCount = 0
    private var consecutiveSuccesses = 0
    private var hasStarted = false

    var isActive: Bool { timer?.isValid == true }

    init(interval: TimeInterval = 0.05, maximumPolls: Int = 200,
         requiredSuccesses: Int = 4, poll: @escaping () -> Bool) {
        self.interval = max(interval, 0.001)
        self.maximumPolls = max(maximumPolls, 1)
        self.requiredSuccesses = max(requiredSuccesses, 1)
        self.poll = poll
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        pollCount = 0
        consecutiveSuccesses = 0
        let timer = Timer(timeInterval: interval, target: self,
                          selector: #selector(tick(_:)), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func reset() {
        invalidateTimer()
        hasStarted = false
        start()
    }

    func stop() {
        invalidateTimer()
        hasStarted = true
    }

    @objc private func tick(_ timer: Timer) {
        pollCount += 1
        if poll() {
            consecutiveSuccesses += 1
        } else {
            consecutiveSuccesses = 0
        }
        if consecutiveSuccesses >= requiredSuccesses || pollCount >= maximumPolls {
            invalidateTimer()
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
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

        @objc func activate(_ sender: NSButton) {
            action()
            sender.window?.makeFirstResponder(sender)
        }
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
    @Published private(set) var generatedInstruction: String?
    @Published private(set) var copyResult: ThreadOSPromptComposerCopyResult?
    private let preferences: ApplicationPreferences

    init(preferences: ApplicationPreferences) {
        self.preferences = preferences
        let loaded = Self.loadSelections(from: preferences)
        selections = loaded.selections ?? Self.defaultSelections
        refreshInstruction()
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
        refreshInstruction()
        persistSelections()
    }

    func selectEffort(_ effort: String, for role: ThreadOSPromptRole) {
        guard ThreadOSLeaderPrompt.supportedEfforts.contains(effort) else { return }
        let current = selection(for: role)
        guard current.effort != effort else { return }
        selections[role] = .init(model: current.model, effort: effort)
        refreshInstruction()
        persistSelections()
    }

    func generateAndCopy(
        language: AppLanguage,
        to clipboard: any ThreadOSSettingsClipboard
    ) -> ThreadOSPromptComposerCopyResult {
        guard canGenerate, let prompt = generatedInstruction else {
            copyResult = .unavailable
            return .unavailable
        }
        let result: ThreadOSPromptComposerCopyResult = clipboard.write(prompt) ? .copied : .clipboardFailure
        copyResult = result
        return result
    }

    private func refreshInstruction() {
        // Preview and Copy share this exact generated value. Wrapping is visual only.
        generatedInstruction = try? ThreadOSLeaderPrompt.make(selections: selections, language: .english)
        copyResult = nil
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

enum ThreadOSPromptWorkbenchMetrics {
    static let heading: CGFloat = 28
    static let columns: CGFloat = 22
    static let row: CGFloat = 74
    static let selector: CGFloat = 30
    static let copy: CGFloat = 32
    static let previewGap: CGFloat = 12
    static var previewHeight: CGFloat {
        heading + columns + 3 * row + 7 + 20 + 7 + selector / 2 - copy / 2 - previewGap
    }
}

private final class ThreadOSPromptPreviewTextView: NSTextView {
    // Selectable by mouse/accessibility without adding another normal Tab stop.
    override var canBecomeKeyView: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 48, let root = window?.contentView else {
            super.keyDown(with: event)
            return
        }
        let identifier = event.modifierFlags.contains(.shift)
            ? "uma.threados.prompt.role.qa.effort" : "uma.threados.prompt.generate-copy"
        func find(_ view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == identifier { return view }
            return view.subviews.lazy.compactMap(find).first
        }
        if let target = find(root), target.canBecomeKeyView {
            window?.makeFirstResponder(target)
            target.revealPromptFocusInEnclosingScrollView()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct ThreadOSPromptInstructionPreview: NSViewRepresentable {
    let instruction: String
    let label: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = UMAVisualStyle.editorColor
        scroll.setAccessibilityIdentifier("uma.threados.prompt.preview")
        let text = ThreadOSPromptPreviewTextView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.allowsUndo = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.textColor = .labelColor
        text.backgroundColor = UMAVisualStyle.editorColor
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel(label)
        text.setAccessibilityIdentifier("uma.threados.prompt.preview.text")
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        if text.string != instruction {
            text.string = instruction
            text.setSelectedRange(NSRange(location: 0, length: 0))
            text.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        text.setAccessibilityLabel(label)
    }
}

/// A target-free command composer. This view does not dispatch or switch models.
public struct ThreadOSPromptComposerView: View {
    @StateObject private var form: ThreadOSPromptComposerForm
    private let language: AppLanguage
    private let clipboard: any ThreadOSSettingsClipboard

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
            let contentWidth = min(max(geometry.size.width - 40, 0), 1120)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if contentWidth >= 680 {
                        HStack(alignment: .top, spacing: 20) {
                            roleSettingsColumn
                                .frame(width: min(360, contentWidth * 0.46), alignment: .topLeading)
                            instructionColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            roleSettingsColumn
                            instructionColumn
                        }
                    }
                    ThreadOSPromptKeyViewLoopAttachment()
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .tint(.purple)
    }

    private var roleSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy.title)
                .font(.system(size: 18, weight: .semibold))
                .frame(height: ThreadOSPromptWorkbenchMetrics.heading, alignment: .topLeading)
            HStack(spacing: 12) {
                Text(copy.modelLabel).frame(maxWidth: .infinity, alignment: .leading)
                Text(copy.effortLabel).frame(width: 112, alignment: .leading)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(height: ThreadOSPromptWorkbenchMetrics.columns)
            ForEach(ThreadOSPromptRole.allCases, id: \.self) { role in
                roleRow(role)
            }
        }
    }

    private func roleRow(_ role: ThreadOSPromptRole) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(role.label(for: language)).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text(role.responsibility(for: language))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(height: 20)
            HStack(spacing: 12) {
                modelPopup(for: role).frame(maxWidth: .infinity)
                effortPopup(for: role).frame(width: 112)
            }
            .frame(height: ThreadOSPromptWorkbenchMetrics.selector)
        }
        .padding(.top, 7)
        .frame(height: ThreadOSPromptWorkbenchMetrics.row, alignment: .top)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var instructionColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThreadOSPromptInstructionPreview(
                instruction: form.generatedInstruction ?? "",
                label: language == .simplifiedChinese ? "完整设置指令" : "Complete settings instruction"
            )
            .frame(height: ThreadOSPromptWorkbenchMetrics.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(UMAVisualStyle.separator.opacity(0.8), lineWidth: 1))
            .padding(.bottom, ThreadOSPromptWorkbenchMetrics.previewGap)
            ThreadOSPromptCopyButton(
                title: copy.generateAndCopy,
                identifier: "uma.threados.prompt.generate-copy",
                enabled: form.canGenerate && form.generatedInstruction != nil,
                status: feedback
            ) {
                _ = form.generateAndCopy(language: language, to: clipboard)
            }
            .frame(height: ThreadOSPromptWorkbenchMetrics.copy)
            Text(copy.leaderScopeNote)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let feedback {
                Text(feedback)
                    .font(.system(size: 12))
                    .foregroundStyle(form.copyResult == .copied ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("uma.threados.prompt.copy-status")
            }
            if let status = form.statusMessage(language: language) {
                Text(status)
                    .font(.system(size: 12)).foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("uma.threados.prompt.selection-status")
            }
        }
    }

    private var feedback: String? {
        guard let result = form.copyResult else { return nil }
        return result == .copied ? copy.copied : copy.failed
    }

    private func modelPopup(for role: ThreadOSPromptRole) -> some View {
        ThreadOSPromptPopup(
            label: "\(role.label(for: language)) — \(copy.modelLabel)",
            identifier: "uma.threados.prompt.role.\(role.rawValue).model",
            options: modelOptions(for: role),
            selection: form.selection(for: role).model,
            onSelection: { form.selectModel($0, for: role) }
        )
    }

    private func effortPopup(for role: ThreadOSPromptRole) -> some View {
        ThreadOSPromptPopup(
            label: "\(role.label(for: language)) — \(copy.effortLabel)",
            identifier: "uma.threados.prompt.role.\(role.rawValue).effort",
            options: effortOptions(for: role),
            selection: form.selection(for: role).effort,
            onSelection: { form.selectEffort($0, for: role) }
        )
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
        var title: String { text("Decision settings", "决策设置") }
        var leaderScopeNote: String { text("Paste to the Leader to apply to its team.", "粘贴给 Leader，应用到其负责的团队。") }
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
    func responsibility(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.leader, .simplifiedChinese): return "规划与协调"
        case (.coderCluster, .simplifiedChinese): return "实现与集成"
        case (.reviewerCluster, .simplifiedChinese): return "独立代码审查"
        case (.qa, .simplifiedChinese): return "验证与验收"
        case (.leader, .english): return "Plan & coordinate"
        case (.coderCluster, .english): return "Build & integrate"
        case (.reviewerCluster, .english): return "Independent review"
        case (.qa, .english): return "Verify & accept"
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
