import CodexUsageUI
import SwiftUI

enum MainSurfaceDestination: String, CaseIterable, Identifiable {
    case agents = "Agents & Settings"
    case threadOS = "ThreadOS"
    var id: String { rawValue }
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
            case .threadOS: ThreadOSSettingsView(language: store.language)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .environment(\.locale, store.language.locale)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker(localized("Destination", "导航"), selection: $navigation.destination) {
                ForEach(MainSurfaceDestination.allCases) { item in
                    Text(destinationTitle(item)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
            .accessibilityLabel(localized("UMA navigation", "UMA 导航"))
            Spacer()
            Button(action: scanAll) { Image(systemName: "sparkle.magnifyingglass") }
                .help(localized("Scan All", "全部扫描"))
                .accessibilityLabel(localized("Scan All", "全部扫描"))
                .accessibilityIdentifier("uma.main.scan")
            Button(action: refreshAll) { Image(systemName: "arrow.clockwise") }
                .help(localized("Refresh All", "全部刷新"))
                .accessibilityLabel(localized("Refresh All", "全部刷新"))
                .accessibilityIdentifier("uma.main.refresh")
                .disabled(!store.allowsManualRefresh)
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .help(localized("Global Settings", "全局设置"))
                .accessibilityLabel(localized("Global Settings", "全局设置"))
                .accessibilityIdentifier("uma.main.settings")
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
