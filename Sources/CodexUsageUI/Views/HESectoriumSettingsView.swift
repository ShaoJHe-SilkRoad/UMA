import HESectoriumRuntime
import SwiftUI

public struct HESectoriumSettingsView: View {
    @StateObject private var model: HESectoriumStore
    private let isChinese: Bool

    public init(isChinese: Bool = false, store: HESectoriumStore? = nil) {
        self.isChinese = isChinese
        _model = StateObject(wrappedValue: store ?? HESectoriumStore())
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent(text("Components", "组件"), value: installedText)
                LabeledContent(text("Automation preference", "自动化偏好"), value: model.snapshot.automationEnabled ? text("Enabled", "已启用") : text("Disabled", "已停用"))
                LabeledContent(text("Automation service", "自动化服务"), value: agentStatusText)
                LabeledContent(text("Operation", "操作状态"), value: operationText)
                LabeledContent(text("Storage readiness", "存储就绪状态"), value: readinessText)
                LabeledContent(text("Pending eject recovery", "待处理的弹出恢复"), value: model.snapshot.pendingEject.map { $0 ? text("Yes", "是") : text("No", "否") } ?? text("Unknown", "未知"))
                if case .missing = model.snapshot.installed {
                    HStack {
                        HESectoriumSettingsNativeButton(
                            title: text("Install HESectorium", "安装 HESectorium"),
                            identifier: "uma.settings.hesectorium.install", isEnabled: !model.isBusy,
                            action: model.install
                        )
                        HESectoriumSettingsNativeButton(
                            title: text("Repair HESectorium", "修复 HESectorium"),
                            identifier: "uma.settings.hesectorium.repair", isEnabled: !model.isBusy,
                            action: model.installRepair
                        )
                    }
                    .disabled(model.isBusy)
                } else {
                    HESectoriumSettingsNativeButton(
                        title: text("Repair HESectorium", "修复 HESectorium"),
                        identifier: "uma.settings.hesectorium.repair", isEnabled: !model.isBusy,
                        action: model.installRepair
                    )
                }
                HESectoriumSettingsNativeToggle(
                    title: text("Enable mount automation", "启用挂载自动化"),
                    identifier: "uma.settings.hesectorium.automation",
                    isOn: model.snapshot.automationEnabled, isEnabled: !model.isBusy,
                    action: model.setAutomation
                )
                HStack {
                    HESectoriumSettingsNativeButton(
                        title: text("Mount DEV", "挂载 DEV"), identifier: "uma.settings.hesectorium.mount",
                        isEnabled: !model.isBusy, action: model.mountDEV
                    )
                    HESectoriumSettingsNativeButton(
                        title: text("Safe Eject HE", "安全推出 HE"), identifier: "uma.settings.hesectorium.eject",
                        isEnabled: !model.isBusy, action: model.safeEjectHE
                    )
                }
                HESectoriumSettingsNativeButton(
                    title: text("Refresh Status", "刷新状态"), identifier: "uma.settings.hesectorium.refresh",
                    isEnabled: !model.isBusy, action: model.refresh
                )
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HESectorium").font(.title2.weight(.semibold))
                    Text(text("Manage storage readiness, explicit actions, and mount automation.", "管理存储就绪状态、显式操作和自动挂载。"))
                        .font(.callout).foregroundStyle(.secondary).textCase(nil)
                }
            }
            if !model.lastResult.isEmpty {
                Section(text("Latest operation", "最近操作")) {
                    Text(model.lastResult).accessibilityIdentifier("uma.settings.hesectorium.operation-result")
                }
            }
            Section(text("Diagnostics", "诊断信息")) {
                Text(model.snapshot.latestActionSummary)
                ForEach(Array(model.snapshot.diagnostics.suffix(8).enumerated()), id: \.offset) { _, item in
                    LabeledContent(item.category, value: item.summary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(14)
        .accessibilityIdentifier("uma.settings.hesectorium")
        .onAppear { model.refresh() }
    }

    private var installedText: String {
        switch model.snapshot.installed {
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
        switch model.snapshot.agentLoadStatus {
        case .loaded: text("Loaded", "已加载")
        case .notLoaded: text("Not loaded", "未加载")
        case .unknown: text("Unknown", "未知")
        }
    }
    private var operationText: String {
        switch model.snapshot.operationProgress {
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
            automationText: text("Automation preference: \(model.snapshot.automationEnabled ? "Enabled" : "Disabled")", "自动化偏好：\(model.snapshot.automationEnabled ? "已启用" : "已停用")"),
            agentStatusText: agentStatusText,
            isEnabled: !model.isBusy
        )
        .help(statusText)
        .onAppear { model.refresh() }
    }

    private var statusText: String {
        switch model.snapshot.readiness {
        case .ready: text("HESectorium ready", "HESectorium 已就绪")
        case .notReady(let reason): text("Storage not ready: \(reason)", "存储未就绪：\(reason)")
        case .unknown: text("Storage readiness unknown", "存储就绪状态未知")
        }
    }
    private var agentStatusText: String {
        switch model.snapshot.agentLoadStatus {
        case .loaded: text("Automation service loaded", "自动化服务已加载")
        case .notLoaded: text("Automation service not loaded", "自动化服务未加载")
        case .unknown: text("Automation service status unknown", "自动化服务状态未知")
        }
    }
    private func text(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }
}


private final class HESectoriumKeyboardButton: NSButton {
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
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = { _ in action() }
        button.title = title
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
    }
}

private struct HESectoriumSettingsNativeToggle: NSViewRepresentable {
    let title: String
    let identifier: String
    let isOn: Bool
    let isEnabled: Bool
    let action: (Bool) -> Void
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
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = { sender in action(sender.state == .on) }
        button.title = title
        button.state = isOn ? .on : .off
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
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
            addAction("Mount DEV", chinese: "挂载 DEV", image: "externaldrive.badge.plus", key: "mount", to: menu)
            addAction("Safe Eject HE", chinese: "安全推出 HE", image: "eject", key: "eject", to: menu)
            addAction("Refresh Status", chinese: "刷新状态", image: "arrow.clockwise", key: "refresh", to: menu)
            button.menu = menu
            button.selectItem(at: 0)
            button.isEnabled = isEnabled
            button.setAccessibilityLabel(storageLabel)
            button.setAccessibilityIdentifier("uma.hesectorium.quick-actions")
        }
        private func addAction(_ english: String, chinese: String, image: String, key: String, to menu: NSMenu) {
            let title = isCurrentChinese ? chinese : english
            let item = NSMenuItem(title: title, action: #selector(activate(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key
            item.image = NSImage(systemSymbolName: image, accessibilityDescription: title)
            menu.addItem(item)
        }
        private var isCurrentChinese = false
        @objc func activate(_ item: NSMenuItem) {
            switch item.representedObject as? String {
            case "mount": model.mountDEV()
            case "eject": model.safeEjectHE()
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
