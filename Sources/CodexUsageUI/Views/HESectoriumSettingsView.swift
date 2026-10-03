import HESectoriumRuntime
import SwiftUI

public struct HESectoriumSettingsView: View {
    @StateObject private var model: HESectoriumStore
    private let isChinese: Bool

    public init(isChinese: Bool = false) {
        self.isChinese = isChinese
        _model = StateObject(wrappedValue: HESectoriumStore())
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
                        Button(text("Install HESectorium", "安装 HESectorium")) { model.install() }
                        Button(text("Repair HESectorium", "修复 HESectorium")) { model.installRepair() }
                    }
                    .disabled(model.isBusy)
                } else {
                    Button(text("Repair HESectorium", "修复 HESectorium")) { model.installRepair() }
                        .disabled(model.isBusy)
                }
                Toggle(text("Enable mount automation", "启用挂载自动化"), isOn: Binding(
                    get: { model.snapshot.automationEnabled },
                    set: { model.setAutomation($0) }
                ))
                .disabled(model.isBusy)
                HStack {
                    Button(text("Mount DEV", "挂载 DEV")) { model.mountDEV() }
                    Button(text("Safe Eject HE", "安全推出 HE")) { model.safeEjectHE() }
                }
                .disabled(model.isBusy)
                Button(text("Refresh Status", "刷新状态")) { model.refresh() }
                    .disabled(model.isBusy)
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
    @StateObject private var model = HESectoriumStore()
    private let isChinese: Bool

    public init(isChinese: Bool = false) { self.isChinese = isChinese }

    public var body: some View {
        Menu {
            Text(statusText)
            Text(text("Automation preference: \(model.snapshot.automationEnabled ? "Enabled" : "Disabled")", "自动化偏好：\(model.snapshot.automationEnabled ? "已启用" : "已停用")"))
            Text(agentStatusText)
            Divider()
            Button(text("Mount DEV", "挂载 DEV"), systemImage: "externaldrive.badge.plus") { model.mountDEV() }
            Button(text("Safe Eject HE", "安全推出 HE"), systemImage: "eject") { model.safeEjectHE() }
            Button(text("Refresh Status", "刷新状态"), systemImage: "arrow.clockwise") { model.refresh() }
        } label: {
            Label(text("Storage", "存储"), systemImage: "externaldrive")
        }
        .disabled(model.isBusy)
        .help(statusText)
        .accessibilityIdentifier("uma.hesectorium.quick-actions")
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
