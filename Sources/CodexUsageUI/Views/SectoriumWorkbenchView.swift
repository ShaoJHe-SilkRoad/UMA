import AppKit
import HESectoriumRuntime
import SwiftUI

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

public struct SectoriumWorkbenchView: View {
    @StateObject private var model: HESectoriumStore
    private let isChinese: Bool
    @State private var showingSettings = false
    @StateObject private var settingsButtonRef = SectoriumWeakButtonReference()
    @State private var showingCreate = false
    @State private var showingUnlock = false
    @State private var profileName = "Development"
    @State private var capacityGiB = 100
    @State private var caseSensitive = false
    @State private var encrypted = false
    @State private var password = ""
    @State private var unlockPassword = ""
    @State private var knownWritersClosed = false
    @State private var stopKnownWritersClosed = false

    public init(store: HESectoriumStore? = nil, isChinese: Bool = false) {
        _model = StateObject(wrappedValue: store ?? HESectoriumStore())
        self.isChinese = isChinese
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text("Sectorium", "分区工")).font(.largeTitle.weight(.semibold))
                        Text(text("Manage a development disk on a selected physical drive.", "在选定硬盘上管理虚拟开发盘。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SectoriumWorkbenchButton(title: text("Refresh", "刷新"), identifier: "uma.sectorium.refresh",
                                             isEnabled: !model.isBusy) { model.refresh() }
                    SectoriumWorkbenchButton(title: text("Settings", "设置"), identifier: "uma.sectorium.settings",
                                             isEnabled: true, action: {
                                                 settingsButtonRef.ownerWindow = settingsButtonRef.button?.window
                                                 showingSettings = true
                                             }, onReady: {
                                                 settingsButtonRef.button = $0
                                             })
                }

                GroupBox(text("Physical drive", "物理硬盘")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.inventoryState == .loading && !model.workbench.devices.isEmpty {
                            Text(inventoryMessage).foregroundStyle(.secondary)
                        }
                        if physicalDevices.isEmpty {
                            Text(inventoryMessage)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(unassignedDevices) { device in
                            Text(text("Unassigned device", "未归属设备") + " " + device.bsdName
                                 + (device.hasAmbiguousPhysicalStores
                                    ? text(" · multiple APFS physical stores; no mother drive was chosen.",
                                           " · 存在多个 APFS 物理存储，未指定母盘。")
                                    : text(" · physical ownership is unverified; actions are unavailable.",
                                           " · 物理归属未核实，操作不可用。")))
                                .font(.caption).foregroundStyle(.orange)
                                .accessibilityIdentifier("uma.sectorium.unassigned-device")
                        }
                        if !physicalDevices.isEmpty {
                            ForEach(physicalDevices) { device in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label(physicalTitle(device), systemImage: device.isExternal ? "externaldrive" : "internaldrive")
                                            .font(.headline)
                                        Spacer()
                                        SectoriumWorkbenchButton(title: model.workbench.selectedDeviceID == device.id
                                            ? text("Selected", "已选择") : text("Select", "选择"),
                                            identifier: "uma.sectorium.select-drive.\(device.bsdName)",
                                            isEnabled: !model.isBusy && model.inventoryState == .available
                                                && model.workbench.selectedDeviceID != device.id) {
                                                model.selectDevice(device.id)
                                            }
                                    }
                                    Text(deviceLabel(device)).font(.caption).foregroundStyle(.secondary)
                                    if !device.identityVerified {
                                        Text(text("Identity unavailable; actions disabled.", "身份未知；操作不可用。"))
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                    ForEach(device.volumeMembers, id: \.bsdName) { member in
                                        Label(volumeDescription(member), systemImage: "externaldrive.fill.badge.person.crop")
                                            .font(.caption)
                                            .accessibilityIdentifier("uma.sectorium.backing-volume")
                                    }
                                    ForEach(model.workbench.profiles.filter { $0.deviceID == device.id }) { profile in
                                        Label(profile.devVolumeName + " · "
                                              + logicalCapacityDescription(profile.logicalCapacityBytes)
                                              + text(" · registered virtual disk", " · 已登记虚拟盘"),
                                              systemImage: "internaldrive")
                                            .font(.caption)
                                            .accessibilityIdentifier("uma.sectorium.related-development-disk")
                                    }
                                    if let legacy = model.legacyDevelopmentByDevice[device.id] {
                                        Label(legacy.name + " · " + logicalCapacityDescription(legacy.logicalCapacityBytes)
                                              + " · " + legacyStateDescription(legacy)
                                              + text(" · not yet managed", " · 尚未接纳管理"),
                                              systemImage: "internaldrive")
                                            .font(.caption)
                                            .accessibilityIdentifier("uma.sectorium.related-development-disk")
                                        Text(text("Used/free: unknown", "已用/可用：未知"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !device.isExternal && !device.apfsContainers.isEmpty {
                                        DisclosureGroup(text("System and recovery APFS details", "系统与恢复 APFS 详情")) {
                                            ForEach(device.apfsContainers, id: \.bsdName) { container in
                                                Text(apfsContainerDescription(container)).font(.caption)
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityIdentifier("uma.sectorium.physical-drive")
                            }
                            if let device = selectedDevice {
                                Text(identityDescription(device)).font(.caption).foregroundStyle(.secondary)
                                if device.mountedVolumePaths.isEmpty {
                                    Text(text("Connected, but no mounted storage location is available.",
                                              "硬盘已连接，但没有可用的已挂载存储位置。"))
                                        .foregroundStyle(.secondary)
                                }
                                if !device.isExternal {
                                    SectoriumWorkbenchConsentControl(
                                        title: text("Allow I/O sampling for this local disk", "允许采样此本地硬盘 I/O"),
                                        identifier: "uma.sectorium.local-sampling-consent",
                                        isConsented: model.isLocalDeviceSamplingConsented(device.id),
                                        isEnabled: device.identityVerified && model.inventoryState == .available && !model.isBusy
                                    ) { consented in
                                        model.setLocalDeviceSamplingConsent(consented, for: device.id)
                                    }
                                }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                            metric(text("Whole-drive read", "整盘读取"), model.workbench.io.readBytesPerSecond)
                            metric(text("Whole-drive write", "整盘写入"), model.workbench.io.writtenBytesPerSecond)
                            Text(model.workbench.io.isFresh ? text("Live", "实时") : text("Unknown", "未知"))
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("uma.sectorium.io-freshness")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox(text("Development disk", "虚拟开发盘")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if selectedDeviceProfiles.count > 1 {
                            Picker(text("Development disk", "开发盘"), selection: Binding(
                                get: { model.workbench.selectedProfileID ?? "" },
                                set: { model.selectProfile($0.isEmpty ? nil : $0) }
                            )) {
                                Text(text("Choose a development disk", "选择开发盘")).tag("")
                                ForEach(selectedDeviceProfiles) { profile in Text(profile.name).tag(profile.id) }
                            }
                            .accessibilityIdentifier("uma.sectorium.profile-picker")
                            .disabled(model.isBusy)
                        }
                        HStack {
                            Label(readinessTitle, systemImage: readinessSymbol)
                                .font(.headline)
                            Spacer()
                            if let profile = selectedProfile {
                                Text(profile.name).foregroundStyle(.secondary)
                            }
                        }
                        Text(readinessSummary).font(.callout).foregroundStyle(.secondary)
                        if model.discoveredLegacyDisk {
                            Text(text("A configured DEV_APFS belongs to this drive. Verify its current state and adopt explicitly before management.",
                                      "已配置的 DEV_APFS 属于此硬盘。核实当前状态并明确接纳后方可管理。"))
                                .font(.callout).foregroundStyle(.secondary)
                                .accessibilityIdentifier("uma.sectorium.legacy-discovery")
                        }
                        if let technicalDetail = readinessTechnicalDetail {
                            DisclosureGroup(text("Technical details", "技术详情")) {
                                Text(technicalDetail).font(.caption).textSelection(.enabled)
                                    .accessibilityIdentifier("uma.sectorium.readiness-technical-detail")
                            }
                            .accessibilityIdentifier("uma.sectorium.readiness-details")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectoriumWorkbenchButton(title: text("Create development disk", "创建开发盘"),
                                identifier: "uma.sectorium.create", isEnabled: selectedDevice?.identityVerified == true && !staleAttachment && !storageMutationBlocked) {
                                    showingCreate = true
                                }
                            SectoriumWorkbenchButton(title: text("Adopt existing disk", "接纳已有开发盘"),
                                identifier: "uma.sectorium.adopt", isEnabled: selectedDevice?.identityVerified == true && !staleAttachment && !storageMutationBlocked,
                                action: adoptExisting)
                            SectoriumWorkbenchButton(title: text("Start", "启动"), identifier: "uma.sectorium.start",
                                isEnabled: selectedDevice?.identityVerified == true && !staleAttachment && selectedProfile?.hasVerifiedImageFormat == true && !storageMutationBlocked && model.workbench.readiness != .ready,
                                action: startSelectedProfile)
                            SectoriumWorkbenchButton(title: text("Stop", "停止"), identifier: "uma.sectorium.stop",
                                isEnabled: selectedDevice?.identityVerified == true && !staleAttachment && selectedProfile != nil && !storageMutationBlocked && model.workbench.readiness == .ready,
                                action: model.prepareStopDevelopmentDiskConfirmation)
                            SectoriumWorkbenchButton(title: text("Resume operation", "继续未完成操作"),
                                identifier: "uma.sectorium.resume",
                                isEnabled: model.workbench.pendingOperation.map { !$0.hasPrefix("eject:") } == true
                                    && model.inventoryState == .available && !model.isBusy,
                                action: model.resumePendingOperation)
                            if model.snapshot.pendingEject == true || model.workbench.pendingOperation?.hasPrefix("eject:") == true {
                                SectoriumWorkbenchButton(title: text("Continue eject", "继续弹出"),
                                    identifier: "uma.sectorium.continue-eject",
                                    isEnabled: model.canContinueWholeDeviceEject && model.inventoryState == .available && !model.isBusy,
                                    action: model.prepareContinueWholeDeviceEjectConfirmation)
                                SectoriumWorkbenchButton(title: text("Return to development", "返回开发环境"),
                                    identifier: "uma.sectorium.return-to-development",
                                    isEnabled: model.canReturnFromWholeDeviceEject && model.inventoryState == .available && !model.isBusy,
                                    action: model.returnToDevelopment)
                            }
                            SectoriumWorkbenchButton(title: text("Eject external drive", "弹出整块外接硬盘"),
                                identifier: "uma.sectorium.eject-drive",
                                isEnabled: model.canBeginWholeDeviceEject && selectedDevice?.isExternal == true
                                    && selectedDevice?.identityVerified == true && !staleAttachment && !storageMutationBlocked && !model.isBusy,
                                action: model.prepareWholeDeviceEjectConfirmation)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if model.workbench.safeToUnplug {
                                Label(text("Safe to unplug", "可以拔出硬盘"), systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityIdentifier("uma.sectorium.safe-to-unplug")
                            } else if selectedDevice?.isExternal == true {
                                Text(text("Do not unplug until eject is verified.", "未验证弹出完成前请勿拔线。"))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(text("Local drives can stop the virtual disk, but cannot be ejected here.", "本地硬盘可停止虚拟盘，但不能在此整盘弹出。"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !model.lastResult.isEmpty {
                    GroupBox(text("Latest operation", "最近操作")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(operationSummary).accessibilityIdentifier("uma.sectorium.operation-summary")
                            DisclosureGroup(text("Operation details", "操作详情")) {
                                Text(model.lastResult).font(.caption).textSelection(.enabled)
                                ForEach(Array(model.workbench.operationSteps.enumerated()), id: \.offset) { _, step in
                                    HStack {
                                        Image(systemName: step.status == .succeeded ? "checkmark.circle" : step.status == .failed ? "xmark.circle" : "minus.circle")
                                        Text(step.step)
                                        Spacer()
                                        Text(step.detail).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    .font(.caption)
                                }
                            }
                            .accessibilityIdentifier("uma.sectorium.operation-details")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(22)
        }
        .frame(minWidth: 360, minHeight: 470)
        .accessibilityIdentifier("uma.sectorium.workbench")
        .onAppear { model.activateWorkbench() }
        .onDisappear { model.deactivateWorkbench() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            model.pauseSamplingForSleep()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.resumeSamplingAfterWake()
        }
        .sheet(isPresented: $showingCreate) { createSheet }
        .sheet(isPresented: $showingUnlock) { unlockSheet }
        .sheet(isPresented: $showingSettings, onDismiss: restoreSettingsFocus) {
            HESectoriumSettingsView(isChinese: isChinese, store: model) {
                showingSettings = false
            }
        }
        .sheet(isPresented: Binding(get: { model.wholeDeviceEjectConfirmation != nil }, set: { if !$0 { model.cancelWholeDeviceEjectConfirmation() } })) {
            ejectConfirmationSheet
        }
        .sheet(isPresented: Binding(get: { model.stopConfirmation != nil }, set: { if !$0 { model.cancelStopConfirmation() } })) {
            stopConfirmationSheet
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
        model.workbench.devices.filter { $0.isVirtual == false }
    }
    private var unassignedDevices: [SectoriumPhysicalDevice] {
        model.workbench.devices.filter { $0.isVirtual == nil || $0.hasAmbiguousPhysicalStores }
    }
    private var selectedDevice: SectoriumPhysicalDevice? {
        physicalDevices.first { $0.id == model.workbench.selectedDeviceID }
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
    private var storageMutationBlocked: Bool {
        model.isBusy || model.inventoryState != .available || model.workbench.pendingOperation != nil
    }
    private var selectedProfile: SectoriumDevelopmentProfile? {
        model.workbench.profiles.first { $0.id == model.workbench.selectedProfileID }
    }
    private var selectedDeviceProfiles: [SectoriumDevelopmentProfile] {
        model.workbench.profiles.filter { $0.deviceID == model.workbench.selectedDeviceID }
    }
    private var readinessTitle: String {
        switch model.workbench.readiness {
        case .noDevice: text("Choose a drive", "请选择硬盘")
        case .connected: text("Connected", "已连接")
        case .noDevelopmentDisk: text("No development disk", "没有开发盘")
        case .notStarted: text("Not started", "未启动")
        case .awaitingUnlock: text("Unlock required", "需要解锁")
        case .ready: text("Ready", "已就绪")
        case .readOnly: text("Read-only", "只读")
        case .busy: text("Busy", "忙碌")
        case .operationInProgress: text("In progress", "操作中")
        case .partialFailure: text("Partially completed", "部分完成")
        case .ejected: text("Ejected", "已弹出")
        case .unknown: text("Unknown", "未知")
        }
    }
    private var readinessSummary: String {
        switch model.workbench.readiness {
        case .operationInProgress: text("A storage operation needs attention. Review the details.", "存储操作待处理，请查看详情。")
        case .partialFailure: text("The operation stopped before completion. Keep the drive connected.", "操作未能完成，请保持硬盘连接。")
        case .unknown: text("Storage state could not be verified. Review the details.", "暂时无法验证存储状态，请查看详情。")
        default: readinessDetail
        }
    }
    private var operationSummary: String {
        let completed = model.workbench.operationSteps.filter { $0.status == .succeeded }.count
        switch model.workbench.readiness {
        case .partialFailure:
            return text("Stopped after \(completed) confirmed step(s). Remaining work is unverified; keep the drive connected.",
                        "已确认完成 \(completed) 个步骤后停止。其余操作尚未验证；请保持硬盘连接。")
        case .operationInProgress:
            return text("\(completed) step(s) are confirmed. The operation still needs attention; keep the drive connected.",
                        "已确认完成 \(completed) 个步骤。操作仍待处理；请保持硬盘连接。")
        case .unknown:
            return text("The result could not be verified. Keep the drive connected and review the details.",
                        "操作结果尚无法验证。请保持硬盘连接并查看详情。")
        default:
            return model.lastResult == "Completed"
                ? text("Operation completed.", "操作已完成。")
                : text("The operation did not complete. Review the details before continuing.", "操作未完成。继续前请查看详情。")
        }
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
        case .connected:
            model.discoveredLegacyDisk
                ? text("The existing DEV_APFS is mounted and verified on this drive. Adopt it explicitly before management.",
                       "现有 DEV_APFS 已挂载并核实属于此硬盘。明确接纳后方可管理。")
                : text("A drive is selected. Create or adopt a development disk.", "已选择硬盘。可以创建或接纳开发盘。")
        case .noDevelopmentDisk: text("This drive has no registered development disk.", "此硬盘尚无已登记的开发盘。")
        case .notStarted:
            model.discoveredLegacyDisk
                ? text("The configured image is detached. Adopt it explicitly before management.",
                       "已配置的镜像已分离。明确接纳后方可管理。")
                : text("The image is known and is not mounted.", "已识别镜像，但当前未挂载。")
        case .awaitingUnlock: text("Unlock the image explicitly to start it.", "请明确解锁镜像后启动。")
        case .ready: text("The validated APFS development volume is available.", "已验证的 APFS 开发卷可用。")
        case .readOnly: text("The mounted volume is read-only.", "已挂载卷为只读。")
        case .busy: text("The storage system reported an active use.", "存储系统报告该卷正在使用。")
        case .ejected: text("The selected external device is no longer mounted.", "所选外接硬盘已卸载。")
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
            Text(text("Create development disk", "创建开发盘")).font(.title2.weight(.semibold))
            TextField(text("Name", "名称"), text: $profileName)
            HStack {
                Text(text("Logical capacity", "逻辑容量"))
                TextField("100", value: $capacityGiB, format: .number).frame(width: 90)
                Text("GiB")
            }
            Toggle(text("Case-sensitive APFS", "区分大小写的 APFS"), isOn: $caseSensitive)
            Toggle(text("Encrypt this disk", "加密此开发盘"), isOn: $encrypted)
            if encrypted {
                SecureField(text("Password (not saved)", "密码（不会保存）"), text: $password)
                    .accessibilityIdentifier("uma.sectorium.create.password")
            } else {
                Text(text("New disks are unencrypted by default. Existing disks are never migrated.", "新建开发盘默认不加密；不会迁移现有开发盘。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(text("Logical capacity is not reserved physical space.", "逻辑容量不代表预留了同等物理空间。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(text("Cancel", "取消")) { showingCreate = false; password = "" }
                Button(text("Choose location and create", "选择位置并创建"), action: createDevelopmentDisk)
                    .disabled(model.isBusy || profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !SectoriumCapacityInput.isValid(capacityGiB) || (encrypted && password.isEmpty))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private var unlockSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text("Unlock development disk", "解锁开发盘")).font(.title2.weight(.semibold))
            Text(text("Leave the password empty for an unencrypted image. For an encrypted image, it is sent to the system disk utility over stdin and is not saved.",
                      "未加密镜像可留空。加密镜像的密码仅通过标准输入交给系统磁盘工具，不会保存。"))
                .font(.callout).foregroundStyle(.secondary)
            SecureField(text("Password", "密码"), text: $unlockPassword)
                .accessibilityIdentifier("uma.sectorium.unlock.password")
            HStack {
                Spacer()
                Button(text("Cancel", "取消")) { showingUnlock = false; unlockPassword = "" }
                Button(text("Unlock and start", "解锁并启动"), action: unlockAndStart)
                    .disabled(model.isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var ejectConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.wholeDeviceEjectConfirmation?.isContinuation == true
                ? text("Continue whole-drive eject", "继续弹出整块硬盘")
                : text("Confirm whole-drive eject", "确认弹出整块硬盘")).font(.title2.weight(.semibold))
            if let confirmation = model.wholeDeviceEjectConfirmation {
                Text(text("Physical drive: \(selectedDevice?.name ?? "External drive")",
                          "物理硬盘：\(selectedDevice?.name ?? "外接硬盘")")).font(.headline)
                Text(confirmation.isContinuation
                    ? text("Continue the recorded non-forcing physical eject for this exact device after rechecking the remaining mounted volumes.",
                           "重新核验仍挂载的宗卷后，继续此硬盘已记录的非强制整盘弹出。")
                    : text("This will unmount \(confirmation.affectedMembers.count) physical volume(s) and detach \(confirmation.attachedImageIdentities.count) virtual disk image(s).",
                           "此操作将卸载 \(confirmation.affectedMembers.count) 个物理宗卷，并分离 \(confirmation.attachedImageIdentities.count) 个虚拟磁盘镜像。"))
                    .font(.callout)
                DisclosureGroup(text("Technical identifiers", "技术标识")) {
                    Text(text("Physical identity: \(confirmation.physicalIdentity)", "物理身份：\(confirmation.physicalIdentity)"))
                    Text(text("Whole-device node: /dev/\(confirmation.bsdName)", "整盘设备节点：/dev/\(confirmation.bsdName)"))
                    ForEach(confirmation.affectedMembers, id: \.self) { member in
                        Text(text("Volume: \(member)", "宗卷：\(member)")).font(.system(.caption, design: .monospaced))
                    }
                    ForEach(confirmation.attachedImageIdentities, id: \.self) { image in
                        Text(text("Virtual image: \(image)", "虚拟镜像：\(image)")).font(.system(.caption, design: .monospaced))
                    }
                }
                Text(confirmation.dependenciesCanFinishOffTarget
                    ? text("Required control and state dependencies are outside this drive.", "所需控制程序和状态依赖位于此硬盘之外。")
                    : text("Required dependencies may be on this drive; eject is unavailable.", "所需依赖可能位于此硬盘上，无法弹出。"))
                    .font(.callout).foregroundStyle(confirmation.dependenciesCanFinishOffTarget ? Color.secondary : Color.red)
                Toggle(text("I closed known applications and writers using this drive", "我已关闭使用此硬盘的已知应用和写入程序"),
                       isOn: $knownWritersClosed)
                    .accessibilityIdentifier("uma.sectorium.eject-known-writers-closed")
                HStack {
                    Spacer()
                    Button(text("Cancel", "取消")) {
                        knownWritersClosed = false
                        model.cancelWholeDeviceEjectConfirmation()
                    }
                    Button(confirmation.isContinuation
                        ? text("Continue eject", "继续弹出")
                        : text("Unmount and eject", "卸载并弹出")) {
                        model.confirmWholeDeviceEject(knownWritersClosed: knownWritersClosed)
                        knownWritersClosed = false
                    }
                    .disabled(!knownWritersClosed || !confirmation.dependenciesCanFinishOffTarget || model.isBusy)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("uma.sectorium.eject-confirm")
                }
            } else {
                Text(text("The device scope could not be verified.", "无法验证硬盘及受影响范围。"))
                Button(text("Close", "关闭")) { model.cancelWholeDeviceEjectConfirmation() }
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        .onAppear { knownWritersClosed = false }
    }

    private var stopConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text("Confirm stopping development disk", "确认停止开发盘")).font(.title2.weight(.semibold))
            if let confirmation = model.stopConfirmation {
                Text(text("Stop the verified virtual disk on \(selectedDevice?.name ?? "the selected drive")? The physical drive will not be ejected.",
                          "停止 \(selectedDevice?.name ?? "所选硬盘") 上已验证的虚拟开发盘？此操作不会弹出物理硬盘。"))
                DisclosureGroup(text("Technical identifiers", "技术标识")) {
                    Text("Profile: \(confirmation.profileID)")
                    Text("Image: \(confirmation.imagePath)")
                    Text("Backing volume: \(confirmation.backingVolumeUUID.uuidString)")
                    Text("Development volume: \(confirmation.devVolumeUUID.uuidString)")
                }
                Toggle(text("I closed known applications and writers using the development disk", "我已关闭使用开发盘的已知应用和写入程序"),
                       isOn: $stopKnownWritersClosed)
                    .accessibilityIdentifier("uma.sectorium.stop-known-writers-closed")
                HStack {
                    Spacer()
                    Button(text("Cancel", "取消")) {
                        stopKnownWritersClosed = false
                        model.cancelStopConfirmation()
                    }
                    Button(text("Stop development disk", "停止开发盘")) {
                        model.stopDevelopmentDisk(knownWritersClosed: stopKnownWritersClosed)
                        stopKnownWritersClosed = false
                    }
                    .disabled(!stopKnownWritersClosed || model.isBusy)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("uma.sectorium.stop-confirm")
                }
            } else {
                Text(text("The mounted image identity could not be verified.", "无法验证已挂载镜像身份。"))
                Button(text("Close", "关闭")) { model.cancelStopConfirmation() }
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .onAppear { stopKnownWritersClosed = false }
    }

    private func startSelectedProfile() {
        guard let profile = selectedProfile else { return }
        guard profile.hasVerifiedImageFormat else { return }
        if profile.encrypted == false { model.startDevelopmentDisk() }
        else { showingUnlock = true }
    }

    private func unlockAndStart() {
        model.startDevelopmentDisk(password: unlockPassword)
        unlockPassword = ""
        showingUnlock = false
    }

    private func createDevelopmentDisk() {
        guard let deviceID = selectedDevice?.id else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = text("Create here", "在此创建")
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        guard let requestedBytes = SectoriumCapacityInput.requestedBytes(gib: capacityGiB) else {
            showCapacityAlert(text("Choose a capacity from 1 to 16,384 GiB.", "请选择 1 至 16,384 GiB 的容量。"))
            return
        }
        if let available = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           available >= 0, requestedBytes > UInt64(available) {
            guard let recommendedGiB = SectoriumCapacityInput.recommendedGiB(availableBytes: UInt64(available)) else {
                showCapacityAlert(text("Not enough available space for a useful development disk.",
                                       "可用空间不足，无法创建有实用容量的开发盘。"))
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = text("The requested logical capacity exceeds available space.", "请求的逻辑容量超过当前可用空间。")
            alert.informativeText = text("A sparsebundle does not reserve its full logical capacity. Use \(recommendedGiB) GiB, 80% of the currently available space?",
                                         "稀疏包不会预留全部逻辑容量。是否使用 \(recommendedGiB) GiB（当前可用空间的 80%）？")
            alert.addButton(withTitle: text("Use recommended capacity", "使用建议容量"))
            alert.addButton(withTitle: text("Cancel", "取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            capacityGiB = recommendedGiB
        }
        model.createDevelopmentDisk(deviceID: deviceID, parentDirectory: directory, name: profileName,
                                    capacityGiB: capacityGiB, caseSensitive: caseSensitive,
                                    password: encrypted ? password : nil)
        showingCreate = false; password = ""
    }

    private func showCapacityAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: text("OK", "好"))
        alert.runModal()
    }

    private func adoptExisting() {
        guard let deviceID = selectedDevice?.id else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false; panel.prompt = text("Adopt", "接纳")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.adoptDevelopmentDisk(deviceID: deviceID, imageURL: url)
    }

    private func physicalTitle(_ device: SectoriumPhysicalDevice) -> String {
        let mountedName = device.volumeMembers.first(where: { $0.mounted })?.name
        if let mountedName, !mountedName.isEmpty, mountedName != device.name {
            return "\(mountedName) · \(device.name)"
        }
        return device.name
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

private final class SectoriumWeakButtonReference: ObservableObject {
    weak var button: NSButton?
    weak var ownerWindow: NSWindow?
}

private struct SectoriumWorkbenchButton: NSViewRepresentable {
    let title: String
    let identifier: String
    let isEnabled: Bool
    let action: () -> Void
    var onReady: ((NSButton) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = SectoriumWorkbenchFocusableButton(title: title, target: context.coordinator,
                                                       action: #selector(Coordinator.activate(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
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
