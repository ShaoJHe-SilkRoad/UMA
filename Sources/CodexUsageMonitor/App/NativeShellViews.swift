import CodexUsageUI
import SwiftUI
import AppKit

enum MainSurfaceDestination: String, CaseIterable, Identifiable {
    case agents = "UMA"
    case threadOS = "ThreadOS"
    case sectorium = "Sectorium"
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
            control.setWidth(118, forSegment: index)
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
private final class MainAgentSettingsFocusBridge {
    weak var button: NSButton?
    private var keyObserver: NSObjectProtocol?
    private var focusRetryTimer: Timer?

    isolated deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        focusRetryTimer?.invalidate()
    }

    func restoreAfterSheetDismiss() {
        guard let window = button?.window else { return }
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.retryWhileKey() }
        }
        retryWhileKey()
    }

    private func retryWhileKey() {
        focusRetryTimer?.invalidate()
        guard button?.window?.isKeyWindow == true else { return }
        let deadline = Date().addingTimeInterval(0.5)
        focusRetryTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] timer in
            let restored = MainActor.assumeIsolated { () -> Bool in
                guard let self, let button = self.button,
                      let window = button.window, window.isKeyWindow else { return false }
                return window.makeFirstResponder(button)
            }
            if restored || Date() >= deadline {
                timer.invalidate()
                if restored { MainActor.assumeIsolated { self?.finishReturnFocus() } }
            }
        }
    }

    private func finishReturnFocus() {
        focusRetryTimer?.invalidate()
        focusRetryTimer = nil
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
    }
}

private struct MainAgentSettingsButton: NSViewRepresentable {
    let label: String
    let enabled: Bool
    let focusBridge: MainAgentSettingsFocusBridge
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = MainToolbarFocusableButton(title: "", target: context.coordinator,
            action: #selector(Coordinator.activate(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.focusRingType = .exterior
        button.refusesFirstResponder = false
        focusBridge.button = button
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: label)
        button.isEnabled = enabled
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier("uma.agent.selected-settings")
        button.toolTip = label
        focusBridge.button = button
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate(_ sender: NSButton) { action() }
    }
}

@MainActor
final class MainSurfaceNavigationState: ObservableObject {
    @Published var destination: MainSurfaceDestination = .agents
    @Published var selectedAgent: ProviderProductID = .codex
}

@MainActor
final class MainSectoriumStoreLifetime: ObservableObject {
    private let makeStore: () -> HESectoriumStore
    private var retainedStore: HESectoriumStore?

    init(makeStore: @escaping () -> HESectoriumStore = { HESectoriumStore() }) {
        self.makeStore = makeStore
    }

    func resolve(injected: HESectoriumStore?) -> HESectoriumStore {
        if let injected { return injected }
        if let retainedStore { return retainedStore }
        let store = makeStore()
        retainedStore = store
        return store
    }
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
    var hesectoriumStore: HESectoriumStore? = nil
    var promptClipboard: (any ThreadOSSettingsClipboard)? = nil
    var promptPreferences: ApplicationPreferences = .production
    var claudeSettings: ClaudeBrowserSettingsModel? = nil
    var referenceDate: Date? = nil
    var agentRailDisplayNames: [ProviderProductID: String] = [:]
    var initiallyExpandedResetProviderID: ProviderProductID? = nil
    // Tab removal stops observation, but must not discard the known volume rows.
    // The service is created lazily so visiting AUV/ThreadOS alone does no storage work.
    @StateObject private var sectoriumStoreLifetime = MainSectoriumStoreLifetime()
    @State private var sheetProviderID: ProviderProductID?
    @State private var agentSettingsFocusBridge = MainAgentSettingsFocusBridge()

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
                    },
                    preferences: promptPreferences,
                    clipboard: promptClipboard ?? SystemThreadOSSettingsClipboard()
                )
            case .sectorium:
                SectoriumWorkbenchView(
                    store: sectoriumStoreLifetime.resolve(injected: hesectoriumStore),
                    isChinese: store.language == .simplifiedChinese
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            versionFooter
        }
        .frame(minWidth: 760, minHeight: 488)
        .background(UMAVisualStyle.canvas)
        .environment(\.locale, store.language.locale)
        .sheet(item: $sheetProviderID, onDismiss: {
            agentSettingsFocusBridge.restoreAfterSheetDismiss()
        }) { providerID in
            AgentSpecificSettingsSheet(store: store, providerID: providerID.settingsProviderID, claudeSettings: claudeSettings) {
                sheetProviderID = nil
            }
        }
    }

    private var versionFooter: some View {
        HStack {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("AUV \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("auv.main.version")
                    .help("Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(UMAVisualStyle.canvas)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            MainToolbarNavigationControl(
                selection: $navigation.destination,
                labels: MainSurfaceDestination.allCases.map(destinationTitle),
                accessibilityLabel: localized("AUV navigation", "AUV 导航")
            )
            .frame(width: 360)
            Spacer()
            if navigation.destination == .agents {
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
            }
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
        .background(UMAVisualStyle.toolbar)
    }

    private var agentsWorkspace: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localized("Agents", "智能体")).font(.headline)
                    Spacer(minLength: 4)
                    MainAgentSettingsButton(
                        label: localized("Selected agent settings", "所选智能体设置"),
                        enabled: !workspaceProviders.isEmpty,
                        focusBridge: agentSettingsFocusBridge,
                        action: { sheetProviderID = selectedProviderID }
                    )
                    .frame(width: 20, height: 20)
                }
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
                    GeometryReader { available in
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(workspaceProviders) { provider in
                                    Button {
                                        navigation.selectedAgent = provider.id
                                    } label: {
                                        AgentGlanceRow(
                                            provider: provider,
                                            style: .mainList,
                                            selected: selectedProviderID == provider.id,
                                            language: store.language,
                                            referenceDate: referenceDate,
                                            displayNameOverride: agentRailDisplayNames[provider.id]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("uma.agent.list.\(provider.id.rawValue)")
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(height: available.size.height)
                    }
                }
            }
            .frame(minWidth: 224, idealWidth: 240, maxWidth: 248)
            .background(UMAVisualStyle.canvas)

            AgentWorkspaceSurface(
                store: store,
                providerID: selectedProviderID,
                refresh: refreshAll,
                connectCodex: connectCodex,
                disconnectCodex: disconnectCodex,
                claudeControlState: claudeControlState,
                connectClaude: connectClaude,
                claudeAccuracySync: accuracySyncClaude,
                referenceDate: referenceDate
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
        case .agents: localized("AUV", "AUV")
        case .threadOS: localized("ThreadOS", "ThreadOS（线程工）")
        case .sectorium: localized("Sectorium", "Sectorium（分区工）")
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
