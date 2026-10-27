import HESectoriumRuntime
import SwiftUI

struct HESectoriumSettingsEjectPlan {
    let isPending: Bool
    let targetID: String?
    let canBegin: Bool
    let canContinue: Bool
    let canReturn: Bool

    static func make(pendingOperation: String?, pendingTargetID: String?,
                     selectedExternalDeviceID: String?, inventoryState: SectoriumInventoryState,
                     canBegin: Bool, canContinue: Bool, canReturn: Bool) -> Self {
        let inventoryObserved = inventoryState == .available || inventoryState == .empty
        if pendingOperation?.hasPrefix("eject:") == true {
            return .init(isPending: true, targetID: pendingTargetID, canBegin: false,
                         canContinue: inventoryObserved && pendingTargetID != nil && canContinue,
                         canReturn: inventoryObserved && pendingTargetID != nil && canReturn)
        }
        return .init(isPending: false, targetID: nil,
                     canBegin: pendingOperation == nil && inventoryState == .available
                         && selectedExternalDeviceID != nil && canBegin,
                     canContinue: false, canReturn: false)
    }
}

public struct HESectoriumSettingsView: View {
    @StateObject private var model: HESectoriumStore
    @State private var showingComponentDetails = false
    @State private var showingDiagnostics = false
    private let isChinese: Bool
    private let onClose: (() -> Void)?

    public init(isChinese: Bool = false, store: HESectoriumStore? = nil, onClose: (() -> Void)? = nil) {
        self.isChinese = isChinese
        self.onClose = onClose
        _model = StateObject(wrappedValue: store ?? HESectoriumStore())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                SectoriumSheetHeader(title: text("Sectorium settings", "分区工设置"),
                    subtitle: text("Automatic loading, components and recovery.", "自动加载、组件与操作恢复。"),
                    symbol: "slider.horizontal.3")
                Spacer(minLength: 8)
                if let onClose {
                    HESectoriumSettingsNativeButton(
                        title: text("Close", "关闭"), identifier: "uma.sectorium.settings.close",
                        isEnabled: true, action: onClose, onEscape: onClose)
                        .frame(width: 70, height: 30)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectoriumPreferenceSection(title: text("Automatic loading", "自动加载")) {
                        HESectoriumSettingsNativeToggle(
                            title: text("Background loading while AUV is closed", "AUV 关闭时后台自动加载"),
                            identifier: "uma.settings.hesectorium.automation",
                            isOn: model.snapshot.automationEnabled, isEnabled: model.hasObservedStatus && !model.isBusy,
                            action: model.setAutomation, onEscape: onClose)
                            .frame(height: 24)
                        Text(text("While AUV is open, each volume follows its own automatic-loading setting.",
                                  "AUV 运行时，按各开发卷的自动加载设置工作。"))
                            .font(.callout).foregroundStyle(.secondary)
                        if model.hasObservedStatus && model.snapshot.automationEnabled
                            && model.snapshot.agentLoadStatus != .loaded {
                            Label(text("Background loading is enabled in preferences, but its service has not been observed as loaded.",
                                       "偏好中已启用后台加载，但尚未观察到后台服务已加载。"), systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.orange)
                        }
                    }
                    SectoriumPreferenceSection(title: text("Components", "组件")) {
                        HStack(alignment: .center) {
                            Text(installedText).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            if case .missing = model.snapshot.installed {
                                HESectoriumSettingsNativeButton(
                                    title: text("Install HESectorium", "安装 HESectorium"),
                                    identifier: "uma.settings.hesectorium.install", isEnabled: model.hasObservedStatus && !model.isBusy,
                                    action: model.install, onEscape: onClose)
                                    .frame(width: 154, height: 30)
                            }
                            HESectoriumSettingsNativeButton(
                                title: text("Repair HESectorium", "修复 HESectorium"),
                                identifier: "uma.settings.hesectorium.repair", isEnabled: model.hasObservedStatus && !model.isBusy,
                                action: model.installRepair, onEscape: onClose)
                                .frame(width: 154, height: 30)
                        }
                        DisclosureGroup(isExpanded: $showingComponentDetails) {
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent(text("Components", "组件"), value: installedText)
                                LabeledContent(text("Background loading preference", "后台加载偏好"),
                                    value: model.hasObservedStatus
                                        ? (model.snapshot.automationEnabled ? text("Enabled", "已启用") : text("Disabled", "已停用"))
                                        : text("Unknown", "未知"))
                                LabeledContent(text("Background service", "后台服务"), value: agentStatusText)
                                LabeledContent(text("Operation", "操作状态"), value: operationText)
                                LabeledContent(text("Storage readiness", "存储就绪状态"), value: readinessText)
                                LabeledContent(text("Pending eject recovery", "待处理的弹出恢复"), value: model.snapshot.pendingEject.map { $0 ? text("Yes", "是") : text("No", "否") } ?? text("Unknown", "未知"))
                            }.padding(.top, 10)
                        } label: {
                            Text(text("Components and background service", "组件与后台服务"))
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                    SectoriumPreferenceSection(title: text("Drive recovery", "硬盘操作恢复")) {
                        LabeledContent(text("Selected drive", "所选硬盘"),
                            value: selectedExternalDevice?.name ?? text("Select an external drive in Sectorium", "请在分区工中选择外接硬盘"))
                            .font(.callout)
                        if ejectPlan.isPending {
                            LabeledContent(text("Pending safe eject target", "待恢复的安全弹出目标"), value: pendingDriveName)
                            if let targetID = ejectPlan.targetID, selectedExternalDevice?.id != targetID {
                                Text(text("Continue the recorded operation for \(pendingDriveName). Other drives will not be changed.",
                                          "继续 \(pendingDriveName) 上已记录的操作；不会更改其他硬盘。"))
                                    .font(.callout).foregroundStyle(.orange)
                                    .accessibilityIdentifier("uma.settings.hesectorium.pending-eject-target")
                            }
                            if ejectPlan.canContinue {
                                HESectoriumSettingsNativeButton(
                                    title: text("Continue safe eject for recorded drive", "继续已记录硬盘的安全弹出"),
                                    identifier: "uma.settings.hesectorium.eject", isEnabled: !model.isBusy,
                                    action: model.prepareContinueWholeDeviceEjectConfirmation, onEscape: onClose)
                                    .frame(height: 30).fixedSize(horizontal: true, vertical: false)
                            }
                            if ejectPlan.canReturn {
                                HESectoriumSettingsNativeButton(
                                    title: text("Return recorded drive to development", "将已记录硬盘恢复为开发状态"),
                                    identifier: "uma.settings.hesectorium.return", isEnabled: !model.isBusy,
                                    action: model.returnToDevelopment, onEscape: onClose)
                                    .frame(height: 30).fixedSize(horizontal: true, vertical: false)
                            }
                            if !ejectPlan.canContinue && !ejectPlan.canReturn {
                                Text(text("Recovery is unavailable until the recorded target is verified. Refresh status.",
                                          "已记录目标核实前无法恢复。请刷新状态。"))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        } else {
                            HESectoriumSettingsNativeButton(
                                title: text("Review safe eject", "查看安全弹出"), identifier: "uma.settings.hesectorium.eject",
                                isEnabled: !model.isBusy && ejectPlan.canBegin,
                                action: model.prepareWholeDeviceEjectConfirmation, onEscape: onClose)
                                .frame(width: 150, height: 30)
                        }
                        Text(text("To change a development volume or read its history, use More beside that volume in Sectorium.",
                                  "要修改开发卷或查看历史，请使用分区工中该卷旁的“更多”。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let notice = model.userNotice {
                        SectoriumPreferenceSection(title: text("Latest operation", "最近操作")) {
                            Text(notice.text(isChinese: isChinese)).font(.callout)
                                .accessibilityIdentifier("uma.settings.hesectorium.operation-result")
                        }
                    }
                    DisclosureGroup(isExpanded: $showingDiagnostics) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.snapshot.latestActionSummary)
                            if !model.lastResult.isEmpty { Text(model.lastResult).textSelection(.enabled) }
                            ForEach(Array(model.snapshot.diagnostics.suffix(8).enumerated()), id: \.offset) { _, item in
                                LabeledContent(item.category, value: item.summary)
                            }
                        }.font(.caption).padding(.top, 10)
                    } label: {
                        Label(text("Diagnostics", "诊断信息"), systemImage: "stethoscope")
                    }.font(.callout).foregroundStyle(.secondary)
                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text(text("Drive actions stay in Sectorium.", "硬盘的日常操作位于分区工主页。"))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                HESectoriumSettingsNativeButton(
                    title: text("Refresh Status", "刷新状态"), identifier: "uma.settings.hesectorium.refresh",
                    isEnabled: !model.isBusy, action: model.refresh, onEscape: onClose)
                    .frame(width: 120, height: 30)
            }
        }
        .padding(24)
        .frame(idealWidth: 560, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("uma.settings.hesectorium")
        .onExitCommand { onClose?() }
        .onAppear { model.activateSettings() }
        .onDisappear { model.deactivateSettings() }
        .sheet(isPresented: Binding(get: { model.wholeDeviceEjectConfirmation != nil },
                                    set: { if !$0 { model.cancelWholeDeviceEjectConfirmation() } })) {
            SectoriumWholeDeviceEjectConfirmationView(model: model, isChinese: isChinese,
                selectedDeviceName: confirmedEjectDeviceName)
        }
    }

    private var pendingDriveName: String {
        guard let id = ejectPlan.targetID else { return text("Drive not verified", "硬盘尚未核实") }
        return model.workbench.devices.first { $0.id == id }?.name
            ?? model.volumeRows.first { $0.parentDeviceID == id }?.parentName
            ?? text("Previously selected drive", "此前选定的硬盘")
    }

    private var confirmedEjectDeviceName: String? {
        guard let targetID = model.wholeDeviceEjectConfirmation?.physicalIdentity else { return nil }
        return model.workbench.devices.first { $0.id == targetID && $0.isVirtual == false }?.name
    }

    private var selectedExternalDevice: SectoriumPhysicalDevice? {
        model.workbench.devices.first { $0.id == model.workbench.selectedDeviceID
            && $0.isVirtual == false && $0.isExternal && $0.identityVerified }
    }

    private var ejectPlan: HESectoriumSettingsEjectPlan {
        .make(pendingOperation: model.workbench.pendingOperation,
              pendingTargetID: model.pendingWholeDeviceEjectTargetID,
              selectedExternalDeviceID: selectedExternalDevice?.id,
              inventoryState: model.inventoryState,
              canBegin: model.canBeginWholeDeviceEject,
              canContinue: model.canContinueWholeDeviceEject,
              canReturn: model.canReturnFromWholeDeviceEject)
    }

    private var installedText: String {
        guard model.hasObservedStatus else { return text("Unknown", "未知") }
        return switch model.snapshot.installed {
        case .installed: text("Installed", "已安装")
        case .missing: text("Not installed", "未安装")
        case .conflict(let reason): text("Conflict: \(reason)", "存在冲突：\(reason)")
        }
    }
    private var readinessText: String {
        switch model.snapshot.readiness {
        case .ready: text("Ready", "就绪")
        case .notReady(let reason): text("Not ready: \(reason)", "未就绪：\(reason)")
        case .unknown: text("Unknown", "未知")
        }
    }
    private var agentStatusText: String {
        guard model.hasObservedStatus else { return text("Unknown", "未知") }
        return switch model.snapshot.agentLoadStatus {
        case .loaded: text("Loaded", "已加载")
        case .notLoaded: text("Not loaded", "未加载")
        case .unknown: text("Unknown", "未知")
        }
    }
    private var operationText: String {
        guard model.hasObservedStatus else { return text("Unknown", "未知") }
        return switch model.snapshot.operationProgress {
        case .idle: text("Idle", "空闲")
        case .running(let action): text("Running: \(action)", "正在运行：\(action)")
        }
    }
    private func text(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }
}

public struct HESectoriumStatusControl: View {
    @StateObject private var model: HESectoriumStore
    private let isChinese: Bool

    public init(isChinese: Bool = false, store: HESectoriumStore? = nil) {
        self.isChinese = isChinese
        _model = StateObject(wrappedValue: store ?? HESectoriumStore())
    }

    public var body: some View {
        HESectoriumNativeQuickActions(
            model: model,
            isChinese: isChinese,
            readinessText: statusText,
            automationText: model.hasObservedStatus
                ? text("Background loading: \(model.snapshot.automationEnabled ? "Enabled" : "Disabled")", "后台加载：\(model.snapshot.automationEnabled ? "已启用" : "已停用")")
                : text("Background loading: Unknown", "后台加载：未知"),
            agentStatusText: agentStatusText,
            isEnabled: !model.isBusy
        )
        .help(statusText)
        .onAppear { model.activateSettings() }
        .onDisappear { model.deactivateSettings() }
        .sheet(isPresented: Binding(get: { model.wholeDeviceEjectConfirmation != nil },
                                    set: { if !$0 { model.cancelWholeDeviceEjectConfirmation() } })) {
            SectoriumWholeDeviceEjectConfirmationView(model: model, isChinese: isChinese,
                selectedDeviceName: model.wholeDeviceEjectConfirmation.flatMap { confirmation in
                    model.workbench.devices.first {
                        $0.id == confirmation.physicalIdentity && $0.isVirtual == false
                    }?.name
                })
        }
    }

    private var statusText: String {
        switch model.snapshot.readiness {
        case .ready: text("HESectorium ready", "HESectorium 已就绪")
        case .notReady(let reason): text("Storage not ready: \(reason)", "存储未就绪：\(reason)")
        case .unknown: text("Storage readiness unknown", "存储就绪状态未知")
        }
    }
    private var agentStatusText: String {
        guard model.hasObservedStatus else {
            return text("Background service status unknown", "后台服务状态未知")
        }
        return switch model.snapshot.agentLoadStatus {
        case .loaded: text("Background service loaded", "后台服务已加载")
        case .notLoaded: text("Background service not loaded", "后台服务未加载")
        case .unknown: text("Background service status unknown", "后台服务状态未知")
        }
    }
    private func text(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }
}


private final class HESectoriumKeyboardButton: NSButton {
    var onEscape: (() -> Void)?
    /// SwiftUI re-applies its own enabled environment to a hosted control after
    /// `updateNSView`, which turned an explicit `false` back into `true`: the
    /// eject button stayed active, and focusable, without a verified target.
    /// The view's own answer is latched here, as the workbench button does,
    /// so the environment can narrow it but never widen it.
    private var settingsEnabled = true
    override var isEnabled: Bool {
        get { settingsEnabled && super.isEnabled }
        set { super.isEnabled = settingsEnabled && newValue }
    }
    func setSettingsEnabled(_ enabled: Bool) {
        settingsEnabled = enabled
        super.isEnabled = enabled
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape { onEscape(); return }
        super.keyDown(with: event)
    }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }
}

@MainActor
final class HESectoriumSettingsControlCoordinator: NSObject {
    var action: (NSButton) -> Void

    init(action: @escaping (NSButton) -> Void) {
        self.action = action
    }

    @objc func activate(_ sender: NSButton) {
        guard sender.isEnabled else { return }
        action(sender)
    }
}

private struct HESectoriumSettingsNativeButton: NSViewRepresentable {
    let title: String
    let identifier: String
    let isEnabled: Bool
    let action: () -> Void
    var onEscape: (() -> Void)? = nil
    func makeCoordinator() -> HESectoriumSettingsControlCoordinator {
        HESectoriumSettingsControlCoordinator { _ in action() }
    }
    func makeNSView(context: Context) -> NSButton {
        let button = HESectoriumKeyboardButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        button.onEscape = onEscape
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = { _ in action() }
        button.title = title
        (button as? HESectoriumKeyboardButton)?.setSettingsEnabled(isEnabled)
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        (button as? HESectoriumKeyboardButton)?.onEscape = onEscape
    }
}

private struct HESectoriumSettingsNativeToggle: NSViewRepresentable {
    let title: String
    let identifier: String
    let isOn: Bool
    let isEnabled: Bool
    let action: (Bool) -> Void
    var onEscape: (() -> Void)? = nil
    func makeCoordinator() -> HESectoriumSettingsControlCoordinator {
        HESectoriumSettingsControlCoordinator { sender in action(sender.state == .on) }
    }
    func makeNSView(context: Context) -> NSButton {
        let button = HESectoriumKeyboardButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.setButtonType(.switch)
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        button.onEscape = onEscape
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = { sender in action(sender.state == .on) }
        button.title = title
        button.state = isOn ? .on : .off
        (button as? HESectoriumKeyboardButton)?.setSettingsEnabled(isEnabled)
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        (button as? HESectoriumKeyboardButton)?.onEscape = onEscape
    }
}

private struct HESectoriumNativeQuickActions: NSViewRepresentable {
    let model: HESectoriumStore
    let isChinese: Bool
    let readinessText: String
    let automationText: String
    let agentStatusText: String
    let isEnabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = HESectoriumKeyboardPopupButton(frame: .zero, pullsDown: true)
        button.controlSize = .regular
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(isChinese ? "存储" : "Storage")
        button.setAccessibilityIdentifier("uma.hesectorium.quick-actions")
        context.coordinator.update(button, isChinese: isChinese, readinessText: readinessText,
                                   automationText: automationText, agentStatusText: agentStatusText, isEnabled: isEnabled)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.model = model
        context.coordinator.update(button, isChinese: isChinese, readinessText: readinessText,
                                   automationText: automationText, agentStatusText: agentStatusText, isEnabled: isEnabled)
    }
    @MainActor final class Coordinator: NSObject {
        var model: HESectoriumStore
        init(model: HESectoriumStore) { self.model = model }
        func update(_ button: NSPopUpButton, isChinese: Bool, readinessText: String,
                    automationText: String, agentStatusText: String, isEnabled: Bool) {
            isCurrentChinese = isChinese
            let storageLabel = isChinese ? "存储" : "Storage"
            let menu = NSMenu(title: storageLabel)
            let title = NSMenuItem(title: storageLabel, action: nil, keyEquivalent: "")
            title.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: storageLabel)
            menu.addItem(title)
            let readiness = NSMenuItem(title: readinessText, action: nil, keyEquivalent: "")
            readiness.isEnabled = false; menu.addItem(readiness)
            let automation = NSMenuItem(title: automationText, action: nil, keyEquivalent: "")
            automation.isEnabled = false; menu.addItem(automation)
            let agent = NSMenuItem(title: agentStatusText, action: nil, keyEquivalent: "")
            agent.isEnabled = false; menu.addItem(agent)
            menu.addItem(.separator())
            let selectedProfile = model.workbench.profiles.first { $0.id == model.workbench.selectedProfileID }
            let canLoad = model.inventoryState == .available
                && model.hasObservedStatus
                && model.workbench.readiness == .notStarted
                && selectedProfile?.hasVerifiedImageFormat == true
                && selectedProfile?.encrypted == false
            let selectedExternalID = model.workbench.devices.first(where: {
                $0.id == model.workbench.selectedDeviceID
                    && $0.isVirtual == false && $0.isExternal && $0.identityVerified
            })?.id
            let ejectPlan = HESectoriumSettingsEjectPlan.make(
                pendingOperation: model.workbench.pendingOperation,
                pendingTargetID: model.pendingWholeDeviceEjectTargetID,
                selectedExternalDeviceID: selectedExternalID,
                inventoryState: model.inventoryState,
                canBegin: model.canBeginWholeDeviceEject,
                canContinue: model.canContinueWholeDeviceEject,
                canReturn: model.canReturnFromWholeDeviceEject)
            addAction("Load development disk", chinese: "加载开发盘", image: "externaldrive.badge.plus",
                key: "mount", isEnabled: canLoad, to: menu)
            if ejectPlan.isPending {
                let target = ejectPlan.targetID ?? (isChinese ? "未核实" : "Unverified")
                addAction("Pending safe eject: \(target)", chinese: "待恢复安全弹出：\(target)",
                    image: "externaldrive", key: "pending-target", isEnabled: false, to: menu)
                addAction("Continue recorded drive eject", chinese: "继续已记录硬盘弹出", image: "eject",
                    key: "continue-eject", isEnabled: ejectPlan.canContinue, to: menu)
                addAction("Return recorded drive to development", chinese: "将已记录硬盘恢复为开发状态",
                    image: "arrow.uturn.backward", key: "return-eject", isEnabled: ejectPlan.canReturn, to: menu)
            } else {
                addAction("Review safe eject", chinese: "查看安全弹出", image: "eject",
                    key: "eject", isEnabled: ejectPlan.canBegin, to: menu)
            }
            addAction("Refresh Status", chinese: "刷新状态", image: "arrow.clockwise",
                key: "refresh", isEnabled: true, to: menu)
            button.menu = menu
            button.selectItem(at: 0)
            button.isEnabled = isEnabled
            button.setAccessibilityLabel(storageLabel)
            button.setAccessibilityIdentifier("uma.hesectorium.quick-actions")
        }
        private func addAction(_ english: String, chinese: String, image: String, key: String,
                               isEnabled: Bool, to menu: NSMenu) {
            let title = isCurrentChinese ? chinese : english
            let item = NSMenuItem(title: title, action: #selector(activate(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key
            item.image = NSImage(systemSymbolName: image, accessibilityDescription: title)
            item.isEnabled = isEnabled
            menu.addItem(item)
        }
        private var isCurrentChinese = false
        @objc func activate(_ item: NSMenuItem) {
            switch item.representedObject as? String {
            case "mount": model.startDevelopmentDisk()
            case "eject": model.prepareWholeDeviceEjectConfirmation()
            case "continue-eject": model.prepareContinueWholeDeviceEjectConfirmation()
            case "return-eject": model.returnToDevelopment()
            case "refresh": model.refresh()
            default: break
            }
        }
    }
}

private final class HESectoriumKeyboardPopupButton: NSPopUpButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }
}
