import AppKit
import HESectoriumRuntime
import SwiftUI

enum SectoriumVolumeNameInput {
    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 80 && !name.hasPrefix(".")
            && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && !name.contains("/") && !name.contains(":")
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

enum SectoriumCapacityInput {
    static let maximumGiB = 16_384
    private static let bytesPerGiB: UInt64 = 1_073_741_824

    static func isValid(_ gib: Int) -> Bool { (1...maximumGiB).contains(gib) }

    static func requestedBytes(gib: Int) -> UInt64? {
        guard isValid(gib) else { return nil }
        let (bytes, overflow) = UInt64(gib).multipliedReportingOverflow(by: bytesPerGiB)
        return overflow ? nil : bytes
    }

    static func recommendedGiB(availableBytes: UInt64) -> Int? {
        let fourFifths = (availableBytes / 5) * 4 + ((availableBytes % 5) * 4) / 5
        let gib = fourFifths / bytesPerGiB
        guard gib > 0 else { return nil }
        return min(maximumGiB, Int(gib))
    }
}

enum SectoriumWorkbenchAction: String, CaseIterable, Equatable {
    case setupComponents, create, adopt, start, stop, resume, continueEject, returnToDevelopment, eject, recheck
}

enum SectoriumWorkbenchDeviceOrdering {
    static func externalFirst(_ devices: [SectoriumPhysicalDevice]) -> [SectoriumPhysicalDevice] {
        devices.sorted {
            if $0.isExternal != $1.isExternal { return $0.isExternal }
            let byName = $0.name.localizedStandardCompare($1.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending
        }
    }

    static func defaultSelection(from devices: [SectoriumPhysicalDevice]) -> SectoriumPhysicalDevice? {
        externalFirst(devices.filter { $0.isVirtual == false && $0.identityVerified }).first
    }
}

private struct SectoriumParentGroup: Identifiable {
    let id: String
    let name: String
    let isExternal: Bool
    let device: SectoriumPhysicalDevice?
    let rows: [SectoriumVolumeRow]
}

enum SectoriumVolumePrimaryAction: Equatable {
    case load, safelyUnloadAndEject, unloadOnly, recheck
}

struct SectoriumVolumeActionPlan: Equatable {
    let action: SectoriumVolumePrimaryAction
    let enabled: Bool
    let disconnectEnabled: Bool?

    static func make(verifiedLoaded: Bool?, isExternal: Bool, canLoad: Bool,
                     canUnloadOnly: Bool, canSafeUnloadAndEject: Bool, busy: Bool) -> Self {
        let action: SectoriumVolumePrimaryAction
        let available: Bool
        switch verifiedLoaded {
        case true:
            action = .unloadOnly; available = canUnloadOnly
        case false:
            action = .load; available = canLoad
        case nil:
            action = .recheck; available = true
        }
        return .init(action: action, enabled: available && !busy,
            disconnectEnabled: verifiedLoaded == true && isExternal ? canSafeUnloadAndEject && !busy : nil)
    }
}

enum SectoriumLegacyPresentationPolicy {
    static func currentLegacyState(inventoryAvailable: Bool, busy: Bool, pending: Bool,
                                   stale: Bool, identityVerified: Bool,
                                   readiness: SectoriumWorkbenchReadiness,
                                   observed: SectoriumWorkbenchActionPlan.LegacyState)
        -> SectoriumWorkbenchActionPlan.LegacyState {
        guard inventoryAvailable, !busy, !pending, !stale, identityVerified else { return .none }
        if observed == .unknown { return .unknown }
        switch (readiness, observed) {
        case (.connected, .mounted), (.notStarted, .detached), (.noDevelopmentDisk, .detached): return observed
        default: return .none
        }
    }
}

struct SectoriumWorkbenchActionPlan: Equatable {
    enum LegacyState: Equatable { case none, mounted, detached, unknown }
    enum UnavailableReason: Equatable {
        case chooseDrive, inventoryUnavailable, busy, pending, identityUnavailable, stale, stateUnknown, imageFormatUnknown
    }
    struct Input {
        var hasDrive: Bool
        var identityVerified: Bool
        var external: Bool
        var stale: Bool
        var inventoryAvailable: Bool
        var busy: Bool
        var readiness: SectoriumWorkbenchReadiness
        var hasProfile: Bool
        var profileFormatVerified: Bool
        var legacyState: LegacyState
        var pendingOperation: String?
        var canBeginEject: Bool
        var canContinueEject: Bool
        var canReturnFromEject: Bool
        var componentSetupNeeded: Bool = false
    }

    let primary: SectoriumWorkbenchAction?
    let secondary: [SectoriumWorkbenchAction]
    let recovery: [SectoriumWorkbenchAction]
    let unavailableReason: UnavailableReason?

    static func make(_ input: Input) -> Self {
        if let pending = input.pendingOperation {
            guard !input.busy else {
                return .init(primary: nil, secondary: [], recovery: [], unavailableReason: .busy)
            }
            guard input.inventoryAvailable else {
                return .init(primary: .recheck, secondary: [], recovery: [], unavailableReason: .inventoryUnavailable)
            }
            if pending.hasPrefix("eject:") {
                let recovery: [SectoriumWorkbenchAction] = [
                    input.canContinueEject ? .continueEject : nil,
                    input.canReturnFromEject ? .returnToDevelopment : nil
                ].compactMap { $0 }
                return .init(primary: recovery.first ?? .recheck, secondary: [], recovery: recovery,
                             unavailableReason: recovery.isEmpty ? .stateUnknown : nil)
            }
            return .init(primary: .resume, secondary: [], recovery: [.resume], unavailableReason: nil)
        }
        guard input.hasDrive else {
            return .init(primary: nil, secondary: [], recovery: [], unavailableReason: .chooseDrive)
        }
        guard input.inventoryAvailable else {
            return .init(primary: .recheck, secondary: [], recovery: [], unavailableReason: .inventoryUnavailable)
        }
        guard !input.busy else {
            return .init(primary: nil, secondary: [], recovery: [], unavailableReason: .busy)
        }
        guard input.identityVerified else {
            return .init(primary: .recheck, secondary: [], recovery: [], unavailableReason: .identityUnavailable)
        }
        guard !input.stale else {
            return .init(primary: .recheck, secondary: [], recovery: [], unavailableReason: .stale)
        }
        if input.canReturnFromEject {
            return .init(primary: .returnToDevelopment, secondary: [], recovery: [.returnToDevelopment],
                         unavailableReason: nil)
        }
        switch input.readiness {
        case .busy:
            return .init(primary: nil, secondary: [], recovery: [], unavailableReason: .busy)
        case .unknown, .partialFailure, .operationInProgress:
            return .init(primary: .recheck, secondary: [], recovery: [], unavailableReason: .stateUnknown)
        case .ejected:
            return .init(primary: nil, secondary: [], recovery: [], unavailableReason: nil)
        default:
            break
        }

        let primary: SectoriumWorkbenchAction?
        var reason: UnavailableReason?
        if input.legacyState == .mounted,
           input.readiness == .connected, input.external, input.canBeginEject {
            primary = .eject
        } else if input.legacyState == .mounted || input.legacyState == .detached {
            primary = .adopt
        } else if input.legacyState == .unknown {
            return .init(primary: .recheck, secondary: [], recovery: [], unavailableReason: .stateUnknown)
        } else if input.hasProfile {
            switch input.readiness {
            case .ready: primary = input.external && input.canBeginEject ? .eject : .recheck
            case .notStarted, .awaitingUnlock:
                primary = input.profileFormatVerified ? .start : .recheck
                if !input.profileFormatVerified { reason = .imageFormatUnknown }
            case .readOnly:
                primary = input.external && input.canBeginEject ? .eject : .recheck
            default:
                primary = .recheck
                reason = .stateUnknown
            }
        } else {
            switch input.readiness {
            case .connected, .noDevelopmentDisk, .notStarted:
                primary = input.componentSetupNeeded ? .setupComponents : .create
            case .readOnly:
                primary = input.external && input.canBeginEject ? .eject : .recheck
            default:
                primary = .recheck
                reason = .stateUnknown
            }
        }

        var secondary: [SectoriumWorkbenchAction] = []
        if input.readiness == .connected || input.readiness == .noDevelopmentDisk
            || input.readiness == .notStarted || input.readiness == .awaitingUnlock || input.readiness == .ready {
            if primary != .create && input.legacyState == .none && !input.componentSetupNeeded {
                secondary.append(.create)
            }
            if !input.hasProfile && (input.legacyState == .none
                || (input.legacyState == .mounted && primary == .eject)) {
                secondary.append(.adopt)
            }
        }
        if input.external && input.canBeginEject
            && (input.readiness == .connected || input.readiness == .noDevelopmentDisk
                || input.readiness == .notStarted || input.readiness == .awaitingUnlock
                || input.readiness == .ready || input.readiness == .readOnly) {
            if primary != .eject { secondary.append(.eject) }
        }
        if input.hasProfile && (input.readiness == .ready || input.readiness == .readOnly) {
            secondary.append(.stop)
        }
        return .init(primary: primary, secondary: secondary, recovery: [], unavailableReason: reason)
    }
}

public struct SectoriumWorkbenchView: View {
    @StateObject private var model: HESectoriumStore
    private let isChinese: Bool
    @State private var showingSettings = false
    @StateObject private var settingsButtonRef = SectoriumWeakButtonReference()
    @State private var showingCreate = false
    @State private var creationDeviceID = ""
    @State private var creationFilesystemID = SectoriumFilesystem.apfs.rawValue
    @State private var creationAutoLoad = true
    @State private var creationMountPoint = ""
    @State private var showingCreationOptions = false
    @State private var showingVolumeSettings = false
    @State private var settingsProfileID = ""
    @State private var editDisplayName = ""
    @State private var editMountPoint = ""
    @State private var editAutoLoad = true
    @State private var editCapacityGiB = 100
    @State private var unlockProfileID = ""
    @State private var expandedVolumeDetails: Set<String> = []
    @State private var showingLegacyAdoptionConfirmation = false
    @State private var adoptionDeviceID = ""
    @State private var showingUnlock = false
    @State private var profileName = "Development"
    @State private var capacityGiB = 100
    @State private var encrypted = false
    @State private var password = ""
    @State private var unlockPassword = ""

    public init(store: HESectoriumStore? = nil, isChinese: Bool = false) {
        _model = StateObject(wrappedValue: store ?? HESectoriumStore())
        self.isChinese = isChinese
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                workbenchHeader
                operationStatus
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(text("YOUR DRIVES", "你的硬盘"))
                            .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                        Spacer()
                        Button { prepareCreation() } label: {
                            Label(text("Create volume", "创建开发卷"), systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isBusy || model.registryUnavailable || creatableDevices.isEmpty)
                        .accessibilityIdentifier("uma.sectorium.create")
                    }
                    inventoryNotices
                    ForEach(parentGroups) { group in parentSection(group) }
                }
                if !unassignedDevices.isEmpty {
                    DisclosureGroup(text("Other observed devices", "其他已观察设备")) {
                        Text(text("These devices could not be linked to one physical parent and are not offered as action targets.",
                                  "这些设备尚无法关联到唯一物理母盘，因此不提供操作。"))
                        ForEach(unassignedDevices) { device in
                            Text(device.name).accessibilityIdentifier("uma.sectorium.unassigned-device")
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                }
                if model.userNotice != nil {
                    DisclosureGroup(text("Latest operation details", "最近操作详情")) {
                        Text(model.lastResult).font(.caption).textSelection(.enabled)
                        ForEach(Array(model.workbench.operationSteps.enumerated()), id: \.offset) { _, step in
                            Text("\(step.step): \(step.detail)").font(.caption).textSelection(.enabled)
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("uma.sectorium.operation-details")
                }
            }
            .padding(28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("uma.sectorium.workbench")
        .onAppear { model.activateWorkbench() }
        .onDisappear { model.deactivateWorkbench() }
        .sheet(isPresented: $showingCreate) { createSheet }
        .sheet(isPresented: $showingUnlock) { unlockSheet }
        .sheet(isPresented: $showingVolumeSettings) { volumeSettingsSheet }
        .sheet(isPresented: $showingSettings, onDismiss: restoreSettingsFocus) {
            HESectoriumSettingsView(isChinese: isChinese, store: model) {
                showingSettings = false
            }
        }
        .sheet(isPresented: Binding(get: { !showingSettings && model.wholeDeviceEjectConfirmation != nil }, set: { if !$0 { model.cancelWholeDeviceEjectConfirmation() } })) {
            ejectConfirmationSheet
        }
        .sheet(isPresented: Binding(get: { model.safetyCheck != nil }, set: { if !$0 { model.cancelSafetyCheck() } })) {
            SectoriumActivityCheckView(model: model, isChinese: isChinese)
        }
        .alert(text("Adopt existing development disk?", "接纳已有开发盘？"), isPresented: $showingLegacyAdoptionConfirmation) {
            Button(text("Cancel", "取消"), role: .cancel) {}
            Button(text("Adopt verified DEV_APFS", "接纳已核实的 DEV_APFS")) {
                guard !adoptionDeviceID.isEmpty else { return }
                model.adoptConfiguredLegacyDevelopmentDisk(deviceID: adoptionDeviceID)
            }
        } message: {
            Text(text("AUV will register the configured image only after rechecking the drive and complete image-to-volume identity. No files will be moved or deleted.",
                      "AUV 仅会在重新核验硬盘及完整镜像与卷身份后登记已配置的镜像；不会移动或删除文件。"))
        }
    }

    private var workbenchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(text("Sectorium", "分区工"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer(minLength: 8)
                SectoriumWorkbenchButton(title: text("Refresh", "刷新"), identifier: "uma.sectorium.refresh",
                    isEnabled: !model.isBusy, controlSize: .small) { model.refresh() }
                    .frame(width: 78, height: 28)
                SectoriumWorkbenchButton(title: text("Settings", "设置"), identifier: "uma.sectorium.settings",
                    isEnabled: true, controlSize: .small, action: {
                        settingsButtonRef.ownerWindow = settingsButtonRef.button?.window
                        showingSettings = true
                    }, onReady: { settingsButtonRef.button = $0 })
                    .frame(width: 78, height: 28)
            }
            Text(text("Your development volumes. Load to work, disconnect to unplug.",
                      "管理开发空间。加载后开始工作，安全断开后拔出硬盘。"))
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var operationStatus: some View {
        if model.isBusy || model.workbench.pendingOperation != nil || model.workbench.safeToUnplug || model.userNotice != nil {
            VStack(alignment: .leading, spacing: 10) {
                if model.isBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.progressNotice.text(isChinese: isChinese)).font(.callout)
                    }
                }
                if let pending = model.workbench.pendingOperation, !model.isBusy {
                    Label(model.pendingEjectDriveDisconnected
                        ? text("Drive disconnected. Updating its operation status.", "硬盘已断开，正在更新操作状态。")
                        : text("An earlier storage operation needs attention.", "此前一项存储操作需要处理。"),
                        systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("uma.sectorium.pending-operation")
                    if pending.hasPrefix("eject:") {
                        pendingEjectActions
                    } else {
                        Button(text("Continue operation", "继续操作")) { model.resumePendingOperation() }
                            .disabled(model.isBusy)
                    }
                }
                if model.workbench.safeToUnplug {
                    Label(text("Disconnect successful. You can unplug \(model.safeToUnplugDriveName ?? "the drive").",
                               "安全断开成功，现在可以拔出 \(model.safeToUnplugDriveName ?? "硬盘")。"),
                          systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.green)
                        .accessibilityIdentifier("uma.sectorium.safe-to-unplug")
                }
                if !model.isBusy, !model.workbench.safeToUnplug, let notice = model.userNotice {
                    Text(notice.text(isChinese: isChinese)).font(.callout)
                        .accessibilityIdentifier("uma.sectorium.operation-summary")
                }
            }
            .padding(.vertical, 13).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var inventoryNotices: some View {
        if model.inventoryState != .available && model.inventoryState != .empty {
            Text(inventoryMessage).font(.callout).foregroundStyle(.secondary)
        }
        if model.registryUnavailable {
            Label(text("Saved volume registrations could not be read. Existing records are preserved; refresh to retry.",
                       "无法读取已保存的开发卷登记。已有记录保持原样，请刷新重试。"), systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
                .accessibilityIdentifier("uma.sectorium.registry-unavailable")
        }
        if let reason = model.inventoryFailureDescription {
            DisclosureGroup(text("Drive detection details", "硬盘检测详情")) {
                Text(reason).font(.caption).textSelection(.enabled)
            }
        }
        if parentGroups.isEmpty && model.inventoryState == .empty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "externaldrive.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
                Text(text("Connect a drive to get started", "连接硬盘，开始使用")).font(.headline)
                Text(text("Connected drives appear here automatically. You can also refresh to check again.",
                          "连接的硬盘会自动显示，也可以点击刷新重新检查。"))
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(.vertical, 24)
        }
    }

    private var creatableDevices: [SectoriumPhysicalDevice] {
        physicalDevices.filter { $0.identityVerified && $0.topologyComplete }
    }

    private var parentGroups: [SectoriumParentGroup] {
        let observed = physicalDevices.map { device in
            SectoriumParentGroup(id: device.id, name: device.name, isExternal: device.isExternal,
                device: device, rows: model.volumeRows.filter { $0.parentDeviceID == device.id })
        }
        let observedIDs = Set(observed.map(\.id))
        let missing = Dictionary(grouping: model.volumeRows.filter { !observedIDs.contains($0.parentDeviceID) },
                                 by: \.parentDeviceID)
            .map { id, rows in
                SectoriumParentGroup(id: id, name: rows.first?.parentName ?? text("Disconnected drive", "未连接的硬盘"),
                    isExternal: rows.first?.isExternal ?? true, device: nil, rows: rows)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (observed + missing).sorted {
            if $0.isExternal != $1.isExternal { return $0.isExternal }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder private var pendingEjectActions: some View {
        if let target = model.pendingWholeDeviceEjectTargetID {
            let name = model.workbench.devices.first { $0.id == target }?.name
                ?? model.volumeRows.first { $0.parentDeviceID == target }?.parentName
                ?? text("the previously selected drive", "此前选定的硬盘")
            Text(text("Continue the interrupted operation for \(name).",
                      "继续 \(name) 上未完成的操作。"))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("uma.sectorium.pending-eject-target")
        }
        HStack {
            if model.canContinueWholeDeviceEject {
                Button(text("Continue Disconnect", "继续安全断开")) {
                    model.prepareContinueWholeDeviceEjectConfirmation()
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("uma.sectorium.continue-eject")
            }
            if model.canReturnFromWholeDeviceEject {
                Button(text("Cancel Disconnect · Return to development", "取消断开，返回开发环境")) { model.returnToDevelopment() }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("uma.sectorium.return-to-development")
            }
            if !model.canContinueWholeDeviceEject && !model.canReturnFromWholeDeviceEject {
                Button(text("Recheck", "重新检查")) { model.refresh() }
                    .disabled(model.isBusy)
            }
        }
    }

    private func parentSection(_ group: SectoriumParentGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: group.isExternal ? "externaldrive" : "internaldrive")
                    .font(.system(size: 24, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: 32, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.device.map(physicalTitle) ?? group.name).font(.headline)
                    HStack(spacing: 6) {
                        Text(group.isExternal ? text("External drive", "外接硬盘") : text("Internal storage", "内置存储"))
                        if let bytes = group.device?.wholeDeviceBytes {
                            Text("·")
                            Text(formatBytes(bytes))
                        }
                        if group.device == nil {
                            Text("·")
                            Text(text("Disconnected", "已断开"))
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let device = group.device, device.identityVerified {
                    Menu {
                        Button(text("Create on this drive", "在此硬盘创建")) { prepareCreation(on: device.id) }
                            .disabled(model.isBusy || model.registryUnavailable)
                        if model.legacyDevelopmentByDevice[device.id] == nil {
                            Button(group.rows.isEmpty
                                ? text("Register existing image…", "登记已有镜像…")
                                : text("Register another image…", "登记其他镜像…")) { adoptExisting(on: device) }
                                .disabled(model.isBusy || model.registryUnavailable || (!model.hasObservedRegistrations && group.rows.isEmpty))
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel(text("Drive options for \(group.name)", "\(group.name) 的硬盘选项"))
                    .accessibilityIdentifier("uma.sectorium.parent-options.\(group.id)")
                }
            }
            .accessibilityIdentifier("uma.sectorium.parent.\(group.id)")

            if let legacy = model.legacyDevelopmentByDevice[group.id] {
                Divider()
                legacyVolumeRow(legacy, parentID: group.id)
            } else if group.rows.isEmpty && !model.registryUnavailable {
                Text(model.hasObservedRegistrations
                    ? text("No development volume registered on this drive.", "此硬盘尚无已登记的开发卷。")
                    : text("Checking development volumes…", "正在识别开发卷…"))
                    .font(.callout).foregroundStyle(.secondary)
                if let device = group.device, device.identityVerified {
                    HStack(spacing: 14) {
                        Button(text("Create volume", "创建开发卷")) { prepareCreation(on: device.id) }
                            .disabled(model.isBusy || model.registryUnavailable)
                        Button(text("Register existing…", "登记已有开发卷…")) { adoptExisting(on: device) }
                            .buttonStyle(.borderless)
                            .disabled(model.isBusy || model.registryUnavailable || !model.hasObservedRegistrations)
                    }
                }
            }
            ForEach(group.rows) { row in
                Divider()
                volumeRow(row)
            }
            DisclosureGroup(text("Drive details", "硬盘详情")) {
                VStack(alignment: .leading, spacing: 10) {
                    if let device = group.device {
                        Text(deviceLabel(device)).textSelection(.enabled)
                        Text(identityDescription(device)).textSelection(.enabled)
                        if model.workbench.selectedDeviceID != device.id {
                            Button(text("Show drive activity", "查看硬盘活动")) { model.selectDevice(device.id) }
                                .disabled(model.isBusy)
                        } else {
                            if !device.isExternal {
                                Toggle(text("Read whole-drive I/O for this internal drive", "读取此内置硬盘的整盘 I/O"), isOn: Binding(
                                    get: { model.isLocalDeviceSamplingConsented(device.id) },
                                    set: { model.setLocalDeviceSamplingConsent($0, for: device.id) }))
                                    .accessibilityIdentifier("uma.sectorium.local-sampling-consent")
                            }
                            HStack(spacing: 32) {
                                metric(text("Whole-drive read", "整盘读取"), model.workbench.io.readBytesPerSecond)
                                metric(text("Whole-drive write", "整盘写入"), model.workbench.io.writtenBytesPerSecond)
                            }
                            Text(text("Activity reflects this physical drive, not an individual volume. Unavailable readings remain unknown.",
                                      "活动数值属于整块物理硬盘，不代表某个开发卷；无法读取时保留未知。"))
                        }
                    } else {
                        Text(text("This drive is not currently observed.", "当前未观察到此硬盘。"))
                    }
                }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(group.isExternal ? 0.025 : 0.012), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    /// Existing volumes are real observed storage even before AUV has a local
    /// management registration. Never represent an empty registry as an empty disk.
    private func legacyVolumeRow(_ legacy: HESectoriumService.LegacyDevelopmentDisplay,
                                 parentID: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(legacy.name).font(.body.weight(.semibold))
                Spacer()
                if legacy.state != .unknown {
                    Text(legacy.state == .mounted ? text("Loaded", "已加载") : text("Not Loaded", "未加载"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(legacy.state == .mounted ? Color.green : Color.secondary)
                        .accessibilityIdentifier("uma.sectorium.legacy-state.\(parentID)")
                }
            }
            if legacy.logicalCapacityBytes != nil {
                Text(logicalCapacityDescription(legacy.logicalCapacityBytes))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(legacy.state == .unknown
                ? text("This existing volume is known, but its current loading state could not be verified. Refresh before managing it.",
                       "已发现此已有开发卷，但当前加载状态尚无法核实。请刷新后再管理。")
                : text("Existing development volume. Register it with AUV to manage loading and safe removal; its files stay in place.",
                       "这是已有开发卷。登记到 AUV 后即可管理加载与安全退出；现有文件保持原位。"))
                .font(.callout).foregroundStyle(.secondary)
            Button(legacy.state == .unknown ? text("Recheck", "重新检查") : text("Register existing volume", "登记已有开发卷")) {
                if legacy.state == .unknown { model.refresh() }
                else {
                    adoptionDeviceID = parentID
                    showingLegacyAdoptionConfirmation = true
                }
            }
            .disabled(model.isBusy || model.workbench.pendingOperation != nil)
            .accessibilityIdentifier("uma.sectorium.legacy-register.\(parentID)")
            if let mountPoint = legacy.mountPoint {
                DisclosureGroup(text("Volume details", "开发卷详情")) {
                    Text(mountPoint).font(.caption).textSelection(.enabled)
                }.font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("uma.sectorium.legacy-volume.\(parentID)")
    }

    private func volumeRow(_ row: SectoriumVolumeRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill").foregroundStyle(.secondary)
                Text(row.profile.name).font(.system(size: 16, weight: .semibold))
                Spacer()
                if let loaded = row.verifiedLoaded {
                    SectoriumStatusPill(title: !row.parentConnected && !loaded ? text("Disconnected", "已断开")
                        : loaded ? text("Loaded", "已加载") : text("Unloaded", "已卸载"), active: loaded)
                        .accessibilityIdentifier("uma.sectorium.volume-state.\(row.id)")
                }
            }
            Text("\(logicalCapacityDescription(row.profile.logicalCapacityBytes)) · \(filesystemDescription(row.profile))")
                .font(.callout).foregroundStyle(.secondary)
            if !model.registryUnavailable && !row.message(isChinese: isChinese).isEmpty {
                Text(row.message(isChinese: isChinese)).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("uma.sectorium.volume-message.\(row.id)")
            }
            HStack(spacing: 10) {
                if row.parentConnected || row.verifiedLoaded == nil {
                    SectoriumWorkbenchButton(title: primaryTitle(for: row),
                    identifier: "uma.sectorium.volume-primary.\(row.id)",
                    isEnabled: primaryEnabled(for: row), prominent: row.verifiedLoaded == false,
                    action: { performPrimary(for: row) })
                    .frame(width: isChinese ? 116 : 100, height: 32)
                        .help(text("Load and Unload affect this development volume only.", "加载和卸载仅作用于此开发卷。"))
                }
                if let enabled = actionPlan(for: row).disconnectEnabled {
                    SectoriumWorkbenchButton(title: text("Disconnect", "安全断开硬盘"),
                        identifier: "uma.sectorium.volume-disconnect.\(row.id)", isEnabled: enabled, prominent: true,
                        action: { model.prepareSafeUnloadAndEject(profileID: row.id) })
                        .frame(width: isChinese ? 136 : 118, height: 32)
                        .help(text("Unload all volumes and safely eject the entire external drive.", "卸载所有相关卷并安全弹出整个外接硬盘。"))
                }
                Menu {
                    Button(text("Volume settings", "开发卷设置")) { prepareVolumeSettings(for: row) }
                        .disabled(model.registryUnavailable)
                    Button(text("Open IMPORTANT.md history", "打开 IMPORTANT.md 历史")) {
                        openHistory(for: row.id)
                    }
                    .disabled(model.registryUnavailable || !row.parentConnected || model.documentReadsInProgress.contains(row.id))
                    if row.documentationPending {
                        Button(text("Retry document sync", "重试文档同步")) { model.retryDocumentation(profileID: row.id) }
                            .disabled(model.isBusy || model.registryUnavailable || !row.parentConnected)
                    }
                    Button(text("Refresh status", "刷新状态")) { model.refresh() }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 28)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel(text("More options for \(row.profile.name)", "\(row.profile.name) 的更多选项"))
                .accessibilityIdentifier("uma.sectorium.volume-more.\(row.id)")
                Spacer(minLength: 0)
            }
            if row.verifiedLoaded == true && row.parentConnected {
                Text(row.isExternal
                    ? text("Unload keeps the drive connected. Disconnect ejects the entire drive.",
                           "卸载仅关闭开发卷；安全断开会弹出整个硬盘。")
                    : text("Unload closes this development volume. Your internal drive stays connected.",
                           "卸载仅关闭此开发卷，内置硬盘保持连接。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: Binding(
                get: { expandedVolumeDetails.contains(row.id) },
                set: { isExpanded in
                    if isExpanded { expandedVolumeDetails.insert(row.id) }
                    else { expandedVolumeDetails.remove(row.id) }
                })) {
                Text(text("Image: \(row.profile.imagePath)", "镜像：\(row.profile.imagePath)"))
                Text(text("Mount location: \(row.profile.devMountPoint)", "挂载位置：\(row.profile.devMountPoint)"))
                if row.documentationPending {
                    Text(text("History document sync is pending. This does not change the volume’s loading state.",
                              "历史文档尚待同步，不影响开发卷的加载状态。"))
                        .accessibilityIdentifier("uma.sectorium.document-pending.\(row.id)")
                }
                if !row.parentConnected {
                    Text(text("Connect the parent drive to open its history document.", "连接母盘后可打开历史文档。"))
                }
            } label: {
                Text(text("History and diagnostics", "历史与诊断"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("uma.sectorium.volume.\(row.id)")
    }

    private func filesystemDescription(_ profile: SectoriumDevelopmentProfile) -> String {
        switch profile.filesystem {
        case .apfs: text("APFS", "APFS")
        case .apfsCaseSensitive: text("APFS (case-sensitive)", "APFS（区分大小写）")
        case nil: text("Filesystem not verified", "文件系统未核实")
        }
    }

    private func primaryTitle(for row: SectoriumVolumeRow) -> String {
        switch actionPlan(for: row).action {
        case .safelyUnloadAndEject: text("Disconnect", "安全断开硬盘")
        case .unloadOnly: text("Unload", "卸载开发卷")
        case .load: text("Load", "加载")
        case .recheck: text("Recheck", "重新检查")
        }
    }

    private func primaryEnabled(for row: SectoriumVolumeRow) -> Bool {
        actionPlan(for: row).enabled
    }

    private func actionPlan(for row: SectoriumVolumeRow) -> SectoriumVolumeActionPlan {
        .make(verifiedLoaded: row.verifiedLoaded, isExternal: row.isExternal,
              canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
              canSafeUnloadAndEject: row.canSafeUnloadAndEject,
              busy: model.isBusy || row.isBusy)
    }

    private func performPrimary(for row: SectoriumVolumeRow) {
        let plan = actionPlan(for: row)
        guard plan.enabled else { return }
        switch plan.action {
        case .safelyUnloadAndEject: model.prepareSafeUnloadAndEject(profileID: row.id)
        case .unloadOnly: model.prepareUnloadOnlyConfirmation(profileID: row.id)
        case .load:
            if row.profile.encrypted == true {
                unlockProfileID = row.id
                showingUnlock = true
            } else { model.loadDevelopmentDisk(profileID: row.id) }
        case .recheck: model.refresh()
        }
    }

    private func prepareCreation(on deviceID: String? = nil) {
        creationDeviceID = deviceID ?? creatableDevices.first?.id ?? ""
        creationFilesystemID = (model.creationFilesystems.first ?? .apfs).rawValue
        creationAutoLoad = true
        creationMountPoint = ""
        showingCreationOptions = false
        encrypted = false
        password = ""
        showingCreate = true
    }

    private func prepareVolumeSettings(for row: SectoriumVolumeRow) {
        settingsProfileID = row.id
        editDisplayName = row.profile.name
        editMountPoint = row.profile.devMountPoint
        editAutoLoad = row.profile.autoLoad
        editCapacityGiB = Int((row.profile.logicalCapacityBytes ?? 107_374_182_400) / 1_073_741_824)
        showingVolumeSettings = true
        model.refreshVolumeSettings(profileID: row.id)
    }

    private func openHistory(for profileID: String) {
        Task { @MainActor in
            if let document = await model.verifiedHistoryDocument(profileID: profileID) {
                NSWorkspace.shared.open(document)
            }
        }
    }

    private func restoreSettingsFocus() {
        // SwiftUI calls onDismiss while AppKit may still be completing the sheet teardown.
        // One main-queue turn lets the original owner regain its key-view route.
        guard let window = settingsButtonRef.ownerWindow else { return }
        DispatchQueue.main.async {
            guard window.attachedSheet == nil, let content = window.contentView,
                  let button = Self.settingsButton(in: content),
                  button.window === window, button.canBecomeKeyView else { return }
            window.makeKeyAndOrderFront(nil)
            guard window.makeFirstResponder(button) else { return }
            DispatchQueue.main.async {
                // SwiftUI can replace the responder during its final update. Retry only
                // for this same attached control and still-detached owner window.
                if window.firstResponder !== button, window.attachedSheet == nil,
                   button.window === window, button.canBecomeKeyView {
                    _ = window.makeFirstResponder(button)
                }
            }
        }
    }
    private static func settingsButton(in view: NSView) -> NSButton? {
        if view.accessibilityIdentifier() == "uma.sectorium.settings", let button = view as? NSButton {
            return button
        }
        for child in view.subviews {
            if let button = settingsButton(in: child) { return button }
        }
        return nil
    }
    private var inventoryMessage: String {
        switch model.inventoryState {
        case .loading: text("Loading drive inventory…", "正在读取硬盘清单…")
        case .empty: text("No physical drives were reported. Refresh after reconnecting the drive.", "系统未报告物理硬盘。重新连接后请刷新。")
        case .unavailable: text("Drive inventory is unavailable. Check disk access, then refresh.", "无法读取硬盘清单。请检查磁盘访问后刷新。")
        case .malformed: text("Drive metadata could not be parsed. Refresh or check system diagnostics.", "无法解析硬盘资料。请刷新或检查系统诊断。")
        case .available: text("Choose a drive to continue.", "请选择硬盘以继续。")
        }
    }
    private var physicalDevices: [SectoriumPhysicalDevice] {
        SectoriumWorkbenchDeviceOrdering.externalFirst(model.workbench.devices.filter { $0.isVirtual == false })
    }
    private var unassignedDevices: [SectoriumPhysicalDevice] {
        model.workbench.devices.filter { $0.isVirtual == nil || $0.hasAmbiguousPhysicalStores }
    }
    private var selectedDevice: SectoriumPhysicalDevice? {
        physicalDevices.first { $0.id == model.workbench.selectedDeviceID }
    }
    private var selectedLegacy: HESectoriumService.LegacyDevelopmentDisplay? {
        selectedDevice.flatMap { model.legacyDevelopmentByDevice[$0.id] }
    }
    private var presentationLegacy: HESectoriumService.LegacyDevelopmentDisplay? {
        guard presentationLegacyState == .mounted || presentationLegacyState == .detached else { return nil }
        return selectedLegacy
    }
    private var presentationLegacyState: SectoriumWorkbenchActionPlan.LegacyState {
        let observed: SectoriumWorkbenchActionPlan.LegacyState
        switch selectedLegacy?.state {
        case .mounted: observed = .mounted
        case .unmounted: observed = .detached
        case .unknown: observed = .unknown
        case nil: observed = .none
        }
        return SectoriumLegacyPresentationPolicy.currentLegacyState(
            inventoryAvailable: model.inventoryState == .available,
            busy: model.isBusy,
            pending: model.workbench.pendingOperation != nil || model.snapshot.pendingEject == true,
            stale: staleAttachment,
            identityVerified: selectedDevice?.identityVerified == true,
            readiness: model.workbench.readiness,
            observed: observed)
    }
    private func apfsContainerDescription(_ detail: SectoriumAPFSContainerDetail) -> String {
        let role: String
        switch detail.partitionContent {
        case "Apple_APFS_ISC": role = text("system support", "系统支持")
        case "Apple_APFS_Recovery": role = text("recovery", "恢复")
        default: role = text("system and data", "系统与数据")
        }
        return text("APFS container", "APFS 容器") + " " + detail.bsdName + " · " + role
    }
    private func identityDescription(_ device: SectoriumPhysicalDevice) -> String {
        switch device.identityBasis {
        case .wholeMediaUUID:
            return text("Whole media identity verified", "已核实整盘身份")
        case .uniqueBackingVolumeUUID:
            return text("Identity bound to one verified backing volume; whole-drive I/O is unavailable without a media identity.",
                        "身份绑定至一个已核实的后备卷；缺少介质身份时整盘 I/O 不可用。")
        case .unavailable:
            return text("A stable physical identity or unique backing volume is unavailable. Storage actions remain disabled.",
                        "缺少稳定的物理身份或唯一后备卷；存储操作保持禁用。")
        }
    }
    private var staleAttachment: Bool {
        if case .unknown(let detail) = model.workbench.readiness {
            return detail == "Drive attachment or topology changed; reselect the physical drive before management"
        }
        return false
    }
    private var selectedProfile: SectoriumDevelopmentProfile? {
        model.workbench.profiles.first { $0.id == model.workbench.selectedProfileID }
    }
    private var selectedDeviceProfiles: [SectoriumDevelopmentProfile] {
        model.workbench.profiles.filter { $0.deviceID == model.workbench.selectedDeviceID }
    }
    var readinessTitle: String {
        if model.isBusy { return text("Busy", "忙碌") }
        if model.workbench.pendingOperation != nil || model.snapshot.pendingEject == true {
            return text("In progress", "操作中")
        }
        if model.workbench.safeToUnplug { return text("Safe to unplug", "可以拔出硬盘") }
        if model.inventoryState != .available {
            switch model.inventoryState {
            case .loading: return text("Loading drives", "正在读取硬盘")
            case .empty, .unavailable, .malformed: return text("Drive inventory unavailable", "硬盘清单不可用")
            case .available: break
            }
        }
        switch model.workbench.readiness {
        case .busy: return text("Busy", "忙碌")
        case .operationInProgress: return text("In progress", "操作中")
        case .partialFailure: return text("Partially completed", "部分完成")
        case .unknown: return text("Unknown", "未知")
        case .ejected: return text("Drive disconnected", "硬盘已断开连接")
        case .awaitingUnlock: return text("Unlock required", "需要解锁")
        case .noDevice: return text("Choose a drive", "请选择硬盘")
        case .readOnly: return text("Read-only", "只读")
        default: break
        }
        if presentationLegacy?.state == .mounted {
            return text("Loaded, not yet managed", "已装载，尚未接纳管理")
        }
        return switch model.workbench.readiness {
        case .noDevice: text("Choose a drive", "请选择硬盘")
        case .connected: text("Drive connected", "硬盘已连接")
        case .noDevelopmentDisk: text("No development disk", "没有开发盘")
        case .notStarted: text("Unloaded", "未装载")
        case .awaitingUnlock: text("Unlock required", "需要解锁")
        case .ready: text("Ready", "已就绪")
        case .readOnly: text("Read-only", "只读")
        case .busy: text("Busy", "忙碌")
        case .operationInProgress: text("In progress", "操作中")
        case .partialFailure: text("Partially completed", "部分完成")
        case .ejected: text("Drive disconnected", "硬盘已断开连接")
        case .unknown: text("Unknown", "未知")
        }
    }
    var readinessSummary: String {
        if model.isBusy || model.workbench.pendingOperation != nil || model.snapshot.pendingEject == true {
            return text("A storage operation needs attention. Keep the selected drive connected and review its result.",
                        "存储操作仍待处理。请保持所选硬盘连接并查看结果。")
        }
        if model.workbench.safeToUnplug {
            return text("The selected physical drive was verified absent after safe eject.",
                        "安全弹出后已核实所选物理硬盘不再出现。")
        }
        if model.inventoryState != .available { return inventoryMessage }
        switch model.workbench.readiness {
        case .operationInProgress:
            return text("A storage operation needs attention. Review the details.", "存储操作待处理，请查看详情。")
        case .partialFailure:
            return text("The operation stopped before completion. Keep the drive connected.", "操作未能完成，请保持硬盘连接。")
        case .unknown:
            return text("Storage state could not be verified. Review the details.", "暂时无法验证存储状态，请查看详情。")
        case .noDevice, .awaitingUnlock, .readOnly, .ejected:
            return readinessDetail
        default: break
        }
        if presentationLegacy?.state == .mounted, let legacy = presentationLegacy, let device = selectedDevice {
            return text("\(legacy.name) is mounted on \(physicalTitle(device)). Adopt it to manage this development disk.",
                        "\(legacy.name) 已挂载在 \(physicalTitle(device)) 上。接纳后即可管理此开发盘。")
        }
        if presentationLegacy?.state == .unmounted, let legacy = presentationLegacy, let device = selectedDevice {
            return text("\(legacy.name) is detached from \(physicalTitle(device)). Adopt it before managing it.",
                        "\(legacy.name) 已从 \(physicalTitle(device)) 分离。接纳后即可管理。")
        }
        return readinessDetail
    }
    private var readinessTechnicalDetail: String? {
        switch model.workbench.readiness {
        case .operationInProgress(let detail), .partialFailure(let detail), .unknown(let detail): detail
        default: nil
        }
    }
    private var readinessDetail: String {
        switch model.workbench.readiness {
        case .operationInProgress, .partialFailure, .unknown: ""
        case .noDevice: text("Select a physical drive to continue.", "请选择物理硬盘以继续。")
        case .connected: text("A physical drive is selected.", "已选择物理硬盘。")
        case .noDevelopmentDisk: text("This drive has no registered development disk.", "此硬盘尚无已登记的开发盘。")
        case .notStarted: text("The development image is not mounted.", "开发镜像当前未挂载。")
        case .awaitingUnlock: text("Unlock the image to load the development volume.", "解锁镜像后即可装载开发卷。")
        case .ready: text("The validated APFS development volume is available.", "已验证的 APFS 开发卷可用。")
        case .readOnly: text("The mounted volume is read-only.", "已挂载卷为只读。")
        case .busy: text("The storage system reported an active use.", "存储系统报告该卷正在使用。")
        case .ejected: text("The selected drive is no longer observed. Safe eject has not been confirmed.",
                            "已无法观察到所选硬盘；尚未确认安全弹出。")
        }
    }
    private var readinessSymbol: String {
        switch model.workbench.readiness {
        case .ready: "checkmark.circle.fill"
        case .partialFailure, .readOnly, .busy: "exclamationmark.triangle"
        case .ejected: "eject.fill"
        case .unknown, .noDevice: "questionmark.circle"
        default: "externaldrive"
        }
    }

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectoriumSheetHeader(title: text("Create development volume", "创建开发卷"),
                subtitle: text("A separate space for your development work.", "为开发工作准备独立空间。"), symbol: "plus.circle")
            Divider()
            Picker(text("Parent drive", "母盘"), selection: $creationDeviceID) {
                ForEach(creatableDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .accessibilityIdentifier("uma.sectorium.create.parent")
            LabeledContent(text("Volume name", "开发卷名称")) {
                TextField(text("Volume name", "开发卷名称"), text: $profileName)
                    .accessibilityIdentifier("uma.sectorium.create.name")
            }
            LabeledContent(text("Capacity", "容量")) {
                HStack(spacing: 6) {
                    TextField("100", value: $capacityGiB, format: .number).frame(width: 90)
                        .accessibilityIdentifier("uma.sectorium.create.capacity")
                    Text("GiB").foregroundStyle(.secondary)
                }
            }
            Picker(text("Filesystem", "文件系统"), selection: $creationFilesystemID) {
                ForEach(model.creationFilesystems, id: \.rawValue) { filesystem in
                    Text(filesystem == .apfs ? "APFS" : text("APFS (case-sensitive)", "APFS（区分大小写）"))
                        .tag(filesystem.rawValue)
                }
            }
            .accessibilityIdentifier("uma.sectorium.create.filesystem")
            Text(text("Creates a file-backed volume on the selected writable drive. Existing drive contents are preserved; logical capacity is not reserved space.",
                      "将在所选可写硬盘内创建文件型开发卷，保留现有内容；逻辑容量不代表预留同等空间。"))
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $showingCreationOptions) {
                Toggle(text("Load automatically when this drive connects", "连接硬盘后自动加载"),
                       isOn: $creationAutoLoad)
                TextField(text("Mount location (automatic by default)", "挂载位置（默认自动选择）"),
                          text: $creationMountPoint)
                    .accessibilityIdentifier("uma.sectorium.create.mount-location")
                Toggle(text("Encrypt this volume", "加密此开发卷"), isOn: $encrypted)
                if encrypted {
                    SecureField(text("Password (not saved)", "密码（不会保存）"), text: $password)
                        .accessibilityIdentifier("uma.sectorium.create.password")
                }
            } label: {
                Text(text("Options", "其他选项"))
            }
            .padding(.vertical, 6)
            Divider()
            HStack {
                Spacer()
                Button(text("Cancel", "取消")) { showingCreate = false; password = "" }
                    .keyboardShortcut(.cancelAction)
                Button(text("Create volume", "创建开发卷"), action: createDevelopmentDisk)
                    .disabled(model.isBusy || model.registryUnavailable || creationDeviceID.isEmpty || model.creationFilesystems.isEmpty || !isValidProfileName(profileName)
                        || !SectoriumCapacityInput.isValid(capacityGiB) || (encrypted && password.isEmpty)
                        || (!creationMountPoint.isEmpty && !creationMountPoint.hasPrefix("/")))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("uma.sectorium.create.confirm")
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(28)
        .frame(width: 500)
    }

    @ViewBuilder private var volumeSettingsSheet: some View {
        if let row = model.volumeRows.first(where: { $0.id == settingsProfileID }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectoriumSheetHeader(title: text("Volume settings", "开发卷设置"),
                        subtitle: row.profile.name + " · " + row.parentName, symbol: "slider.horizontal.3")
                    Spacer()
                    Button(text("Done", "完成")) { showingVolumeSettings = false }
                        .keyboardShortcut(.cancelAction)
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                    SectoriumPreferenceSection(title: text("Name", "名称")) {
                        HStack {
                            TextField(text("Display name", "显示名称"), text: $editDisplayName)
                                .accessibilityIdentifier("uma.sectorium.settings.name")
                            Button(text("Save name", "保存名称")) {
                                model.updateDevelopmentDisk(profileID: row.id,
                                    change: .displayName(editDisplayName))
                            }
                            .disabled(model.isBusy || model.registryUnavailable || !isValidProfileName(editDisplayName)
                                || editDisplayName == row.profile.name)
                        }
                    }
                    SectoriumPreferenceSection(title: text("Automatic loading", "自动加载")) {
                        Toggle(text("Load when this drive connects", "连接硬盘后加载"), isOn: $editAutoLoad)
                            .accessibilityIdentifier("uma.sectorium.settings.autoload")
                        Button(text("Save automatic loading", "保存自动加载设置")) {
                            model.updateDevelopmentDisk(profileID: row.id,
                                change: .autoLoad(editAutoLoad))
                        }
                        .disabled(model.isBusy || model.registryUnavailable || editAutoLoad == row.profile.autoLoad)
                    }
                    SectoriumPreferenceSection(title: text("Mount location", "挂载位置")) {
                        TextField(text("Mount location", "挂载位置"), text: $editMountPoint)
                            .accessibilityIdentifier("uma.sectorium.settings.mount-location")
                        Button(text("Change mount location", "更改挂载位置")) {
                            model.updateDevelopmentDisk(profileID: row.id,
                                change: .mountPoint(editMountPoint))
                        }
                        .disabled(model.isBusy || model.registryUnavailable || row.verifiedLoaded != false
                            || !editMountPoint.hasPrefix("/")
                            || editMountPoint == row.profile.devMountPoint)
                        if row.verifiedLoaded != false {
                            Text(text("Unload and verify this volume before changing its mount location.",
                                      "更改挂载位置前，先卸载并核实此开发卷。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectoriumPreferenceSection(title: text("Capacity and filesystem", "容量与文件系统")) {
                        HStack {
                            TextField(text("Logical capacity", "逻辑容量"), value: $editCapacityGiB, format: .number)
                                .accessibilityIdentifier("uma.sectorium.settings.capacity")
                            Text("GiB")
                            Button(text("Increase capacity", "扩大容量")) {
                                model.updateDevelopmentDisk(profileID: row.id, change: .capacityGiB(editCapacityGiB))
                            }
                            .disabled(model.isBusy || model.registryUnavailable || row.verifiedLoaded != false || row.profile.encrypted != false
                                || model.capacityChangeUnavailableReason(for: row) != nil
                                || !SectoriumCapacityInput.isValid(editCapacityGiB)
                                || (SectoriumCapacityInput.requestedBytes(gib: editCapacityGiB) ?? 0) <= (row.profile.logicalCapacityBytes ?? UInt64.max))
                        }
                        Text(text("Unload the volume before increasing its capacity. Shrinking and resizing encrypted volumes are not supported here.",
                                  "先卸载开发卷再扩大容量。此处不支持缩小容量或调整加密卷。"))
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent(text("Filesystem", "文件系统"), value: filesystemDescription(row.profile))
                        Text(text("Changing this filesystem requires recreating the volume and is not offered here. Create a separate volume with the desired format to preserve existing data.",
                                  "更改此文件系统需要重建开发卷，因此此处不提供转换。可另建所需格式的开发卷，保留现有数据。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup(text("History", "历史")) {
                        if row.documentHistory.isEmpty {
                            Text(text("No recorded changes yet.", "暂无已记录的变更。"))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(row.documentHistory.suffix(10).reversed(), id: \.id) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(historyTitle(event))
                                Text(event.occurredAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if row.documentationPending {
                            Text(text("Document sync pending; the volume’s actual loading state is unchanged.",
                                      "文档待同步；开发卷的实际加载状态未改变。"))
                                .foregroundStyle(.secondary)
                            Button(text("Retry document sync", "重试文档同步")) { model.retryDocumentation(profileID: row.id) }
                                .disabled(model.isBusy || model.registryUnavailable || !row.parentConnected)
                        }
                        Button(text("Open IMPORTANT.md", "打开 IMPORTANT.md")) { openHistory(for: row.id) }
                            .disabled(model.registryUnavailable || !row.parentConnected || model.documentReadsInProgress.contains(row.id))
                    }
                    DisclosureGroup(text("Technical details", "技术详情")) {
                        Text(row.profile.imagePath).font(.caption).textSelection(.enabled)
                        Text(row.profile.devMountPoint).font(.caption).textSelection(.enabled)
                        if let reason = model.capacityChangeUnavailableReason(for: row) { Text(reason).font(.caption).textSelection(.enabled) }
                    }
                    }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
                .textFieldStyle(.roundedBorder)
                if let notice = model.userNotice {
                    Text(notice.text(isChinese: isChinese)).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("uma.sectorium.settings.result")
                }
            }
            .padding(28)
            .frame(width: 540, height: 610)
            .accessibilityIdentifier("uma.sectorium.volume-settings")
        } else {
            VStack(spacing: 12) {
                Text(text("This volume is no longer available. Refresh before editing.",
                          "此开发卷已不可用。请刷新后再修改。"))
                Button(text("Close", "关闭")) { showingVolumeSettings = false }
            }
            .padding(20)
        }
    }

    private var unlockSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectoriumSheetHeader(title: text("Unlock development volume", "解锁开发卷"),
                subtitle: text("Your password stays on this Mac.", "密码仅用于本机解锁。"), symbol: "lock.open")
            Divider()
            Text(text("Enter this volume’s password. It is used only to unlock the volume and is not saved by AUV.",
                      "输入此开发卷的密码，仅用于本次解锁，AUV 不会保存。"))
                .font(.callout).foregroundStyle(.secondary)
            SecureField(text("Password", "密码"), text: $unlockPassword)
                .accessibilityIdentifier("uma.sectorium.unlock.password")
            HStack {
                Spacer()
                Button(text("Cancel", "取消")) { showingUnlock = false; unlockPassword = "" }
                    .keyboardShortcut(.cancelAction)
                Button(text("Unlock and Load", "解锁并装载"), action: unlockAndStart)
                    .disabled(model.isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(28)
        .frame(width: 460)
    }

    private var ejectConfirmationSheet: some View {
        let confirmedDeviceName = model.wholeDeviceEjectConfirmation.flatMap { confirmation in
            model.workbench.devices.first(where: { $0.id == confirmation.physicalIdentity })?.name
        }
        return SectoriumWholeDeviceEjectConfirmationView(model: model, isChinese: isChinese,
            selectedDeviceName: confirmedDeviceName)
    }

    private func unlockAndStart() {
        guard !unlockProfileID.isEmpty else { return }
        model.loadDevelopmentDisk(profileID: unlockProfileID, password: unlockPassword)
        unlockPassword = ""
        unlockProfileID = ""
        showingUnlock = false
    }

    private func createDevelopmentDisk() {
        guard creatableDevices.contains(where: { $0.id == creationDeviceID }),
              isValidProfileName(profileName), SectoriumCapacityInput.isValid(capacityGiB) else { return }
        guard let filesystem = SectoriumFilesystem(rawValue: creationFilesystemID),
              model.creationFilesystems.contains(filesystem) else { return }
        let mount = creationMountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SectoriumCreateRequest(deviceID: creationDeviceID, parentDirectory: nil,
            name: profileName.trimmingCharacters(in: .whitespacesAndNewlines), capacityGiB: capacityGiB,
            filesystem: filesystem, autoLoad: creationAutoLoad,
            mountPoint: mount.isEmpty ? nil : mount, password: encrypted ? password : nil)
        model.createDevelopmentDisk(request: request)
        showingCreate = false; password = ""
    }

    private func historyTitle(_ event: SectoriumPortableDocumentEvent) -> String {
        let title: String
        switch event.kind {
        case "registered": title = text("Volume registered", "已登记开发卷")
        case "validated": title = text("Volume verified", "已核实开发卷")
        case "loaded": title = text("Volume loaded", "已加载开发卷")
        case "unloaded": title = text("Volume unloaded", "已卸载开发卷")
        case "ejected": title = text("Parent drive disconnected", "母盘已断开")
        case "reconnected": title = text("Parent drive reconnected", "母盘重新连接")
        case "displayNameChanged": title = text("Name changed", "已更改名称")
        case "autoLoadChanged": title = text("Automatic loading changed", "已更改自动加载")
        case "mountPointChanged": title = text("Mount location changed", "已更改挂载位置")
        case "capacityChanged": title = text("Capacity changed", "已更改容量")
        case "filesystemChanged": title = text("Filesystem changed", "已更改文件系统")
        case "creationIntended": title = text("Creation started", "开始创建")
        case "modificationIntended": title = text("Change started", "开始更改")
        case "removed": title = text("Registration removed", "已移除登记")
        case "replaced": title = text("Registration replaced", "已替换登记")
        default: title = text("Volume record updated", "开发卷记录更新")
        }
        return event.phase == .intended ? title + text(" — completion not recorded", " — 尚未记录完成") : title
    }

    private func isValidProfileName(_ name: String) -> Bool {
        SectoriumVolumeNameInput.isValid(name)
    }

    private func showCapacityAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: text("OK", "好"))
        alert.runModal()
    }

    private func adoptExisting() {
        guard let device = selectedDevice else { return }
        adoptExisting(on: device)
    }

    private func adoptExisting(on device: SectoriumPhysicalDevice) {
        guard device.identityVerified, model.inventoryState == .available,
              !model.isBusy else { return }
        let panel = SectoriumExistingImagePicker.makePanel(
            mountedVolumePaths: device.mountedVolumePaths, prompt: text("Register", "登记"))
        guard let url = SectoriumExistingImagePicker.selectedURL(from: panel, response: panel.runModal()) else { return }
        guard model.workbench.devices.contains(where: { $0.id == device.id && $0.identityVerified }),
              model.inventoryState == .available, !model.isBusy else { return }
        model.adoptDevelopmentDisk(deviceID: device.id, imageURL: url)
    }

    private func physicalTitle(_ device: SectoriumPhysicalDevice) -> String {
        let mountedName = device.volumeMembers.first(where: { $0.mounted })?.name
        let title: String
        if let mountedName, !mountedName.isEmpty, mountedName != device.name {
            title = "\(mountedName) · \(device.name)"
        } else {
            title = device.name
        }
        guard !device.isExternal, !title.localizedCaseInsensitiveContains(device.bsdName) else {
            return title
        }
        return "\(title) · \(device.bsdName)"
    }
    private func deviceLabel(_ device: SectoriumPhysicalDevice) -> String {
        let location = device.isExternal ? text("External physical drive", "外接物理硬盘")
            : text("Internal physical drive", "内置物理硬盘")
        let size = device.wholeDeviceBytes.map(formatBytes) ?? text("capacity unknown", "容量未知")
        return "\(location) · \(size) · \(device.bsdName)"
    }
    private func volumeDescription(_ member: SectoriumVolumeMember) -> String {
        let name = member.name ?? member.mountPoint.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? text("Unnamed volume", "未命名卷")
        return name + (member.mountPoint.map { text(" · mounted at ", " · 已挂载于 ") + $0 }
                       ?? text(" · unmounted", " · 未挂载"))
    }
    private func legacyStateDescription(_ legacy: HESectoriumService.LegacyDevelopmentDisplay) -> String {
        switch legacy.state {
        case .mounted:
            return legacy.mountPoint.map { text("mounted at ", "已挂载于 ") + $0 }
                ?? text("mount verification needed", "挂载状态待核实")
        case .unmounted: return text("image detached", "镜像已分离")
        case .unknown: return text("state unverified", "状态未核实")
        }
    }
    private func logicalCapacityDescription(_ bytes: UInt64?) -> String {
        guard let bytes else { return text("logical capacity unknown", "逻辑容量未知") }
        let gib = Double(bytes) / 1_073_741_824
        return String(format: "%.1f GiB", gib) + text(" logical capacity", " 逻辑容量")
    }
    private func metric(_ title: String, _ value: UInt64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { "\(formatBytes($0))/s" } ?? "—").font(.system(.body, design: .monospaced))
        }
    }
    private func formatBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
    private func text(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }
}

struct SectoriumStatusPill: View {
    let title: String
    let active: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(active ? Color.green : Color.secondary).frame(width: 5, height: 5)
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(active ? Color.green : Color.secondary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background((active ? Color.green : Color.secondary).opacity(0.09), in: Capsule())
    }
}

struct SectoriumSheetHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 30, height: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 21, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SectoriumPreferenceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
            Divider().padding(.top, 6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Group only resolved application identities. Unknown tools remain separate by
/// command; an identically named but differently identified app stays distinct.
struct SectoriumBlockingApplicationGroup: Identifiable {
    let id: String
    let name: String
    let processes: [SectoriumActivityProcess]

    static func make(_ processes: [SectoriumActivityProcess]) -> [Self] {
        let grouped = Dictionary(grouping: processes) { process in
            if let bundle = process.bundleIdentifier, !bundle.isEmpty { return "bundle:" + bundle }
            if let name = process.applicationName, !name.isEmpty { return "application:" + name }
            return "command:" + process.command
        }
        return grouped.map { id, values in
            let ordered = values.sorted { $0.processID < $1.processID }
            return Self(id: id, name: ordered.first?.applicationName ?? ordered.first?.command ?? "", processes: ordered)
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
}

struct SectoriumActivityCheckView: View {
    @ObservedObject var model: HESectoriumStore
    let isChinese: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let check = model.safetyCheck {
                SectoriumSheetHeader(title: check.name,
                    subtitle: check.processes.isEmpty ? text("Review before continuing", "继续前确认")
                        : text("Apps are using this drive", "有应用正在使用此硬盘"), symbol: "externaldrive.badge.exclamationmark")
                Divider()
                Text(message(check)).font(.callout).foregroundStyle(.secondary)
                if !check.processes.isEmpty {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(SectoriumBlockingApplicationGroup.make(check.processes)) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label(group.name, systemImage: "app")
                                            .font(.body.weight(.medium))
                                        Spacer()
                                        Text(text("\(group.processes.count) processes", "\(group.processes.count) 个进程"))
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                    DisclosureGroup(text("Process details", "进程详情")) {
                                        ForEach(group.processes, id: \.processID) { process in
                                            HStack(alignment: .top, spacing: 10) {
                                                Text("PID \(process.processID)").monospacedDigit()
                                                Text(process.references.contains { $0.descriptor == "cwd" }
                                                    ? text("Open working folder", "工作目录仍打开")
                                                    : text("Open drive resource", "硬盘资源仍打开"))
                                            }.font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.font(.callout).foregroundStyle(.secondary)
                                    Divider()
                                }.padding(.vertical, 5)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .accessibilityIdentifier("uma.sectorium.blocking-apps")
                }
                if let notice = check.quitNotice {
                    Text(notice.text(isChinese: isChinese)).font(.callout).foregroundStyle(.secondary)
                }
                if check.waiting { ProgressView(text("Waiting for the apps to release the drive…", "正在等待应用释放硬盘…")) }
                if !check.waiting, !check.applications.isEmpty {
                    Button(quitTitle(check)) { model.quitBlockingApplicationsAndRetry() }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("uma.sectorium.quit-blockers-and-retry")
                }
                Divider()
                HStack {
                    Button(text("Cancel", "取消")) { model.cancelSafetyCheck() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if check.canProceed {
                        Button(text("Continue", "继续")) { model.confirmSafeUnload() }
                            .keyboardShortcut(.defaultAction)
                    } else if !check.waiting {
                        Button(text("Recheck", "重新检查")) { model.recheckSafeUnload() }
                            .disabled(model.isBusy)
                        Button(text("Wait", "等待")) { model.waitForSafeUnload() }
                            .disabled(model.isBusy)
                    }
                }
            }
        }
        .padding(28).frame(width: 520)
        .accessibilityIdentifier("uma.sectorium.activity-check")
    }
    private func message(_ check: SectoriumSafetyCheck) -> String {
        switch check.activity {
        case .busy:
            text("These apps or processes still use this drive. An open working folder can prevent unloading even when no data is being written. Quit the listed apps, then retry.",
                 "以下应用或进程仍在使用硬盘。即使没有写入，打开的工作目录也可能阻止卸载。请退出列出的应用后重试。")
        case .incomplete:
            text("Activity could not be fully checked. Keep the drive connected. Cancel or wait for a fresh check; nothing will be forced closed.",
                 "暂时无法完整检查使用情况，请保持硬盘连接。可取消或等待重新检查；不会强制关闭任何程序。")
        case .noVisibleOccupancy:
            text("No visible activity was found. Continue to recheck and unload normally. This check alone does not guarantee that the drive is safe to disconnect.",
                 "未发现可见活动。继续后将再次检查并正常卸载；仅此检查不能证明可以安全拔线。")
        }
    }
    private func quitTitle(_ check: SectoriumSafetyCheck) -> String {
        if check.applications.count == 1, let app = check.applications.first {
            return text("Quit \(app.name) and retry", "退出 \(app.name) 并重试")
        }
        let names = check.applications.map(\.name).joined(separator: isChinese ? "、" : ", ")
        return text("Quit \(names) and retry", "退出 \(names) 并重试")
    }
    private func text(_ en: String, _ zh: String) -> String { isChinese ? zh : en }
}

struct SectoriumWholeDeviceEjectConfirmationView: View {
    @ObservedObject var model: HESectoriumStore
    let isChinese: Bool
    let selectedDeviceName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let confirmation = model.wholeDeviceEjectConfirmation {
                SectoriumSheetHeader(title: confirmation.isObservationOnly ? text("Verify removal", "确认已移除")
                    : text("Disconnect drive", "安全断开硬盘"),
                    subtitle: selectedDeviceName ?? text("External drive", "外接硬盘"), symbol: "eject.circle")
                Divider()
                Text(confirmation.isObservationOnly
                    ? text("Check whether the previously ejected drive is now absent. This does not run another eject.",
                           "确认此前弹出的硬盘现在是否已移除；不会重复执行弹出。")
                    : text("Disconnect unloads all volumes and safely ejects the entire drive. Unload alone keeps the parent drive connected.",
                           "断开操作会卸载所有相关卷并安全弹出整个硬盘；仅卸载开发卷则保留母盘连接。"))
                    .font(.body)
                if !affectedVolumeNames.isEmpty {
                    Text(affectedVolumeNames.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
                if !confirmation.dependenciesCanFinishOffTarget && !confirmation.isObservationOnly {
                    Text(text("AUV is currently using files on this drive to finish the operation. Move its required runtime to the Mac before ejecting.",
                              "AUV 完成操作所需的运行文件仍在此硬盘上。请先将必要运行组件放到 Mac 内置盘，再弹出。"))
                        .foregroundStyle(.orange)
                }
                DisclosureGroup(text("Technical details", "技术详情")) {
                    Text("/dev/\(confirmation.bsdName)")
                    Text(text("\(confirmation.affectedMembers.count) physical volumes, \(confirmation.attachedImageIdentities.count) disk images",
                              "\(confirmation.affectedMembers.count) 个物理卷，\(confirmation.attachedImageIdentities.count) 个磁盘镜像"))
                    ForEach(confirmation.affectedMembers, id: \.self) { Text($0).textSelection(.enabled) }
                }.font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Button(text("Cancel", "取消")) { model.cancelWholeDeviceEjectConfirmation() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(confirmation.isObservationOnly ? text("Check", "核验") : text("Disconnect", "安全断开硬盘")) {
                        model.confirmWholeDeviceEject()
                    }
                    .disabled(model.isBusy || (!confirmation.isObservationOnly && !confirmation.dependenciesCanFinishOffTarget))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("uma.sectorium.eject-confirm")
                }
            } else {
                Text(text("The drive changed. Refresh before trying again.", "硬盘已变化，请刷新后重试。"))
                Button(text("Close", "关闭")) { model.cancelWholeDeviceEjectConfirmation() }
            }
        }
        .padding(28).frame(width: 480)
    }
    private var affectedVolumeNames: [String] {
        guard let id = model.wholeDeviceEjectConfirmation?.physicalIdentity else { return [] }
        let names = model.workbench.devices.first { $0.id == id }?.volumeMembers.compactMap(\.name) ?? []
        return Array(Set(names + model.volumeRows.filter { $0.parentDeviceID == id }.map { $0.profile.name })).sorted()
    }
    private func text(_ en: String, _ zh: String) -> String { isChinese ? zh : en }
}

enum SectoriumExistingImagePicker {
    @MainActor
    static func makePanel(mountedVolumePaths: [String], prompt: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.showsHiddenFiles = true
        if let observedMount = suggestedDirectoryURL(mountedVolumePaths: mountedVolumePaths) {
            panel.directoryURL = observedMount
        }
        return panel
    }

    static func suggestedDirectoryURL(mountedVolumePaths: [String]) -> URL? {
        mountedVolumePaths.first(where: { !$0.isEmpty && $0.hasPrefix("/") })
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @MainActor
    static func selectedURL(from panel: NSOpenPanel, response: NSApplication.ModalResponse) -> URL? {
        guard response == .OK else { return nil }
        return panel.url
    }
}

private final class SectoriumWeakButtonReference: ObservableObject {
    weak var button: NSButton?
    weak var ownerWindow: NSWindow?
}

struct SectoriumWorkbenchButton: NSViewRepresentable {
    let title: String
    let identifier: String
    let isEnabled: Bool
    var controlSize: NSControl.ControlSize = .regular
    var prominent: Bool = false
    let action: () -> Void
    var onReady: ((NSButton) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = SectoriumWorkbenchFocusableButton(title: title, target: context.coordinator,
                                                       action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = .rounded
        button.controlSize = controlSize
        button.bezelColor = prominent ? .controlAccentColor : nil
        button.setWorkbenchEnabled(isEnabled)
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        DispatchQueue.main.async { onReady?(button) }
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.controlSize = controlSize
        button.bezelColor = prominent ? .controlAccentColor : nil
        (button as? SectoriumWorkbenchFocusableButton)?.setWorkbenchEnabled(isEnabled)
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        onReady?(button)
    }

    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate(_ sender: NSButton) { guard sender.isEnabled else { return }; action() }
    }
}

private struct SectoriumWorkbenchConsentControl: NSViewRepresentable {
    let title: String
    let identifier: String
    let isConsented: Bool
    let isEnabled: Bool
    let action: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = SectoriumWorkbenchFocusableButton(title: title, target: context.coordinator,
                                                       action: #selector(Coordinator.activate(_:)))
        button.setButtonType(.switch)
        button.bezelStyle = .regularSquare
        button.setWorkbenchEnabled(isEnabled)
        button.refusesFirstResponder = false
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.state = isConsented ? .on : .off
        (button as? SectoriumWorkbenchFocusableButton)?.setWorkbenchEnabled(isEnabled)
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
    }

    @MainActor final class Coordinator: NSObject {
        var action: (Bool) -> Void
        init(action: @escaping (Bool) -> Void) { self.action = action }
        @objc func activate(_ sender: NSButton) {
            guard sender.isEnabled else { return }
            action(sender.state == .on)
        }
    }
}

private final class SectoriumWorkbenchFocusableButton: NSButton {
    private var workbenchEnabled = true

    override var isEnabled: Bool {
        get { workbenchEnabled && super.isEnabled }
        set { super.isEnabled = workbenchEnabled && newValue }
    }

    func setWorkbenchEnabled(_ enabled: Bool) {
        workbenchEnabled = enabled
        super.isEnabled = enabled
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds.insetBy(dx: -6, dy: -6)) }
        return accepted
    }
}
