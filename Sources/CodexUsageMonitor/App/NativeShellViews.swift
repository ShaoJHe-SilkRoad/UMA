import CodexUsageUI
import SwiftUI
import AppKit

enum MainSurfaceDestination: String, CaseIterable, Identifiable {
    case agents = "Agents & Settings"
    case threadOS = "ThreadOS"
    var id: String { rawValue }
}

private struct MainToolbarNavigationControl: NSViewRepresentable {
    @Binding var selection: MainSurfaceDestination
    let labels: [String]
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = MainToolbarFocusableSegmentedControl(frame: .zero)
        control.segmentCount = labels.count
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.controlSize = .regular
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
            control.setWidth(125, forSegment: index)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        control.setAccessibilityLabel(accessibilityLabel)
        control.setAccessibilityIdentifier("uma.main.navigation")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
        }
        control.selectedSegment = MainSurfaceDestination.allCases.firstIndex(of: selection) ?? 0
        control.setAccessibilityLabel(accessibilityLabel)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<MainSurfaceDestination>

        init(selection: Binding<MainSurfaceDestination>) { self.selection = selection }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard MainSurfaceDestination.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = MainSurfaceDestination.allCases[sender.selectedSegment]
        }
    }
}

private final class MainToolbarFocusableSegmentedControl: NSSegmentedControl {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }
}

private struct MainToolbarActionButton: NSViewRepresentable {
    let label: String
    let identifier: String
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = MainToolbarFocusableButton(title: label, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.imagePosition = .noImage
        button.font = .systemFont(ofSize: 13)
        button.focusRingType = .exterior
        button.refusesFirstResponder = false
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.toolTip = label
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = label
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.toolTip = label
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }

        @objc func activate(_ sender: NSButton) { action() }
    }
}

private final class MainToolbarFocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isHidden && alphaValue > 0 }
}

@MainActor
final class MainSurfaceNavigationState: ObservableObject {
    @Published var destination: MainSurfaceDestination = .agents
    @Published var selectedAgent: ProviderProductID = .codex
}

struct MainWindowRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var navigation: MainSurfaceNavigationState
    let openSettings: () -> Void
    let scanAll: () -> Void
    let refreshAll: () -> Void
    let connectCodex: () -> Void
    let disconnectCodex: () -> Void
    let claudeControlState: () -> ClaudeAgentControlState
    let connectClaude: () -> Void
    let accuracySyncClaude: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch navigation.destination {
            case .agents: agentsWorkspace
            case .threadOS:
                ThreadOSSettingsView(
                    language: store.language,
                    basicUsage: store.basicUsagePresentation,
                    showCodexDetail: {
                        navigation.selectedAgent = .codex
                        navigation.destination = .agents
                    }
                )
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .environment(\.locale, store.language.locale)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            MainToolbarNavigationControl(
                selection: $navigation.destination,
                labels: MainSurfaceDestination.allCases.map(destinationTitle),
                accessibilityLabel: localized("UMA navigation", "UMA 导航")
            )
            .frame(width: 250)
            Spacer()
            MainToolbarActionButton(
                label: localized("Scan for Agents", "扫描智能体"),
                identifier: "uma.main.scan",
                isEnabled: true,
                action: scanAll
            )
            .frame(width: store.language == .simplifiedChinese ? 92 : 112, height: 30)
            MainToolbarActionButton(
                label: localized("Refresh All", "全部刷新"),
                identifier: "uma.main.refresh",
                isEnabled: store.allowsManualRefresh,
                action: refreshAll
            )
            .frame(width: store.language == .simplifiedChinese ? 76 : 94, height: 30)
            MainToolbarActionButton(
                label: localized("Global Settings", "全局设置"),
                identifier: "uma.main.settings",
                isEnabled: true,
                action: openSettings
            )
            .frame(width: store.language == .simplifiedChinese ? 76 : 110, height: 30)
            .help(localized("Global Settings", "全局设置"))
            ThreadOSPromptKeyViewLoopBoundary()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var agentsWorkspace: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Agents", "智能体"))
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                if workspaceProviders.isEmpty {
                    VStack(spacing: 8) {
                        Text(localized("No active agents", "没有活跃的智能体"))
                        Button(localized("Scan for Agents", "扫描智能体"), action: scanAll)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(workspaceProviders) { provider in
                                Button {
                                    navigation.selectedAgent = provider.id
                                } label: {
                                    AgentGlanceRow(
                                        provider: provider,
                                        style: .mainList,
                                        selected: selectedProviderID == provider.id,
                                        language: store.language
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("uma.agent.list.\(provider.id.rawValue)")
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(minWidth: 210, idealWidth: 240, maxWidth: 285)
            .background(Color(nsColor: .windowBackgroundColor))

            AgentWorkspaceSurface(
                store: store,
                providerID: selectedProviderID,
                refresh: refreshAll,
                connectCodex: connectCodex,
                disconnectCodex: disconnectCodex,
                claudeControlState: claudeControlState,
                connectClaude: connectClaude,
                claudeAccuracySync: accuracySyncClaude
            )
            .frame(minWidth: 500)
        }
    }

    private var workspaceProviders: [ProviderProductState] {
        store.productInventory.agentWorkspaceProviders
    }

    private var selectedProviderID: ProviderProductID {
        if workspaceProviders.contains(where: { $0.id == navigation.selectedAgent }) { return navigation.selectedAgent }
        return workspaceProviders.first?.id ?? .codex
    }

    private func destinationTitle(_ destination: MainSurfaceDestination) -> String {
        switch destination {
        case .agents: localized("Agents & Settings", "智能体与设置")
        case .threadOS: "ThreadOS"
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        store.language == .simplifiedChinese ? chinese : english
    }
}

struct SettingsWindowRootView: View {
    let preferences: ApplicationPreferences
    @ObservedObject var store: UsageStore
    @ObservedObject var navigation: GlobalSettingsNavigationState
    var dataPaths: ApplicationDataPaths = .current()

    var body: some View {
        GlobalSettingsSurface(
            preferences: preferences,
            store: store,
            navigation: navigation,
            dataPaths: dataPaths
        )
    }
}
