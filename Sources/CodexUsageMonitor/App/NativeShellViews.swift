import CodexUsageUI
import SwiftUI
import AppKit

enum MainSurfaceDestination: String, CaseIterable, Identifiable {
    case agents = "UMA"
    case threadOS = "ThreadOS"
    case sectorium = "Sectorium"
    var id: String { rawValue }

    /// ThreadOS is opened from Codex's settings instead of the toolbar, because
    /// it is expected to stop being useful. Its page stays in the main window,
    /// since the form needs more width than the settings sheet has.
    static let toolbarDestinations: [MainSurfaceDestination] = [.agents, .sectorium]
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
            control.setWidth(Self.segmentWidth(for: label, in: control), forSegment: index)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        control.setAccessibilityLabel(accessibilityLabel)
        control.setAccessibilityIdentifier("uma.main.navigation")
        AUVLookAppKit.style(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
            control.setWidth(Self.segmentWidth(for: label, in: control), forSegment: index)
        }
        control.invalidateIntrinsicContentSize()
        // No segment is selected while ThreadOS, which has none, is showing.
        control.selectedSegment = MainSurfaceDestination.toolbarDestinations.firstIndex(of: selection) ?? -1
        control.setAccessibilityLabel(accessibilityLabel)
    }

    /// Each segment fits its own label. A fixed 118 points cut the Chinese
    /// labels, which carry their translation ("ThreadOS（线程工）"), while the
    /// English ones did not need it and pushed the toolbar past the window's
    /// minimum width.
    static func segmentWidth(for label: String, in control: NSSegmentedControl) -> CGFloat {
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let text = (label as NSString).size(withAttributes: [.font: font]).width
        return max(84, ceil(text) + 24)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<MainSurfaceDestination>

        init(selection: Binding<MainSurfaceDestination>) { self.selection = selection }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let destinations = MainSurfaceDestination.toolbarDestinations
            guard destinations.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = destinations[sender.selectedSegment]
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
    var symbol: String? = nil
    /// An icon-only button, named by its tooltip and accessibility label.
    var iconOnly = false
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = MainToolbarFocusableButton(title: iconOnly ? "" : label, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = iconOnly ? .accessoryBarAction : .rounded
        button.controlSize = iconOnly ? .small : .regular
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconOnly ? 12 : 12, weight: .medium))
            button.imagePosition = iconOnly ? .imageOnly : .imageLeading
            button.imageHugsTitle = true
        } else {
            button.imagePosition = .noImage
        }
        if iconOnly { button.isBordered = false; button.contentTintColor = .secondaryLabelColor }
        button.font = .systemFont(ofSize: 13)
        button.auvIconOnly = iconOnly
        button.applyLook()
        button.focusRingType = .exterior
        button.refusesFirstResponder = false
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.toolTip = label
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = iconOnly ? "" : label
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

private final class MainToolbarFocusableButton: AUVLookButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isHidden && alphaValue > 0 }
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
    var geminiSettings: GeminiSettingsModel? = nil
    var antigravitySettings: AntigravitySettingsModel? = nil
    var referenceDate: Date? = nil
    var agentRailDisplayNames: [ProviderProductID: String] = [:]
    var initiallyExpandedResetProviderID: ProviderProductID? = nil
    // Tab removal stops observation, but must not discard the known volume rows.
    // The service is created lazily so visiting AUV/ThreadOS alone does no storage work.
    @StateObject private var sectoriumStoreLifetime = MainSectoriumStoreLifetime()

    var body: some View {
        // The window's content runs under its transparent title bar; the bar
        // takes the title bar's height, beside the traffic lights.
        GeometryReader { proxy in
            surface(barHeight: max(40, proxy.safeAreaInsets.top))
                .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 760, minHeight: 488)
        .background(UMAVisualStyle.canvas)
        .environment(\.locale, store.language.locale)
        .auvLookRoot()
    }

    private func surface(barHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            toolbar(height: barHeight)
            barRule
            Group {
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
            // The page gives way at the window's minimum height; otherwise a
            // page taller than the window pushed the bar out of the top
            // (wabi-sabi in Chinese at 528 pt).
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            versionFooter
        }
    }

    /// Under the bar: a hairline in Standard, only space in wabi-sabi, the
    /// formwork's 2 pt rule in Brutalist.
    @ViewBuilder private var barRule: some View {
        switch AUVLook.current {
        case .standard: Divider()
        case .wabiSabi: EmptyView()
        case .brutalist: Rectangle().fill(Color.primary).frame(height: AUVFormwork.rule)
        }
    }

    private var versionFooter: some View {
        HStack {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("AUV \(version)")
                    .font(AUVType.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("auv.main.version")
                    .help("Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(UMAVisualStyle.canvas)
    }

    private func toolbar(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            // Past the bar's 16 pt padding and the row's 12 pt spacing.
            AUVTrafficLightClearance(leadingPadding: 28)
                .fixedSize()
                .accessibilityHidden(true)
            MainToolbarNavigationControl(
                selection: $navigation.destination,
                labels: MainSurfaceDestination.toolbarDestinations.map(destinationTitle),
                accessibilityLabel: localized("AUV navigation", "AUV 导航")
            )
            .fixedSize()
            // No minimum: the toolbar's fixed parts already fill the narrowest
            // window, and an eight-point spacer pushed them past it, shifting
            // the whole row sideways on the Agents tab.
            Spacer(minLength: 0)
            // Scan for Agents is beside the Agents list it fills; the
            // toolbar keeps the two actions used every day.
            if navigation.destination == .agents {
                MainToolbarActionButton(
                    label: localized("Refresh All", "全部刷新"),
                    identifier: "uma.main.refresh",
                    isEnabled: store.allowsManualRefresh,
                    symbol: "arrow.clockwise",
                    action: refreshAll
                )
                .frame(width: store.language == .simplifiedChinese ? 96 : 112, height: 30)
                .help(localized(
                    "Refresh every agent, including Claude's exact figures",
                    "刷新所有智能体，包括 Claude 的精确读数"
                ))
            }
            if navigation.destination == .threadOS {
                MainToolbarActionButton(
                    label: localized(
                        "Back to \(ProviderProductID.codex.displayName)",
                        "返回 \(ProviderProductID.codex.displayName)"
                    ),
                    identifier: "uma.main.threados.back",
                    isEnabled: true,
                    symbol: "chevron.left",
                    action: {
                        navigation.selectedAgent = .codex
                        navigation.destination = .agents
                    }
                )
                .frame(width: store.language == .simplifiedChinese ? 124 : 150, height: 30)
            }
            MainToolbarActionButton(
                label: localized("Global Settings", "全局设置"),
                identifier: "uma.main.settings",
                isEnabled: true,
                symbol: "gearshape",
                action: openSettings
            )
            .frame(width: store.language == .simplifiedChinese ? 96 : 130, height: 30)
            .help(localized("Global Settings", "全局设置"))
            ThreadOSPromptKeyViewLoopBoundary()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(height: height)
        // One colour with the window; the empty bar still moves the window.
        .background(AUVTitlebarDragArea())
    }

    private var agentsWorkspace: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(localized("Agents", "智能体"))
                        .font(AUVType.label)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    MainToolbarActionButton(
                        label: localized("Scan for Agents", "扫描智能体"),
                        identifier: "uma.main.scan",
                        isEnabled: true,
                        symbol: "magnifyingglass",
                        iconOnly: true,
                        action: scanAll
                    )
                    .frame(width: 24, height: 22)
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.top, 12)
                if workspaceProviders.isEmpty {
                    VStack(spacing: 8) {
                        Text(localized("No active agents", "没有活跃的智能体"))
                        Button(localized("Scan for Agents", "扫描智能体"), action: scanAll)
                    }
                    .font(AUVType.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { available in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(workspaceProviders) { provider in
                                    // Deliberately not a Button. A Button's own
                                    // gesture swallows the drag, so the row
                                    // never lifted; a plain row with an explicit
                                    // tap keeps selection working and leaves the
                                    // drag to start. The button role and
                                    // keyboard action are restored below so
                                    // assistive technology is unaffected.
                                    AgentGlanceRow(
                                        provider: provider,
                                        style: .mainList,
                                        selected: selectedProviderID == provider.id,
                                        language: store.language,
                                        // The dense rail stays compact; the
                                        // reset preference is the quick panel's,
                                        // and the workspace detail is one click
                                        // away.
                                        showsReset: false,
                                        referenceDate: referenceDate,
                                        displayNameOverride: agentRailDisplayNames[provider.id]
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { navigation.selectedAgent = provider.id }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { navigation.selectedAgent = provider.id }
                                    .accessibilityIdentifier("uma.agent.list.\(provider.id.rawValue)")
                                    // Drag a row onto another to rearrange the
                                    // list. The arrangement is saved as soon as
                                    // it changes and decides both lists and
                                    // which agent the menu bar reads.
                                    .onDrag {
                                        NSItemProvider(object: provider.id.rawValue as NSString)
                                    }
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let dropped = items.first,
                                              let moved = ProviderProductID(rawValue: dropped)
                                        else { return false }
                                        store.moveAgent(moved, onto: provider.id)
                                        return true
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                        .frame(height: available.size.height)
                    }
                }
            }
            // The list only navigates (icon, name, status when wrong); the
            // agent page holds its usage and settings.
            .frame(minWidth: 176, idealWidth: 188, maxWidth: 220)
            .background(UMAVisualStyle.canvas)

            AgentWorkspaceSurface(
                store: store,
                providerID: selectedProviderID,
                settingsContent: workspaceProviders.isEmpty ? nil : AnyView(agentSettingsPanel),
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

    /// The one way into an agent's own settings: the last module of that
    /// agent's page.
    private var agentSettingsPanel: some View {
        AgentSpecificSettingsPanel(
            store: store,
            providerID: selectedProviderID.settingsProviderID,
            claudeSettings: claudeSettings,
            geminiSettings: geminiSettings,
            antigravitySettings: antigravitySettings,
            openThreadOS: { navigation.destination = .threadOS }
        )
    }

    private var workspaceProviders: [ProviderProductState] {
        store.orderedWorkspaceProviders
    }

    private var selectedProviderID: ProviderProductID {
        if workspaceProviders.contains(where: { $0.id == navigation.selectedAgent }) { return navigation.selectedAgent }
        return workspaceProviders.first?.id ?? .codex
    }

    private func destinationTitle(_ destination: MainSurfaceDestination) -> String {
        switch destination {
        case .agents: localized("AUV", "AUV")
        case .threadOS: localized("ThreadOS", "ThreadOS（线程工）")
        case .sectorium: localized("Sectorium", "分区工")
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
    var geminiSettings: GeminiSettingsModel? = nil

    var body: some View {
        // As the main window: under a transparent title bar, the pane's
        // title in its row and the empty strip still moving the window.
        GeometryReader { proxy in
            let titlebarHeight = proxy.safeAreaInsets.top
            GlobalSettingsSurface(
                preferences: preferences,
                store: store,
                navigation: navigation,
                dataPaths: dataPaths,
                geminiSettings: geminiSettings,
                titlebarHeight: titlebarHeight
            )
            .background(alignment: .top) {
                AUVTitlebarDragArea().frame(height: titlebarHeight)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(AUVLook.current.isStandard ? Color.clear : UMAVisualStyle.canvas)
        .auvLookRoot()
    }
}
