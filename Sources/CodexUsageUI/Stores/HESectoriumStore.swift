import Combine
import AppKit
import Foundation
import HESectoriumCore
import HESectoriumRuntime

public enum SectoriumInventoryState: Equatable {
    case loading, available, empty, unavailable, malformed
}

struct SectoriumIOSampleHistoryEntry: Equatable {
    let deviceID: String
    let counters: SectoriumDeviceIOCounters
    let uptime: TimeInterval
}

/// Presentation keeps verified loading separate from operation progress and failures.
public struct SectoriumVolumeRow: Identifiable, Equatable, Sendable {
    public var id: String { profile.id }
    public let profile: SectoriumDevelopmentProfile
    public let parentDeviceID: String
    public let parentName: String
    public let isExternal: Bool
    public let verifiedLoaded: Bool?
    public let parentConnected: Bool
    public let canLoad: Bool
    public let canUnloadOnly: Bool
    public let canSafeUnloadAndEject: Bool
    public let isBusy: Bool
    public let importantDocumentURL: URL?
    public let documentationPending: Bool
    public let documentHistory: [SectoriumPortableDocumentEvent]
    public let capacityChangeUnavailableReason: String?

    public func message(isChinese: Bool) -> String {
        if !parentConnected && verifiedLoaded == false {
            return isChinese ? "硬盘已断开；登记已保留，重新连接后可继续。" : "Drive disconnected. Its registration is saved for reconnection."
        }
        if isBusy && verifiedLoaded == nil {
            return isChinese ? "已登记；正在核实当前状态，无需重复登记。" : "Registered. Checking its current state; no need to register again."
        }
        if !parentConnected { return isChinese ? "暂时无法确认母盘连接状态。" : "The parent drive connection could not be verified." }
        if verifiedLoaded == nil { return isChinese ? "暂时无法确认加载状态。请保持连接并刷新。" : "Loading could not be verified. Keep the drive connected and refresh." }
        return ""
    }
}

public struct SectoriumUserNotice: Equatable, Sendable {
    public let english: String
    public let chinese: String
    public func text(isChinese: Bool) -> String { isChinese ? chinese : english }

    static func operation(_ result: OperationResult, observed: Bool) -> Self {
        guard let failure = result.failure else {
            if observed && result.steps.contains(where: { $0.step == "verifyDevelopmentVolumeUnloaded" && $0.status == .succeeded }) {
                return .init(english: "Development volume unloaded. The parent drive remains connected.",
                             chinese: "开发卷已卸载，母盘保持连接。")
            }
            return observed
                ? .init(english: "Operation completed. Current volume states are shown above.", chinese: "操作已完成；当前开发卷状态见上方。")
                : .init(english: "The operation completed, but the current volume state could not be verified. Keep the drive connected and refresh.", chinese: "操作已完成，但当前卷状态尚无法确认。请保持连接并刷新。")
        }
        switch failure {
        case .occupancyBusy:
            return .init(english: "The drive is in use. Keep it connected; close the activity or wait, then try again.", chinese: "硬盘仍在使用中。请保持连接，结束相关操作或等待后重试。")
        case .occupancyIncomplete:
            return .init(english: "Activity could not be checked safely. Keep the drive connected and recheck before unloading.", chinese: "暂时无法可靠检查使用情况。请保持连接，重新检查后再卸载。")
        case .operationInProgress, .ejectAlreadyPending:
            return .init(english: "Another storage operation needs to finish first. Keep the drive connected.", chinese: "请先完成正在进行的存储操作，并保持硬盘连接。")
        case .outerStillPresent, .finalStateUnknown:
            return .init(english: "The parent drive was not confirmed ejected. Keep it connected and continue the pending operation.", chinese: "尚未确认母盘已弹出。请保持连接并继续待完成操作。")
        case .observationUnavailable, .readiness, .stateConflict, .stateUnavailable:
            return .init(english: "The volume could not be verified. No safe-to-disconnect result is available. Refresh and review its details.", chinese: "无法核实开发卷，尚不能确认可安全拔线。请刷新并查看详情。")
        case .workbenchFailed(let message) where message.hasPrefix("Load failed: "):
            let reason = String(message.dropFirst("Load failed: ".count))
            if reason.localizedCaseInsensitiveContains("cancel") {
                return .init(english: "Load was cancelled. Select Load to try again.", chinese: "加载已取消，可点击“加载”重试。")
            }
            return .init(english: "Load failed: " + reason, chinese: "加载未完成：" + reason)
        default:
            return .init(english: "The operation did not finish. The observed loading state remains shown above. Keep the drive connected and review the details before retrying.", chinese: "操作未完成；上方仍显示实际观察到的加载状态。请保持连接，查看详情后重试。")
        }
    }
}

/// An action result qualifies only its own target and only after its terminal
/// verification step. A command exit alone is never a lifecycle observation.
enum SectoriumCommandAction: Equatable, Sendable {
    case load, unload, disconnect, other

    var progress: SectoriumUserNotice {
        switch self {
        case .load: .init(english: "Loading the development volume…", chinese: "正在加载开发卷…")
        case .unload: .init(english: "Unloading the development volume… The parent drive stays connected.", chinese: "正在卸载开发卷…母盘将保持连接。")
        case .disconnect: .init(english: "Disconnecting the external drive…", chinese: "正在安全断开外接硬盘…")
        case .other: .init(english: "Updating storage…", chinese: "正在更新存储状态…")
        }
    }

    func isVerified(by result: OperationResult, pending: String?) -> Bool {
        guard result.succeeded, pending == nil else { return false }
        let completed = Set(result.steps.filter { $0.status == .succeeded }.map(\.step))
        switch self {
        case .load: return !completed.isDisjoint(with: ["reuseVerifiedImage", "validateImageChain", "validateMountedChain"])
        case .unload: return completed.contains("verifyDevelopmentVolumeUnloaded")
        case .disconnect:
            return !completed.isDisjoint(with: ["verifyWholeDeviceEjected", "verifyPhysicalDeviceAbsent"])
                && !completed.isDisjoint(with: ["ejectWholeDevice", "observeWholeDeviceAbsentAfterEjectIssue"])
        case .other: return false
        }
    }

    var success: SectoriumUserNotice {
        switch self {
        case .load: .init(english: "Load successful. The development volume is ready.", chinese: "加载成功，开发卷已就绪。")
        case .unload: .init(english: "Unload successful. The parent drive remains connected. Select Load to use the development volume again.", chinese: "卸载成功，母盘保持连接。点击“加载”可再次使用开发卷。")
        case .disconnect: .init(english: "Disconnect successful. The drive is disconnected safely; you can unplug it.", chinese: "安全断开成功，现在可以拔出硬盘。")
        case .other: .init(english: "Operation completed.", chinese: "操作已完成。")
        }
    }
}

public enum SectoriumSafetyTarget: Equatable, Sendable {
    case volume(String), drive(profileID: String, deviceID: String)
}

public struct SectoriumSafetyCheck: Equatable, Sendable {
    public let target: SectoriumSafetyTarget
    public let name: String
    public let activity: OccupancyAssessment
    public var processes: [SectoriumActivityProcess] = []
    public var applications: [SectoriumQuitApplication] = []
    public var waiting: Bool = false
    public var quitNotice: SectoriumUserNotice?
    public var canProceed: Bool { activity == .noVisibleOccupancy && !waiting }
}

/// The observer is independent of a particular SwiftUI page lifetime.
private final class SectoriumObservationLifetime: @unchecked Sendable {
    var diskObserver: (any SectoriumDiskChangeObserving)?
    var notifications: NotificationCenter?
    var tokens: [NSObjectProtocol] = []
    var automaticOperationToken: NSObjectProtocol?
    deinit {
        diskObserver?.stop()
        if let notifications { tokens.forEach(notifications.removeObserver) }
        if let automaticOperationToken { NotificationCenter.default.removeObserver(automaticOperationToken) }
    }
}

/// Only passive observation work uses this flag. An admitted storage action
/// retains its own token and must finish its mutation and postchecks normally.
private final class SectoriumObservationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

@MainActor
public final class HESectoriumStore: ObservableObject {
    @Published public private(set) var snapshot = HESectoriumRuntimeSnapshot(
        installed: .missing, automationEnabled: false, readiness: .unknown, pendingEject: nil,
        diagnostics: [], latestActionSummary: "Status has not been checked"
    )
    @Published public private(set) var hasObservedStatus = false
    @Published public private(set) var hasObservedRegistrations = false
    @Published public private(set) var registryUnavailable = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastResult = ""
    @Published public private(set) var workbench = SectoriumWorkbenchSnapshot()
    @Published public private(set) var inventoryState: SectoriumInventoryState = .loading
    @Published public private(set) var inventoryFailureDescription: String?
    @Published public private(set) var discoveredLegacyDisk = false
    @Published public private(set) var legacyDevelopmentByDevice: [String: HESectoriumService.LegacyDevelopmentDisplay] = [:]
    @Published public private(set) var localSamplingConsentDeviceIDs: Set<String> = []
    @Published public private(set) var wholeDeviceEjectConfirmation: SectoriumWholeDeviceEjectConfirmation?
    @Published public private(set) var canBeginWholeDeviceEject = false
    @Published public private(set) var canContinueWholeDeviceEject = false
    @Published public private(set) var canReturnFromWholeDeviceEject = false
    @Published public private(set) var pendingWholeDeviceEjectTargetID: String?
    @Published public private(set) var stopConfirmation: SectoriumStopConfirmation?

    @Published public private(set) var volumeRows: [SectoriumVolumeRow] = []
    @Published public private(set) var documentReadsInProgress: Set<String> = []
    @Published public private(set) var creationFilesystems: [SectoriumFilesystem] = []
    @Published public private(set) var userNotice: SectoriumUserNotice?
    @Published private(set) var activeWorkbenchAction: SectoriumCommandAction?
    public var progressNotice: SectoriumUserNotice {
        activeWorkbenchAction?.progress ?? .init(english: "Checking the drive…", chinese: "正在检查硬盘…")
    }
    @Published public private(set) var safeToUnplugDriveName: String?
    @Published public private(set) var safetyCheck: SectoriumSafetyCheck?
    private var safetyWaitTask: Task<Void, Never>?
    private var safetyGeneration: UInt64 = 0
    private var explicitEjectDeviceID: String?
    private var activeWorkbenchOperationToken: UUID?
    private var activeInstallOperationToken: UUID?
    private var completedWorkbenchAction: (result: OperationResult, ejectTarget: String?, target: String?, name: String?, profileID: String?, action: SectoriumCommandAction)?
    private var verifiedVolumeCommandNotice: (deviceID: String, notice: SectoriumUserNotice)?

    public var pendingEjectDriveDisconnected: Bool {
        guard let target = pendingWholeDeviceEjectTargetID else { return false }
        return volumeRows.contains { $0.parentDeviceID == target && !$0.parentConnected && $0.verifiedLoaded == false }
    }
    private var capacityObservations: [String: (profile: SectoriumDevelopmentProfile, loaded: Bool?, reason: String?)] = [:]
    /// Compare saved registration data with saved data, not a relocated display path.
    private var observedRegistrations: [String: SectoriumDevelopmentProfile] = [:]

    private var isPreviewFixture = false
    private let service: HESectoriumService
    private let applicationQuitter: any SectoriumApplicationQuitting
    private let sampleIntervalNanoseconds: UInt64
    private var observationGeneration: UInt64 = 0 {
        didSet { activeObservationCancellation?.cancel() }
    }
    private var workbenchIsActive = false
    private var workbenchIsSleeping = false
    private var sampleTask: Task<Void, Never>?
    private var activeSampleToken: UUID?
    /// Ephemeral, selected-device-only history. It is deliberately never persisted.
    private var ioHistory: [SectoriumIOSampleHistoryEntry] = []
    private var verifiedEjectDeviceID: String?
    private var verifiedEjectBSDName: String?
    private let workspaceNotifications: NotificationCenter?
    private let observationLifetime = SectoriumObservationLifetime()
    private let diskObserverFactory: @Sendable (@escaping @Sendable (SectoriumDiskChange) -> Void) -> (any SectoriumDiskChangeObserving)?
    private let consistencyProvider: @Sendable () -> SectoriumConsistencyStamp?
    private var monitoringStarted = false
    private var hasCompletedObservation = false
    /// A stable topology stamp cannot prove a previously failed detailed check.
    /// Retry unresolved details at the next consistency interval, never each tick.
    private var deepObservationNeedsRetry = false
    private var settingsAppearanceCount = 0
    private var surfaceGeneration: UInt64 = 0
    private var preparationSurfaceGeneration: UInt64 = 0
    private var diskChangeRevision: UInt64 = 0
    private var bootstrapWindowOpen = false
    private var connectionDebounceTask: Task<Void, Never>?
    private var activeConsistencyToken: UUID?
    private var lastConsistencyStamp: SectoriumConsistencyStamp?
    private var lastConsistencyObservation: TimeInterval = 0
    private var hasVisibleSurface: Bool { workbenchIsActive || settingsAppearanceCount > 0 }
    private var activeObservationToken: UUID?
    private var activeObservationCancellation: SectoriumObservationCancellation?
    private var activePreparationToken: UUID?
    private let observationClock: @Sendable () -> TimeInterval
    private var needsConnectionRefresh = false

    public init(service: HESectoriumService = .shared, sampleIntervalNanoseconds: UInt64 = 1_000_000_000,
                workspaceNotifications: NotificationCenter? = nil,
                observationClock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                diskObserverFactory: @escaping @Sendable (@escaping @Sendable (SectoriumDiskChange) -> Void) -> (any SectoriumDiskChangeObserving)? = { makeSystemSectoriumDiskChangeObserver(onChange: $0) },
                consistencyProvider: (@Sendable () -> SectoriumConsistencyStamp?)? = nil,
                applicationQuitter: (any SectoriumApplicationQuitting)? = nil) {
        self.service = service; self.sampleIntervalNanoseconds = max(1, sampleIntervalNanoseconds)
        self.applicationQuitter = applicationQuitter ?? SectoriumSystemApplicationQuitter()
        self.workspaceNotifications = workspaceNotifications
        self.observationClock = observationClock
        self.diskObserverFactory = diskObserverFactory
        self.consistencyProvider = consistencyProvider ?? { service.observeSectoriumConsistency() }
    }

    #if DEBUG
    public static func isolatedPreviewFixture() -> HESectoriumStore {
        let service = HESectoriumService(paths: HESectoriumPaths(root: URL(fileURLWithPath: "/private/tmp/auv-sectorium-render-only")),
            runner: SectoriumPreviewNoCommands(), identityPolicy: .expected,
            sectoriumDeviceObserver: SectoriumPreviewNoCommands(),
            sectoriumDeviceIOSampler: SectoriumPreviewNoCommands())
        let store = HESectoriumStore(service: service)
        store.isPreviewFixture = true
        let externalID = "E0A66D35-BD8E-45CE-AB7B-3027E2470001"
        let internalID = "E0A66D35-BD8E-45CE-AB7B-3027E2470002"
        let external = SectoriumPhysicalDevice(id: externalID, bsdName: "fixture-external", name: "HE · External SSD",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 1_000_000_000_000,
            mountedVolumePaths: ["/fixture/HE"], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        let internalDrive = SectoriumPhysicalDevice(id: internalID, bsdName: "fixture-internal", name: "Mac internal storage",
            isExternal: false, identityVerified: true, wholeDeviceBytes: 256_000_000_000,
            mountedVolumePaths: ["/fixture/Internal"], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        func row(_ name: String, parent: SectoriumPhysicalDevice, loaded: Bool?, capacity: UInt64, pending: Bool = false) -> SectoriumVolumeRow {
            let root = parent.mountedVolumePaths[0]
            let profile = SectoriumDevelopmentProfile(name: name, deviceID: parent.id, backingVolumeUUID: UUID(),
                backingMountPoint: root, imagePath: root + "/" + name + ".sparsebundle",
                devVolumeName: name, devMountPoint: root + "/" + name, devUUID: UUID(), encrypted: false,
                caseSensitive: false, logicalCapacityBytes: capacity * 1_073_741_824, imageFormat: "UDSB", validation: .validated)
            return .init(profile: profile, parentDeviceID: parent.id, parentName: parent.name,
                isExternal: parent.isExternal, verifiedLoaded: loaded, parentConnected: true,
                canLoad: loaded == false, canUnloadOnly: loaded == true,
                canSafeUnloadAndEject: loaded == true && parent.isExternal, isBusy: false,
                importantDocumentURL: nil, documentationPending: pending, documentHistory: [],
                capacityChangeUnavailableReason: loaded == false ? nil : "Unload before resizing")
        }
        store.volumeRows = [row("DEV_APFS", parent: external, loaded: true, capacity: 300),
            row("Research", parent: external, loaded: false, capacity: 100),
            row("Archive", parent: external, loaded: nil, capacity: 50, pending: true),
            row("Local Lab", parent: internalDrive, loaded: false, capacity: 30)]
        store.workbench = .init(devices: [external, internalDrive], selectedDeviceID: externalID,
            profiles: store.volumeRows.map(\.profile), readiness: .ready)
        store.creationFilesystems = [.apfs, .apfsCaseSensitive]
        store.inventoryState = .available
        store.hasObservedStatus = true
        store.hasObservedRegistrations = true
        store.snapshot = .init(installed: .installed, automationEnabled: true, readiness: .ready,
            pendingEject: false, diagnostics: [], latestActionSummary: "Synthetic render fixture; no host observations",
            agentLoadStatus: .loaded)
        return store
    }
    #endif

    public func activateWorkbench() {
        guard !isPreviewFixture, !workbenchIsActive else { return }
        workbenchIsActive = true
        activateObservationSurface()
    }

    public func deactivateWorkbench() {
        guard workbenchIsActive else { return }
        workbenchIsActive = false
        discardSurfaceConfirmations()
        localSamplingConsentDeviceIDs.removeAll()
        invalidateCounterSample(clearReading: true)
        stopVisibleTimerIfHidden()
    }

    /// Settings shares the same snapshot and listeners, without enabling I/O sampling.
    public func activateSettings() {
        guard !isPreviewFixture else { return }
        settingsAppearanceCount += 1
        activateObservationSurface()
    }

    public func deactivateSettings() {
        settingsAppearanceCount = max(0, settingsAppearanceCount - 1)
        if !hasVisibleSurface { discardSurfaceConfirmations() }
        stopVisibleTimerIfHidden()
    }

    private func activateObservationSurface() {
        if !monitoringStarted {
            monitoringStarted = true
            observationLifetime.automaticOperationToken = NotificationCenter.default.addObserver(
                forName: HESectoriumService.automaticOperationDidCompleteNotification,
                object: service, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Startup/reconnect automation may finish after the first
                    // observation. One event-driven follow-up replaces that stale
                    // result; neither tab switching nor a retry loop is needed.
                    self?.storageConnectionChanged()
                }
            }
            let notifications = workspaceNotifications ?? NSWorkspace.shared.notificationCenter
            observationLifetime.notifications = notifications
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
                observationLifetime.tokens.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    let isSleep = notification.name == NSWorkspace.willSleepNotification
                    MainActor.assumeIsolated {
                        if isSleep { self?.pauseSamplingForSleep() }
                        else { self?.resumeSamplingAfterWake() }
                    }
                })
            }
            observationLifetime.diskObserver = diskObserverFactory { [weak self] change in
                Task { @MainActor [weak self] in self?.storageConnectionChanged(change) }
            }
            if let observer = observationLifetime.diskObserver {
                // Coalesce the subscription's initial appeared wave before starting
                // observation. Events after it starts must not be absorbed.
                bootstrapWindowOpen = true
                observer.start()
                debounceConnectionRefresh()
            }
            else {
                // If Disk Arbitration is unavailable, retain the narrower workspace
                // notifications for the same lifetime. The five-minute check remains.
                for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                    observationLifetime.tokens.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.storageConnectionChanged() }
                    })
                }
            }
        }
        if !hasCompletedObservation && activeObservationToken == nil && !isBusy { needsConnectionRefresh = true }
        startPendingConnectionRefresh()
        refreshVisibleStatusIfDue()
        guard sampleTask == nil else { return }
        sampleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.sampleIntervalNanoseconds else { return }
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
                guard let self, self.hasVisibleSurface else { return }
                if self.workbenchIsActive { self.sampleSelectedDeviceIO() }
                self.refreshVisibleStatusIfDue()
            }
        }
    }

    private func stopVisibleTimerIfHidden() {
        guard !hasVisibleSurface else { return }
        sampleTask?.cancel(); sampleTask = nil
        // Listeners and an already-running passive observation remain alive.
    }

    private func discardSurfaceConfirmations() {
        surfaceGeneration &+= 1
        safetyGeneration &+= 1
        safetyWaitTask?.cancel(); safetyWaitTask = nil
        safetyCheck = nil
        stopConfirmation = nil
        wholeDeviceEjectConfirmation = nil
        // A preparation still owns busy until its callback drains. Navigation only
        // invalidates its UI confirmation, not the passive observation generation.
    }

    public func pauseSamplingForSleep() {
        guard !isPreviewFixture else { return }
        workbenchIsSleeping = true
        diskChangeRevision &+= 1
        needsConnectionRefresh = true
        invalidateCounterSample(clearReading: true)
        invalidateConnectionState()
    }

    public func resumeSamplingAfterWake() {
        guard !isPreviewFixture else { return }
        workbenchIsSleeping = false
        invalidateCounterSample(clearReading: true)
        storageConnectionChanged()
    }

    /// Native events remain subscribed while hidden. They revoke display
    /// qualifications immediately; only a visible surface starts deep observation.
    func storageConnectionChanged(_ change: SectoriumDiskChange? = nil) {
        guard !isPreviewFixture else { return }
        if bootstrapWindowOpen, activeObservationToken == nil,
           let change, change.kind == .appeared {
            // The upcoming first observation covers these pre-observation events.
            return
        }
        diskChangeRevision &+= 1
        needsConnectionRefresh = true
        let alreadyUnloadedVolume = change.map { event in
            event.kind == .disappeared && event.volumeUUID.map { uuid in
                volumeRows.contains { row in
                    row.profile.devUUID == uuid && row.verifiedLoaded == false && row.parentConnected
                        && row.canLoad && workbench.pendingOperation == nil
                }
            } == true && !workbench.devices.contains { $0.bsdName == event.bsdName }
        } == true
        let alreadyDisconnectedDrive = change.map {
            $0.kind == .disappeared && $0.bsdName != nil
                && $0.bsdName == verifiedEjectBSDName && verifiedEjectDeviceID != nil
        } == true
        // DA may deliver the development-volume disappearance after Unload's
        // native postcheck. That event agrees with the verified state. Retain
        // Load while checking in the background; parent disappearance still revokes it.
        if !alreadyUnloadedVolume && !alreadyDisconnectedDrive {
            invalidateConnectionState(affectedDeviceIDs: change.flatMap(affectedDeviceIDs))
        }
        if let change, change.kind == .disappeared, let bsdName = change.bsdName {
            // A child volume disappearing does not prove its physical parent absent.
            // A matching whole-device disappearance does, without granting safe-eject success.
            let absentIDs = Set(workbench.devices.filter { $0.isVirtual == false && $0.bsdName == bsdName }.map(\.id))
            if !absentIDs.isEmpty {
                if let receipt = verifiedVolumeCommandNotice, absentIDs.contains(receipt.deviceID) {
                    if userNotice == receipt.notice { userNotice = nil }
                    verifiedVolumeCommandNotice = nil
                }
                volumeRows = volumeRows.map { absentIDs.contains($0.parentDeviceID) ? Self.disconnected($0) : $0 }
                workbench = .init(devices: workbench.devices.filter { !absentIDs.contains($0.id) },
                    selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
                    selectedProfileID: workbench.selectedProfileID,
                    readiness: workbench.selectedDeviceID.map(absentIDs.contains) == true ? .ejected : workbench.readiness,
                    pendingOperation: workbench.pendingOperation, operationSteps: workbench.operationSteps)
            }
        }
        debounceConnectionRefresh()
    }

    private func debounceConnectionRefresh() {
        connectionDebounceTask?.cancel()
        connectionDebounceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self else { return }
            self.connectionDebounceTask = nil
            self.startPendingConnectionRefresh()
        }
    }

    /// Nil means the relationship is unknown; BSD strings are correlation hints
    /// only. No event grants a volume or physical-device operation permission.
    private func affectedDeviceIDs(_ change: SectoriumDiskChange) -> Set<String>? {
        var matches = Set<String>()
        for device in workbench.devices {
            if change.wholeDiskBSDName == device.bsdName || change.bsdName == device.bsdName
                || change.mediaUUID.map({ $0 == device.wholeMediaUUID }) == true
                || change.volumeUUID.map({ device.volumeUUIDs.contains($0) }) == true {
                matches.insert(device.id)
            }
        }
        if let uuid = change.volumeUUID {
            for profile in workbench.profiles where profile.devUUID == uuid || profile.backingVolumeUUID == uuid {
                matches.insert(profile.deviceID)
            }
        }
        return matches.isEmpty ? nil : matches
    }

    private func startPendingConnectionRefresh() {
        guard needsConnectionRefresh, hasVisibleSurface, !workbenchIsSleeping,
              !isBusy, activeObservationToken == nil, activeConsistencyToken == nil,
              connectionDebounceTask == nil else { return }
        needsConnectionRefresh = false
        refresh(background: true)
    }

    private func finishOperationObservation() {
        activeWorkbenchAction = nil
        isBusy = false
        if needsConnectionRefresh { startPendingConnectionRefresh() }
    }

    private func beginPreparation() -> (token: UUID, generation: UInt64) {
        let token = UUID()
        activePreparationToken = token
        preparationSurfaceGeneration = surfaceGeneration
        isBusy = true
        observationGeneration &+= 1
        return (token, observationGeneration)
    }

    /// A cancelled page may discard a confirmation, but its read-only preparation
    /// must still release busy state. Actual storage operations drain separately.
    private func finishPreparation(_ preparation: (token: UUID, generation: UInt64)) -> Bool {
        guard activePreparationToken == preparation.token else { return false }
        activePreparationToken = nil
        isBusy = false
        guard preparationSurfaceGeneration == surfaceGeneration else {
            startPendingConnectionRefresh()
            return false
        }
        guard observationGeneration == preparation.generation, !needsConnectionRefresh,
              !workbenchIsSleeping else {
            needsConnectionRefresh = true
            startPendingConnectionRefresh()
            return false
        }
        return true
    }

    func refreshVisibleStatusIfDue(now: TimeInterval? = nil) {
        let now = now ?? observationClock()
        if needsConnectionRefresh { startPendingConnectionRefresh(); return }
        guard hasVisibleSurface, !workbenchIsSleeping, !isPreviewFixture, !isBusy,
              activeObservationToken == nil, activeConsistencyToken == nil,
              hasCompletedObservation, now - lastConsistencyObservation >= 300 else { return }
        let token = UUID(), revision = diskChangeRevision, generation = observationGeneration
        activeConsistencyToken = token
        let provider = consistencyProvider
        Task.detached(priority: .utility) { [weak self] in
            let stamp = provider()
            Self.deliverObservation { [weak self] in
                guard let self, self.activeConsistencyToken == token else { return }
                self.activeConsistencyToken = nil
                self.lastConsistencyObservation = self.observationClock()
                guard self.diskChangeRevision == revision, self.observationGeneration == generation,
                      !self.workbenchIsSleeping else {
                    self.startPendingConnectionRefresh()
                    return
                }
                if stamp == nil || self.lastConsistencyStamp == nil || stamp != self.lastConsistencyStamp {
                    self.diskChangeRevision &+= 1
                    self.needsConnectionRefresh = true
                    self.invalidateConnectionState()
                } else if self.deepObservationNeedsRetry {
                    // Keep any verified rows visible while retrying the unresolved
                    // details. An unchanged stamp does not turn unknown into known.
                    self.needsConnectionRefresh = true
                }
                self.startPendingConnectionRefresh()
            }
        }
    }

    private func invalidateConnectionState(affectedDeviceIDs: Set<String>? = nil) {
        let affected: (String) -> Bool = { affectedDeviceIDs?.contains($0) ?? true }
        capacityObservations = capacityObservations.filter { !affected($0.value.profile.deviceID) }
        if verifiedEjectDeviceID.map(affected) ?? (affectedDeviceIDs == nil) {
            verifiedEjectDeviceID = nil
            safeToUnplugDriveName = nil
        }
        discardSurfaceConfirmations()
        volumeRows = volumeRows.map { affected($0.parentDeviceID) ? Self.unverified($0) : $0 }
        for id in Array(legacyDevelopmentByDevice.keys) where affected(id) {
            legacyDevelopmentByDevice[id] = Self.unverified(legacyDevelopmentByDevice[id]!)
        }
        if workbench.selectedDeviceID.map(affected) ?? true {
            // A description update revokes current action qualifications, not a
            // completed Load/Unload receipt. Actual absence is handled separately.
            if userNotice != verifiedVolumeCommandNotice?.notice { userNotice = nil }
            hasObservedStatus = false
            canBeginWholeDeviceEject = false
            canContinueWholeDeviceEject = false
            canReturnFromWholeDeviceEject = false
            invalidateCounterSample(clearReading: true)
            workbench = .init(devices: workbench.devices, selectedDeviceID: workbench.selectedDeviceID,
                profiles: workbench.profiles, selectedProfileID: workbench.selectedProfileID,
                readiness: .unknown("Storage connection changed; verifying current state"),
                pendingOperation: workbench.pendingOperation, operationSteps: workbench.operationSteps)
        }
        // An admitted action owns its generation and fresh postchecks. Events
        // queue a separate observation; passive callbacks can never clear it.
        if !isBusy { observationGeneration &+= 1 }
    }

    public func isLocalDeviceSamplingConsented(_ deviceID: String) -> Bool {
        localSamplingConsentDeviceIDs.contains(deviceID)
    }

    public func setLocalDeviceSamplingConsent(_ consented: Bool, for deviceID: String) {
        guard workbenchIsActive, !workbenchIsSleeping,
              let device = workbench.devices.first(where: { $0.id == deviceID }),
              workbench.selectedDeviceID == deviceID, !device.isExternal, device.identityVerified else { return }
        if consented { localSamplingConsentDeviceIDs.insert(deviceID) }
        else { localSamplingConsentDeviceIDs.remove(deviceID) }
        invalidateCounterSample(clearReading: true)
        if consented { sampleSelectedDeviceIO() }
    }

    public func refresh() {
        refresh(background: false)
    }

    func refresh(background: Bool) {
        guard !isBusy, !isPreviewFixture, !workbenchIsSleeping else { return }
        guard activeObservationToken == nil, activeConsistencyToken == nil else {
            needsConnectionRefresh = true
            if !background { invalidateConnectionState() }
            return
        }
        bootstrapWindowOpen = false
        if !background {
            hasObservedStatus = false
            volumeRows = volumeRows.map { Self.unverified($0) }
            canBeginWholeDeviceEject = false
            canContinueWholeDeviceEject = false
            canReturnFromWholeDeviceEject = false
            inventoryState = .loading
            discoveredLegacyDisk = false
            legacyDevelopmentByDevice = legacyDevelopmentByDevice.mapValues { Self.unverified($0) }
            inventoryFailureDescription = nil
            invalidateCounterSample(clearReading: true)
            workbench = SectoriumWorkbenchSnapshot(
                devices: workbench.devices, selectedDeviceID: workbench.selectedDeviceID,
                profiles: workbench.profiles, selectedProfileID: workbench.selectedProfileID,
                readiness: .unknown("Refreshing device and development disk identity"),
                pendingOperation: workbench.pendingOperation,
                io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
                operationSteps: workbench.operationSteps, safeToUnplug: false
            )
            snapshot = HESectoriumRuntimeSnapshot(
                installed: snapshot.installed, automationEnabled: snapshot.automationEnabled,
                readiness: .unknown, pendingEject: snapshot.pendingEject,
                diagnostics: snapshot.diagnostics, latestActionSummary: snapshot.latestActionSummary,
                agentLoadStatus: snapshot.agentLoadStatus, operationProgress: snapshot.operationProgress
            )
        }
        let observationToken = UUID()
        activeObservationToken = observationToken
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        let cancellation = SectoriumObservationCancellation()
        activeObservationCancellation = cancellation
        let selectedID = workbench.selectedDeviceID
        let selectedProfileID = workbench.selectedProfileID
        let previousRegistrations = observedRegistrations
        let consistencyProvider = self.consistencyProvider
        let revision = diskChangeRevision
        let needsInitialInventory = !hasCompletedObservation && workbench.devices.isEmpty
        Task.detached(priority: .utility) { [weak self] in
            // Superseded work drains its current bounded read, then releases the
            // observation token. The queued current observation can start without
            // waiting for unrelated profiles, service checks or eject eligibility.
            defer {
                if cancellation.isCancelled {
                    Self.deliverObservation { [weak self] in
                        guard let self, self.activeObservationToken == observationToken else { return }
                        self.activeObservationToken = nil
                        self.activeObservationCancellation = nil
                        self.startPendingConnectionRefresh()
                    }
                }
            }
            guard !cancellation.isCancelled else { return }
            if needsInitialInventory {
                // A cold window can display bounded physical-device metadata before
                // consistency, recovery or startup automation releases its lock.
                // This separate snapshot grants no loading or eject permission.
                let inventory = Result { try service.observeSectoriumInventoryForDisplay() }
                Self.deliverObservation { [weak self] in
                    guard let self, self.observationGeneration == generation,
                          self.activeObservationToken == observationToken else { return }
                    self.publishDisplayInventory(inventory)
                }
            }
            guard !cancellation.isCancelled else { return }
            // Capture before the deep read. A late registry change cannot be
            // folded into a post-read baseline and hidden until another change.
            let stamp = consistencyProvider()
            guard !cancellation.isCancelled else { return }
            _ = service.reconcileCompletedUnload()
            _ = service.reconcileInterruptedLoad()
            _ = service.reconcileWholeDeviceEjectRecovery()
            guard !cancellation.isCancelled else { return }
            service.withReadOnlyObservation {
                // A running automatic action may have held the service lock while
                // its completion notification superseded this queued observation.
                guard !cancellation.isCancelled else { return }
                let rawInventory = Result { try service.observeSectoriumDevices() }
                let safelyEjectedIDs = service.verifiedSafelyEjectedDeviceIDs()
                // A successful OS eject can leave the USB hardware node enumerated.
                // It is no longer a connected storage location. Keep saved volume
                // cards as Disconnected, with the verified result retained.
                let observed = rawInventory.map { devices in
                    devices.filter { !safelyEjectedIDs.contains($0.id) }
                }
                guard !cancellation.isCancelled else { return }
                let devices = try? observed.get()
                // Inventory is useful on its own. Service installation, document and
                // eject-qualification checks must not hide an already observed drive.
                Self.deliverObservation { [weak self] in
                    guard let self, self.observationGeneration == generation else { return }
                    if let previous = self.verifiedEjectDeviceID, !safelyEjectedIDs.contains(previous) {
                        self.verifiedEjectDeviceID = nil
                        self.verifiedEjectBSDName = nil
                        self.safeToUnplugDriveName = nil
                        if self.userNotice == SectoriumCommandAction.disconnect.success { self.userNotice = nil }
                    }
                    if let identity = safelyEjectedIDs.contains(selectedID ?? "") ? selectedID : safelyEjectedIDs.sorted().first {
                        let device = (try? rawInventory.get())?.first { $0.id == identity }
                        self.recordVerifiedEjection(deviceID: identity, name: device?.name
                            ?? self.volumeRows.first { $0.parentDeviceID == identity }?.parentName)
                        self.verifiedEjectBSDName = device?.bsdName ?? self.verifiedEjectBSDName
                    }
                    self.publishInventory(observed)
                }
                let pending = service.pendingSectoriumOperation()
                let pendingEjectTargetID = pending?.hasPrefix("eject:") == true
                    ? service.pendingWholeDeviceEjectPhysicalIdentity() : nil
                Self.deliverObservation { [weak self] in
                    guard let self, self.observationGeneration == generation else { return }
                    self.pendingWholeDeviceEjectTargetID = pendingEjectTargetID
                    if pending == nil {
                        self.canContinueWholeDeviceEject = false
                        self.canReturnFromWholeDeviceEject = false
                        if !safelyEjectedIDs.isEmpty { self.userNotice = SectoriumCommandAction.disconnect.success }
                    }
                    self.workbench = .init(devices: self.workbench.devices,
                        selectedDeviceID: self.workbench.selectedDeviceID, profiles: self.workbench.profiles,
                        selectedProfileID: self.workbench.selectedProfileID, readiness: self.workbench.readiness,
                        pendingOperation: pending, io: self.workbench.io,
                        operationSteps: self.workbench.operationSteps, safeToUnplug: self.workbench.safeToUnplug)
                    // Removal completion needs the operation receipt and fresh
                    // whole-device absence, not optional service or document checks.
                    if let target = self.completedWorkbenchAction?.target,
                       devices.map({ !$0.contains { $0.id == target } }) == true {
                        self.publishCompletedWorkbenchAction(devices: devices, pending: pending)
                    }
                }
                let effectiveID = selectedID
                    ?? pendingEjectTargetID
                    ?? devices.flatMap(SectoriumWorkbenchDeviceOrdering.defaultSelection(from:))?.id
                guard let profiles = service.sectoriumProfilesObservation(resolvePaths: false) else {
                    Self.deliverObservation { [weak self] in
                        if self?.activeObservationToken == observationToken {
                            self?.activeObservationToken = nil
                            self?.activeObservationCancellation = nil
                        }
                        guard let self else { return }
                        guard self.observationGeneration == generation else {
                            self.startPendingConnectionRefresh()
                            return
                        }
                        self.publishUnavailableRegistry(pending: pending)
                        self.completeConsistencyBaseline(stamp, revision: revision, needsRetry: true)
                        self.startPendingConnectionRefresh()
                    }
                    return
                }
                guard !cancellation.isCancelled else { return }
                Self.deliverObservation { [weak self] in
                    guard let self, self.observationGeneration == generation else { return }
                    self.publishRegistrations(profiles, devices: devices, preservingExistingObservations: background)
                }
                // Selection binds on this background path. A newly visible drive can
                // be clicked while the previous refresh still owns the service lock.
                let selectedDevice = devices?.first { $0.id == effectiveID && $0.isVirtual == false }
                service.selectSectoriumDevice(effectiveID, observedBSDName: selectedDevice?.bsdName,
                    observedDevice: selectedDevice)
                let matchingProfiles = profiles.filter { $0.deviceID == effectiveID }
                service.selectSectoriumProfile(matchingProfiles.first { $0.id == selectedProfileID }?.id
                    ?? (matchingProfiles.count == 1 ? matchingProfiles.first?.id : nil))
                var qualifiedRows: [SectoriumVolumeRow] = []
                var profileReadiness: [String: SectoriumWorkbenchReadiness] = [:]
                var ejectEligibilityByParent: [String: Bool] = [:]
                // Finish each registered volume before inspecting the next one. A
                // slow unrelated drive must not withhold an already qualified row.
                let externalParents = Set((devices ?? []).filter { $0.isExternal && $0.isVirtual == false }.map(\.id))
                let prioritizedProfiles = profiles.filter { externalParents.contains($0.deviceID) }
                    + profiles.filter { !externalParents.contains($0.deviceID) }
                for savedProfile in prioritizedProfiles {
                    guard !cancellation.isCancelled else { return }
                    let registrationChanged = previousRegistrations[savedProfile.id].map { $0 != savedProfile } ?? false
                    let presence = Self.parentPresence(profile: savedProfile, devices: devices)
                    let profile = presence == true ? (service.sectoriumProfileObservation(profileID: savedProfile.id) ?? savedProfile) : savedProfile
                    guard !cancellation.isCancelled else { return }
                    guard let loading = Self.observeVolumeLoadingRows(service: service, devices: devices,
                        profiles: [profile], pending: pending).first else { continue }
                    guard !cancellation.isCancelled else { return }
                    // verifiedLoadedState above already observed this profile. The
                    // runtime scope retains its full result, including read-only
                    // and precise unknown states, without another device traversal.
                    if presence == true { profileReadiness[profile.id] = service.profileReadiness(profileID: profile.id) }
                    Self.deliverObservation { [weak self] in
                        guard let self, self.observationGeneration == generation else { return }
                        // A changed saved registration is a new qualification input.
                        // Keep its old permissions revoked until this row's complete
                        // qualification returns, even if loading itself looks valid.
                        if registrationChanged && loading.verifiedLoaded == true { return }
                        // A background observation keeps the previous completed qualification
                        // while its replacement is in flight. New negative loading,
                        // connection or operation evidence revokes it immediately.
                        let hasPreviousLoading = self.volumeRows.first { $0.id == loading.id }?.verifiedLoaded == true
                        if !background || !hasPreviousLoading || loading.verifiedLoaded != true || !loading.parentConnected || loading.isBusy {
                            self.publishVolumeObservation(loading)
                        }
                    }
                    let eligible: Bool
                    if let cached = ejectEligibilityByParent[loading.parentDeviceID] {
                        eligible = cached
                    } else {
                        eligible = !loading.isBusy && loading.parentConnected && loading.isExternal
                            && service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: loading.parentDeviceID)
                        ejectEligibilityByParent[loading.parentDeviceID] = eligible
                    }
                    guard !cancellation.isCancelled else { return }
                    let qualified = Self.qualifyVolumeEjectRow(loading, canEject: loading.verifiedLoaded == true && eligible)
                    qualifiedRows.append(qualified)
                    Self.deliverObservation { [weak self] in
                        guard let self, self.observationGeneration == generation else { return }
                        self.publishVolumeObservation(qualified)
                    }
                }
                guard !cancellation.isCancelled else { return }
                // Preserve registration order while displaying any freshly resolved paths.
                let displayProfiles = profiles.map { saved in
                    qualifiedRows.first { $0.id == saved.id }?.profile ?? saved
                }
                let legacyByDevice = Self.observeLegacyDisplays(service: service, devices: devices)
                guard !cancellation.isCancelled else { return }
                let legacy = effectiveID.flatMap { legacyByDevice[$0] } != nil
                Self.deliverObservation { [weak self] in
                    guard let self, self.observationGeneration == generation else { return }
                    self.legacyDevelopmentByDevice = legacyByDevice
                    self.discoveredLegacyDisk = legacy
                    self.workbench = SectoriumWorkbenchSnapshot(devices: self.workbench.devices,
                        selectedDeviceID: self.workbench.selectedDeviceID, profiles: displayProfiles,
                        selectedProfileID: self.workbench.selectedProfileID,
                        readiness: self.workbench.readiness, pendingOperation: pending,
                        io: self.workbench.io, operationSteps: self.workbench.operationSteps,
                        safeToUnplug: self.workbench.safeToUnplug)
                }
                let readiness = Self.observedReadiness(deviceID: effectiveID, selectedProfileID: selectedProfileID,
                    devices: devices, rows: qualifiedRows, profileReadiness: profileReadiness,
                    pending: pending, legacy: effectiveID.flatMap { legacyByDevice[$0] })
                let value = service.refreshStatus(observedReadiness: readiness)
                guard !cancellation.isCancelled else { return }
                let rows = Self.enrichVolumeRows(service: service, rows: qualifiedRows)
                let filesystems = service.supportedCreationFilesystems()
                let canBeginEject = pending == nil && effectiveID.flatMap { ejectEligibilityByParent[$0] } == true
                let recovery = Self.ejectRecoveryAvailability(selectedDeviceID: selectedID,
                    pendingOperation: pending, pendingEjectTargetID: pendingEjectTargetID,
                    canContinue: { service.prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: $0) != nil },
                    canReturn: { service.canReturnFromWholeDeviceEject(physicalIdentity: $0) })
                guard !cancellation.isCancelled else { return }
                let canContinueEject = recovery.canContinue
                let canReturnEject = recovery.canReturn
                let needsRetry = devices == nil || rows.contains { row in
                    !row.isBusy && (row.verifiedLoaded == nil
                        || (row.parentConnected && row.isExternal && ejectEligibilityByParent[row.parentDeviceID] == false))
                } || legacyByDevice.values.contains { $0.state == .unknown }
                // Deliver the result through the AppKit event loop, including
                // nested loops used by native foreground controls.
                Self.deliverObservation { [weak self] in
                    if self?.activeObservationToken == observationToken {
                        self?.activeObservationToken = nil
                        self?.activeObservationCancellation = nil
                    }
                    guard let self else { return }
                    guard self.observationGeneration == generation else {
                        self.startPendingConnectionRefresh()
                        return
                    }
                    self.snapshot = value
                    self.volumeRows = rows
                    self.creationFilesystems = filesystems
                    self.hasObservedStatus = true
                    switch observed {
                    case .success(let devices):
                        self.canBeginWholeDeviceEject = canBeginEject
                        self.canContinueWholeDeviceEject = canContinueEject
                        self.canReturnFromWholeDeviceEject = canReturnEject
                        self.inventoryState = devices.contains(where: { $0.isVirtual == false }) ? .available : .empty
                        self.apply(devices: devices, profiles: displayProfiles, readiness: readiness, pending: pending,
                                   discoveredLegacy: legacy, legacyByDevice: legacyByDevice,
                                   pendingEjectTargetID: pendingEjectTargetID)
                    case .failure(let error):
                        self.canBeginWholeDeviceEject = false
                        self.canContinueWholeDeviceEject = false
                        self.canReturnFromWholeDeviceEject = false
                        self.inventoryState = (error as? SectoriumDeviceCatalogError) == .malformedDeviceInventory ? .malformed : .unavailable
                        self.apply(devices: [], profiles: displayProfiles,
                                   readiness: .unknown("Device inventory observation failed; refresh after checking disk access"),
                                   pending: pending, discoveredLegacy: false, legacyByDevice: [:],
                                   pendingEjectTargetID: pendingEjectTargetID)
                    }
                    self.publishCompletedWorkbenchAction(devices: devices, pending: pending)
                    self.completeConsistencyBaseline(stamp, revision: revision, needsRetry: needsRetry)
                    self.startPendingConnectionRefresh()
                }
            }
        }
    }

    private func completeConsistencyBaseline(_ stamp: SectoriumConsistencyStamp?, revision: UInt64, needsRetry: Bool) {
        hasCompletedObservation = true
        if diskChangeRevision == revision {
            lastConsistencyStamp = stamp
            lastConsistencyObservation = observationClock()
            deepObservationNeedsRetry = needsRetry
        }
    }

    private nonisolated static func deliverObservation(_ body: @escaping @MainActor @Sendable () -> Void) {
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent(), 0, 0, 0) { _ in MainActor.assumeIsolated { body() } }
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .commonModes)
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func publishDisplayInventory(_ observed: Result<[SectoriumPhysicalDevice], Error>) {
        switch observed {
        case .success(let devices):
            inventoryState = devices.contains { $0.isVirtual == false } ? .available : .empty
            inventoryFailureDescription = nil
            workbench = SectoriumWorkbenchSnapshot(devices: devices,
                selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
                selectedProfileID: workbench.selectedProfileID, readiness: workbench.readiness,
                pendingOperation: workbench.pendingOperation, io: workbench.io,
                operationSteps: workbench.operationSteps, safeToUnplug: workbench.safeToUnplug)
        case .failure(let error):
            inventoryState = (error as? SectoriumDeviceCatalogError) == .malformedDeviceInventory ? .malformed : .unavailable
            inventoryFailureDescription = String(describing: error)
        }
        // Registrations, volume state, qualification and the consistency baseline
        // remain owned by the serialized observation below, including on failure.
    }

    private func publishInventory(_ observed: Result<[SectoriumPhysicalDevice], Error>) {
        let devices: [SectoriumPhysicalDevice]
        switch observed {
        case .success(let value):
            devices = value
            inventoryState = value.contains { $0.isVirtual == false } ? .available : .empty
            inventoryFailureDescription = nil
        case .failure(let error):
            devices = []
            inventoryState = (error as? SectoriumDeviceCatalogError) == .malformedDeviceInventory ? .malformed : .unavailable
            inventoryFailureDescription = String(describing: error)
        }
        if let verifiedEjectDeviceID, devices.contains(where: { $0.id == verifiedEjectDeviceID }) {
            self.verifiedEjectDeviceID = nil
            safeToUnplugDriveName = nil
            userNotice = nil
        }
        let observedIDs = Set(devices.map(\.id))
        legacyDevelopmentByDevice = legacyDevelopmentByDevice.filter { observedIDs.contains($0.key) }
        volumeRows = volumeRows.map { row in
            if case .success = observed {
                let presence = Self.parentPresence(profile: row.profile, devices: devices)
                if presence == true { return row }
                if presence == false { return Self.disconnected(row) }
            }
            return Self.unverified(row)
        }
        if case .success = observed, let selected = workbench.selectedDeviceID,
           volumeRows.contains(where: { $0.parentDeviceID == selected && !$0.parentConnected && $0.verifiedLoaded == false }) {
            // Retain the diagnostic receipt, but do not leave a stale notice
            // asking for connection after native inventory confirms absence.
            userNotice = nil
        }
        workbench = SectoriumWorkbenchSnapshot(devices: devices,
            selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: workbench.selectedProfileID, readiness: workbench.readiness,
            pendingOperation: workbench.pendingOperation, io: workbench.io,
            operationSteps: workbench.operationSteps,
            safeToUnplug: verifiedEjectDeviceID != nil
                && inventoryState != .unavailable && inventoryState != .malformed)
    }

    /// Registration is durable knowledge, separate from fresh device readiness.
    /// Publish it before slow service/document/eject checks so a fresh window
    /// never makes a saved volume look as though it needs registration again.
    private func publishRegistrations(_ profiles: [SectoriumDevelopmentProfile], devices: [SectoriumPhysicalDevice]?,
                                      preservingExistingObservations: Bool) {
        hasObservedRegistrations = true
        registryUnavailable = false
        volumeRows = profiles.map { profile in
            let device = devices?.first { $0.id == profile.deviceID && $0.isVirtual == false && $0.identityVerified }
            let previous = volumeRows.first { $0.id == profile.id }
            if preservingExistingObservations, device != nil, let previous,
               observedRegistrations[profile.id] == profile {
                return previous
            }
            let parentObserved = Self.parentPresence(profile: profile, devices: devices)
            return SectoriumVolumeRow(profile: profile, parentDeviceID: profile.deviceID,
                parentName: device?.name ?? previous?.parentName ?? URL(fileURLWithPath: profile.backingMountPoint).lastPathComponent,
                isExternal: device?.isExternal ?? previous?.isExternal ?? true,
                verifiedLoaded: parentObserved == false ? false : nil,
                parentConnected: device != nil,
                canLoad: false, canUnloadOnly: false, canSafeUnloadAndEject: false,
                isBusy: parentObserved != false,
                importantDocumentURL: nil, documentationPending: previous?.documentationPending ?? false,
                documentHistory: previous?.documentHistory ?? [],
                capacityChangeUnavailableReason: "Current state is being checked")
        }
        observedRegistrations = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let registeredParents = Set(profiles.map(\.deviceID))
        legacyDevelopmentByDevice = legacyDevelopmentByDevice.filter { !registeredParents.contains($0.key) }
        workbench = SectoriumWorkbenchSnapshot(devices: workbench.devices,
            selectedDeviceID: workbench.selectedDeviceID, profiles: profiles,
            selectedProfileID: workbench.selectedProfileID, readiness: workbench.readiness,
            pendingOperation: workbench.pendingOperation, io: workbench.io,
            operationSteps: workbench.operationSteps, safeToUnplug: workbench.safeToUnplug)
    }

    /// A failed registry read does not establish an empty registry. Preserve
    /// known identities for display, but revoke actions until a valid reread.
    private func publishUnavailableRegistry(pending: String?) {
        registryUnavailable = true
        observedRegistrations.removeAll()
        hasObservedRegistrations = false
        hasObservedStatus = true
        capacityObservations.removeAll()
        creationFilesystems = []
        canBeginWholeDeviceEject = false
        canContinueWholeDeviceEject = false
        canReturnFromWholeDeviceEject = false
        wholeDeviceEjectConfirmation = nil
        stopConfirmation = nil
        cancelSafetyCheck()
        verifiedEjectDeviceID = nil
        safeToUnplugDriveName = nil
        discoveredLegacyDisk = false
        legacyDevelopmentByDevice = [:]
        volumeRows = volumeRows.map { row in
            SectoriumVolumeRow(profile: row.profile, parentDeviceID: row.parentDeviceID,
                parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: nil,
                parentConnected: workbench.devices.contains { $0.id == row.parentDeviceID && $0.identityVerified && $0.isVirtual == false },
                canLoad: false, canUnloadOnly: false, canSafeUnloadAndEject: false, isBusy: false,
                importantDocumentURL: nil, documentationPending: row.documentationPending,
                documentHistory: row.documentHistory,
                capacityChangeUnavailableReason: "Saved volume registrations could not be read")
        }
        workbench = SectoriumWorkbenchSnapshot(devices: workbench.devices,
            selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: workbench.selectedProfileID,
            readiness: .unknown("Saved volume registrations could not be read"), pendingOperation: pending,
            io: workbench.io, operationSteps: workbench.operationSteps, safeToUnplug: false)
        snapshot = HESectoriumRuntimeSnapshot(installed: snapshot.installed,
            automationEnabled: snapshot.automationEnabled, readiness: .unknown,
            pendingEject: snapshot.pendingEject, diagnostics: snapshot.diagnostics,
            latestActionSummary: "Saved volume registrations could not be read",
            agentLoadStatus: snapshot.agentLoadStatus, operationProgress: snapshot.operationProgress)
    }

    private func publishVolumeObservation(_ row: SectoriumVolumeRow) {
        // The observation generation owns this update; the same registered ID
        // may have a newly verified backing mount path after reconnection.
        guard let index = volumeRows.firstIndex(where: { $0.id == row.id }) else { return }
        let previous = volumeRows[index]
        volumeRows[index] = SectoriumVolumeRow(profile: row.profile, parentDeviceID: row.parentDeviceID,
            parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: row.verifiedLoaded,
            parentConnected: row.parentConnected, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
            canSafeUnloadAndEject: row.canSafeUnloadAndEject, isBusy: row.isBusy,
            importantDocumentURL: nil, documentationPending: previous.documentationPending,
            documentHistory: previous.documentHistory,
            capacityChangeUnavailableReason: row.capacityChangeUnavailableReason)
    }

    nonisolated static func observedReadiness(deviceID: String?, selectedProfileID: String?,
        devices: [SectoriumPhysicalDevice]?, rows: [SectoriumVolumeRow],
        profileReadiness: [String: SectoriumWorkbenchReadiness], pending: String?,
        legacy: HESectoriumService.LegacyDevelopmentDisplay?) -> SectoriumWorkbenchReadiness {
        guard let devices else { return .unknown("Device inventory observation failed") }
        if let pending { return .operationInProgress(pending) }
        guard let deviceID else { return .noDevice }
        guard let device = devices.first(where: { $0.id == deviceID && $0.isVirtual == false }) else { return .ejected }
        guard device.identityVerified else { return .unknown("Physical device identity is unavailable") }
        let candidates = rows.filter { $0.parentDeviceID == deviceID }
        guard !candidates.isEmpty else {
            guard let legacy else { return .noDevelopmentDisk }
            switch legacy.state {
            case .mounted: return .connected
            case .unmounted: return .notStarted
            case .unknown: return .unknown("Configured development disk state could not be verified")
            }
        }
        let row = selectedProfileID.flatMap { selectedID in candidates.first { $0.id == selectedID } }
            ?? (selectedProfileID == nil && candidates.count == 1 ? candidates.first : nil)
        guard let row else { return .unknown("Select a development profile to verify readiness") }
        guard row.profile.hasVerifiedImageFormat else { return .unknown("The selected image format has not been verified") }
        return profileReadiness[row.id] ?? .unknown("Development volume state could not be verified")
    }

    nonisolated static func ejectRecoveryTarget(selectedDeviceID: String?, pendingOperation: String?,
                                    pendingEjectTargetID: String?) -> String? {
        // An incomplete or invalid eject journal must never silently redirect recovery to
        // whichever other drive happens to be selected in this window.
        if pendingOperation?.hasPrefix("eject:") == true { return pendingEjectTargetID }
        return selectedDeviceID
    }

    nonisolated static func ejectRecoveryAvailability(selectedDeviceID: String?, pendingOperation: String?,
        pendingEjectTargetID: String?, canContinue: (String) -> Bool,
        canReturn: (String) -> Bool) -> (canContinue: Bool, canReturn: Bool) {
        let target = ejectRecoveryTarget(selectedDeviceID: selectedDeviceID,
            pendingOperation: pendingOperation, pendingEjectTargetID: pendingEjectTargetID)
        return (pendingOperation?.hasPrefix("eject:") == true && target.map(canContinue) == true,
                target.map(canReturn) ?? false)
    }

    public func selectDevice(_ id: String?) {
        guard !isPreviewFixture, !isBusy else { return }
        invalidateConnectionState()
        verifiedEjectDeviceID = nil
        explicitEjectDeviceID = nil
        wholeDeviceEjectConfirmation = nil
        canBeginWholeDeviceEject = false
        canContinueWholeDeviceEject = false
        canReturnFromWholeDeviceEject = false
        invalidateCounterSample(clearReading: true)
        let selected = workbench.devices.first { $0.id == id && $0.isVirtual == false }
        let deviceProfiles = workbench.profiles.filter { $0.deviceID == id }
        let selectedProfileID = deviceProfiles.count == 1 ? deviceProfiles.first?.id : nil
        let readiness: SectoriumWorkbenchReadiness = workbench.pendingOperation.map(SectoriumWorkbenchReadiness.operationInProgress)
            ?? (id == nil ? .noDevice : selected?.identityVerified == true ? .connected : .unknown("Physical device identity is unavailable"))
        workbench = SectoriumWorkbenchSnapshot(
            devices: workbench.devices, selectedDeviceID: id, profiles: workbench.profiles,
            selectedProfileID: selectedProfileID,
            readiness: readiness,
            pendingOperation: workbench.pendingOperation,
            io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
            operationSteps: workbench.operationSteps, safeToUnplug: false
        )
        refresh()
    }

    public func selectProfile(_ id: String?) {
        guard !isPreviewFixture, !isBusy else { return }
        invalidateConnectionState()
        verifiedEjectDeviceID = nil
        let profile = workbench.profiles.first { $0.id == id && $0.deviceID == workbench.selectedDeviceID }
        workbench = SectoriumWorkbenchSnapshot(
            devices: workbench.devices, selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: profile?.id, readiness: workbench.readiness,
            pendingOperation: workbench.pendingOperation, io: workbench.io,
            operationSteps: workbench.operationSteps, safeToUnplug: false
        )
        refresh()
    }

    func apply(devices: [SectoriumPhysicalDevice], profiles: [SectoriumDevelopmentProfile],
               readiness: SectoriumWorkbenchReadiness?, pending: String?, discoveredLegacy: Bool? = nil,
               legacyByDevice: [String: HESectoriumService.LegacyDevelopmentDisplay]? = nil,
               pendingEjectTargetID: String? = nil) {
        pendingWholeDeviceEjectTargetID = pending?.hasPrefix("eject:") == true
            ? pendingEjectTargetID : nil
        if let discoveredLegacy { discoveredLegacyDisk = discoveredLegacy }
        if let legacyByDevice { legacyDevelopmentByDevice = legacyByDevice }
        else if discoveredLegacy == false { legacyDevelopmentByDevice = [:] }
        invalidateCounterSample(clearReading: false)
        let previousSelectedID = workbench.selectedDeviceID
        let selectedID = devices.first(where: { $0.id == previousSelectedID && $0.isVirtual == false })?.id
            ?? pendingEjectTargetID
            ?? (previousSelectedID == nil
                ? SectoriumWorkbenchDeviceOrdering.defaultSelection(from: devices)?.id
                : (verifiedEjectDeviceID == previousSelectedID ? previousSelectedID : nil))
        let selectedProfileID = workbench.selectedProfileID
        if let verifiedEjectDeviceID, devices.contains(where: { $0.id == verifiedEjectDeviceID }) {
            self.verifiedEjectDeviceID = nil
            safeToUnplugDriveName = nil
            userNotice = nil
        }
        workbench = SectoriumWorkbenchSnapshot(
            devices: devices, selectedDeviceID: selectedID, profiles: profiles,
            selectedProfileID: profiles.first(where: { $0.id == selectedProfileID && $0.deviceID == selectedID })?.id
                ?? (profiles.filter { $0.deviceID == selectedID }.count == 1 ? profiles.first(where: { $0.deviceID == selectedID })?.id : nil),
            readiness: pending.map(SectoriumWorkbenchReadiness.operationInProgress)
                ?? (readiness ?? workbench.readiness), pendingOperation: pending,
            io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
            operationSteps: workbench.operationSteps,
            safeToUnplug: verifiedEjectDeviceID != nil
                && !devices.contains(where: { $0.id == verifiedEjectDeviceID })
                && pending == nil && inventoryState != .unavailable && inventoryState != .malformed
        )
    }

    /// Called by the active workbench's bounded sampling loop. Tests may invoke this through
    /// @testable imports; production sampling remains selected-device-only.
    func sampleSelectedDeviceIO() {
        guard workbenchIsActive, !workbenchIsSleeping, !isBusy, activeSampleToken == nil,
              let selectedID = workbench.selectedDeviceID,
              let device = workbench.devices.first(where: { $0.id == selectedID }),
              device.identityVerified,
              device.isExternal || localSamplingConsentDeviceIDs.contains(selectedID) else {
            if workbench.selectedDeviceID == nil || workbench.selectedDeviceID.flatMap({ id in
                workbench.devices.first(where: { $0.id == id })
            }).map({ !$0.identityVerified || (!$0.isExternal && !localSamplingConsentDeviceIDs.contains($0.id)) }) == true {
                invalidateCounterSample(clearReading: true)
            }
            return
        }
        let token = UUID()
        activeSampleToken = token
        let service = self.service
        Task.detached(priority: .utility) { [weak self] in
            let counters = service.sampleSectoriumDeviceCounters(for: device)
            let sampledAt = ProcessInfo.processInfo.systemUptime
            await MainActor.run {
                guard let self, self.activeSampleToken == token else { return }
                self.activeSampleToken = nil
                guard self.workbenchIsActive, !self.workbenchIsSleeping,
                      self.workbench.selectedDeviceID == selectedID,
                      device.isExternal || self.localSamplingConsentDeviceIDs.contains(selectedID),
                      let counters else {
                    self.ioHistory.removeAll(keepingCapacity: false)
                    self.updateIO(.init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false))
                    return
                }
                let reading: SectoriumIOReading
                self.ioHistory = Self.prunedIOHistory(self.ioHistory, now: sampledAt)
                if let previous = self.ioHistory.last, previous.deviceID == selectedID {
                    reading = Self.rateReading(previous: previous.counters, current: counters,
                                               elapsed: sampledAt - previous.uptime)
                } else {
                    reading = .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)
                }
                self.ioHistory.append(.init(deviceID: selectedID, counters: counters, uptime: sampledAt))
                self.ioHistory = Self.prunedIOHistory(self.ioHistory, now: sampledAt)
                self.updateIO(reading)
            }
        }
    }

    static func rateReading(previous: SectoriumDeviceIOCounters, current: SectoriumDeviceIOCounters,
                            elapsed: TimeInterval) -> SectoriumIOReading {
        guard elapsed >= 0.5, elapsed <= 3.0,
              current.readBytes >= previous.readBytes, current.writtenBytes >= previous.writtenBytes else {
            return .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)
        }
        let readRate = Double(current.readBytes - previous.readBytes) / elapsed
        let writeRate = Double(current.writtenBytes - previous.writtenBytes) / elapsed
        // Native counters can reset or be malformed. Floating-point conversion
        // rounds UInt64.max upward, so even equality with this bound is unsafe.
        guard readRate.isFinite, writeRate.isFinite,
              readRate < Double(UInt64.max), writeRate < Double(UInt64.max) else {
            return .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)
        }
        return .init(readBytesPerSecond: UInt64(readRate), writtenBytesPerSecond: UInt64(writeRate), isFresh: true)
    }

    static func prunedIOHistory(_ history: [SectoriumIOSampleHistoryEntry], now: TimeInterval) -> [SectoriumIOSampleHistoryEntry] {
        Array(history.filter { $0.uptime <= now && now - $0.uptime <= 60 }.suffix(120))
    }

    private func invalidateCounterSample(clearReading: Bool) {
        activeSampleToken = nil
        ioHistory.removeAll(keepingCapacity: false)
        if clearReading { updateIO(.init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)) }
    }

    private func updateIO(_ io: SectoriumIOReading) {
        workbench = SectoriumWorkbenchSnapshot(devices: workbench.devices,
            selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: workbench.selectedProfileID, readiness: workbench.readiness,
            pendingOperation: workbench.pendingOperation, io: io,
            operationSteps: workbench.operationSteps, safeToUnplug: workbench.safeToUnplug)
    }

    nonisolated static func observeLegacyDisplays(service: HESectoriumService,
        devices: [SectoriumPhysicalDevice]?) -> [String: HESectoriumService.LegacyDevelopmentDisplay] {
        guard let devices else { return [:] }
        return Dictionary(uniqueKeysWithValues: devices.filter { $0.isVirtual == false }.compactMap { device in
            service.legacyDevelopmentDisplay(deviceID: device.id, devices: devices).map { (device.id, $0) }
        })
    }

    nonisolated static func unverified(_ legacy: HESectoriumService.LegacyDevelopmentDisplay)
        -> HESectoriumService.LegacyDevelopmentDisplay {
        .init(name: legacy.name, mountPoint: nil, logicalCapacityBytes: legacy.logicalCapacityBytes,
              state: .unknown)
    }

    nonisolated static func unverified(_ row: SectoriumVolumeRow) -> SectoriumVolumeRow {
        .init(profile: row.profile, parentDeviceID: row.parentDeviceID, parentName: row.parentName,
              isExternal: row.isExternal, verifiedLoaded: nil, parentConnected: row.parentConnected,
              canLoad: false, canUnloadOnly: false, canSafeUnloadAndEject: false, isBusy: true,
              importantDocumentURL: nil, documentationPending: row.documentationPending,
              documentHistory: row.documentHistory, capacityChangeUnavailableReason: row.capacityChangeUnavailableReason)
    }

    nonisolated static func disconnected(_ row: SectoriumVolumeRow) -> SectoriumVolumeRow {
        .init(profile: row.profile, parentDeviceID: row.parentDeviceID, parentName: row.parentName,
            isExternal: row.isExternal, verifiedLoaded: false, parentConnected: false,
            canLoad: false, canUnloadOnly: false, canSafeUnloadAndEject: false, isBusy: false,
            importantDocumentURL: nil, documentationPending: row.documentationPending,
            documentHistory: row.documentHistory, capacityChangeUnavailableReason: "Parent drive is disconnected")
    }

    nonisolated static func observeVolumeRows(service: HESectoriumService,
        devices: [SectoriumPhysicalDevice]?, profiles: [SectoriumDevelopmentProfile], pending: String?) -> [SectoriumVolumeRow] {
        let loading = observeVolumeLoadingRows(service: service, devices: devices, profiles: profiles, pending: pending)
        return enrichVolumeRows(service: service, rows: qualifyVolumeEjectRows(service: service, rows: loading))
    }

    /// Missing identity is not proof of physical absence. Unresolved media that
    /// is not confirmed internal, or a backing-volume hint, leaves the parent unknown.
    nonisolated static func parentPresence(profile: SectoriumDevelopmentProfile,
                                          devices: [SectoriumPhysicalDevice]?) -> Bool? {
        guard let devices else { return nil }
        if let exact = devices.first(where: { $0.id == profile.deviceID && $0.isVirtual != true }) {
            return exact.identityVerified && exact.isVirtual == false ? true : nil
        }
        if devices.contains(where: { device in
            device.isVirtual != true && (
                device.volumeUUIDs.contains(profile.backingVolumeUUID)
                || device.mountedVolumePaths.contains(profile.backingMountPoint)
                || (!device.identityVerified && !device.isInternalConfirmed))
        }) { return nil }
        return false
    }

    nonisolated static func observeVolumeLoadingRows(service: HESectoriumService,
        devices: [SectoriumPhysicalDevice]?, profiles: [SectoriumDevelopmentProfile], pending: String?) -> [SectoriumVolumeRow] {
        let safelyEjected = service.verifiedSafelyEjectedDeviceIDs()
        return profiles.map { profile in
            let device = devices?.first { $0.id == profile.deviceID && $0.identityVerified && $0.isVirtual == false
                && !safelyEjected.contains($0.id) }
            let presence = safelyEjected.contains(profile.deviceID) ? false : parentPresence(profile: profile, devices: devices)
            let loaded = presence == false ? false : (presence == true ? service.verifiedLoadedState(profileID: profile.id) : nil)
            let active = pending != nil && presence != false
            return SectoriumVolumeRow(profile: profile, parentDeviceID: profile.deviceID,
                parentName: device?.name ?? URL(fileURLWithPath: profile.backingMountPoint).lastPathComponent,
                isExternal: device?.isExternal ?? true, verifiedLoaded: loaded,
                parentConnected: device != nil, canLoad: device != nil && loaded == false && !active && profile.hasVerifiedImageFormat,
                canUnloadOnly: loaded == true && !active,
                canSafeUnloadAndEject: false, isBusy: active,
                importantDocumentURL: nil, documentationPending: false, documentHistory: [],
                capacityChangeUnavailableReason: "Capacity availability has not been checked")
        }
    }

    nonisolated static func qualifyVolumeEjectRows(service: HESectoriumService,
        rows: [SectoriumVolumeRow]) -> [SectoriumVolumeRow] {
        rows.map { row in
            let canEject = row.verifiedLoaded == true && !row.isBusy && row.parentConnected && row.isExternal
                && service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: row.parentDeviceID)
            return qualifyVolumeEjectRow(row, canEject: canEject)
        }
    }

    nonisolated static func qualifyVolumeEjectRow(_ row: SectoriumVolumeRow, canEject: Bool) -> SectoriumVolumeRow {
        SectoriumVolumeRow(profile: row.profile, parentDeviceID: row.parentDeviceID,
            parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: row.verifiedLoaded,
            parentConnected: row.parentConnected, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
            canSafeUnloadAndEject: canEject, isBusy: row.isBusy,
            importantDocumentURL: nil, documentationPending: row.documentationPending,
            documentHistory: row.documentHistory, capacityChangeUnavailableReason: row.capacityChangeUnavailableReason)
    }

    nonisolated static func enrichVolumeRows(service: HESectoriumService,
        rows: [SectoriumVolumeRow]) -> [SectoriumVolumeRow] {
        rows.map { row in
            SectoriumVolumeRow(profile: row.profile, parentDeviceID: row.parentDeviceID,
                parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: row.verifiedLoaded,
                parentConnected: row.parentConnected, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
                canSafeUnloadAndEject: row.canSafeUnloadAndEject, isBusy: row.isBusy,
                importantDocumentURL: nil,
                documentationPending: service.portableDocumentationPending(profileID: row.id),
                documentHistory: service.portableDocumentHistory(profileID: row.id),
                capacityChangeUnavailableReason: row.capacityChangeUnavailableReason)
        }
    }

    /// History access is explicit. Passive status observation never touches the
    /// document on a removable drive or performs capacity-edit prechecks.
    public func verifiedHistoryDocument(profileID: String) async -> URL? {
        guard !isBusy, !isPreviewFixture, !workbenchIsSleeping, !registryUnavailable,
              !documentReadsInProgress.contains(profileID),
              let profile = volumeRows.first(where: { $0.id == profileID && $0.parentConnected })?.profile else { return nil }
        documentReadsInProgress.insert(profileID)
        defer { documentReadsInProgress.remove(profileID) }
        let generation = observationGeneration
        let surface = surfaceGeneration
        let service = self.service
        let url = await Task.detached(priority: .userInitiated) {
            service.portableDocumentURL(profileID: profileID)
        }.value
        guard observationGeneration == generation, surfaceGeneration == surface, !workbenchIsSleeping,
              volumeRows.contains(where: { $0.profile == profile && $0.parentConnected }) else { return nil }
        if url == nil {
            userNotice = .init(english: "The history document could not be verified. Keep its parent drive connected and try again.",
                chinese: "暂时无法核实历史文档。请保持母盘连接后重试。")
        }
        return url
    }

    public func capacityChangeUnavailableReason(for row: SectoriumVolumeRow) -> String? {
        if let observed = capacityObservations[row.id], observed.profile == row.profile,
           observed.loaded == row.verifiedLoaded, row.parentConnected {
            return observed.reason
        }
        return row.capacityChangeUnavailableReason
    }

    public func refreshVolumeSettings(profileID: String) {
        guard !isBusy, !isPreviewFixture, !workbenchIsSleeping, !registryUnavailable,
              let profile = volumeRows.first(where: { $0.id == profileID })?.profile else { return }
        let generation = observationGeneration
        let service = self.service
        Task.detached(priority: .utility) { [weak self] in
            let reason = service.capacityChangeAvailability(profileID: profileID)
            await MainActor.run {
                guard let self, self.observationGeneration == generation, !self.workbenchIsSleeping,
                      let index = self.volumeRows.firstIndex(where: { $0.profile == profile }) else { return }
                let row = self.volumeRows[index]
                self.capacityObservations[profileID] = (profile: profile, loaded: row.verifiedLoaded, reason: reason)
                self.volumeRows[index] = SectoriumVolumeRow(profile: row.profile, parentDeviceID: row.parentDeviceID,
                    parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: row.verifiedLoaded,
                    parentConnected: row.parentConnected, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
                    canSafeUnloadAndEject: row.canSafeUnloadAndEject, isBusy: row.isBusy,
                    importantDocumentURL: nil, documentationPending: row.documentationPending,
                    documentHistory: row.documentHistory, capacityChangeUnavailableReason: reason)
            }
        }
    }

    public func retryDocumentation(profileID: String) {
        guard !isBusy, !isPreviewFixture, !workbenchIsSleeping, !registryUnavailable,
              volumeRows.contains(where: { $0.id == profileID }) else { return }
        isBusy = true
        observationGeneration &+= 1
        let generation = observationGeneration
        let surface = surfaceGeneration
        let service = self.service
        Task.detached(priority: .utility) { [weak self] in
            let result = service.retryPortableDocumentation(profileID: profileID)
            let pending = service.portableDocumentationPending(profileID: profileID)
            let history = service.portableDocumentHistory(profileID: profileID)
            await MainActor.run {
                guard let self else { return }
                defer { self.finishOperationObservation() }
                self.isBusy = false
                guard self.observationGeneration == generation, !self.workbenchIsSleeping else { return }
                if self.surfaceGeneration == surface {
                    switch result {
                    case .updated, .unchanged:
                        self.userNotice = .init(english: "IMPORTANT.md is up to date. Volume loading was not changed.",
                                           chinese: "IMPORTANT.md 已同步；开发卷加载状态未改变。")
                    case .pending(let reason):
                        self.userNotice = .init(english: "IMPORTANT.md still needs to sync. Keep the parent drive connected and review the details; volume loading was not changed.",
                                           chinese: "IMPORTANT.md 尚待同步。请保持母盘连接并查看详情；开发卷加载状态未改变。")
                        self.lastResult = reason
                    }
                }
                // A connection event owns the queued refresh; let completion
                // drain it once instead of starting a second obsolete read.
                if !self.needsConnectionRefresh,
                   let index = self.volumeRows.firstIndex(where: { $0.id == profileID }) {
                    let row = self.volumeRows[index]
                    self.volumeRows[index] = SectoriumVolumeRow(profile: row.profile, parentDeviceID: row.parentDeviceID,
                        parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: row.verifiedLoaded,
                        parentConnected: row.parentConnected, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
                        canSafeUnloadAndEject: row.canSafeUnloadAndEject, isBusy: row.isBusy,
                        importantDocumentURL: nil, documentationPending: pending, documentHistory: history,
                        capacityChangeUnavailableReason: row.capacityChangeUnavailableReason)
                }
            }
        }
    }

    public func createDevelopmentDisk(request: SectoriumCreateRequest) {
        performWorkbench({ $0.createDevelopmentDisk(request) }, operationTargetID: request.deviceID)
    }

    public func loadDevelopmentDisk(profileID: String, password: String? = nil) {
        guard volumeRows.contains(where: { $0.id == profileID && $0.canLoad }) else { return }
        performWorkbench({ $0.startDevelopmentDisk(profileID: profileID, password: password) },
            profileID: profileID, actionKind: .load)
    }

    public func updateDevelopmentDisk(profileID: String, change: SectoriumProfileChange) {
        guard volumeRows.contains(where: { $0.id == profileID }) else { return }
        performWorkbench({ $0.updateDevelopmentDisk(profileID: profileID, change: change) })
    }

    public func prepareUnloadOnlyConfirmation(profileID: String) {
        guard let row = volumeRows.first(where: { $0.id == profileID }), row.canUnloadOnly else { return }
        prepareSafetyCheck(target: .volume(profileID), name: row.profile.name)
    }

    public func prepareSafeUnloadAndEject(profileID: String) {
        guard let row = volumeRows.first(where: { $0.id == profileID }), row.canSafeUnloadAndEject else { return }
        prepareSafetyCheck(target: .drive(profileID: profileID, deviceID: row.parentDeviceID), name: row.parentName)
    }

    private func prepareSafetyCheck(target: SectoriumSafetyTarget, name: String) {
        guard !isBusy, !isPreviewFixture else { return }
        safetyWaitTask?.cancel()
        safetyGeneration &+= 1
        let generation = safetyGeneration
        let preparation = beginPreparation()
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let report: SectoriumActivityReport
            switch target {
            case .volume(let id): report = service.profileActivityReport(profileID: id)
            case .drive(_, let id): report = service.wholeDeviceActivityReport(physicalIdentity: id)
            }
            await MainActor.run {
                guard let self, self.finishPreparation(preparation),
                      self.safetyGeneration == generation else { return }
                self.safetyCheck = .init(target: target, name: name, activity: report.assessment,
                    processes: report.processes, applications: self.applicationQuitter.applications(using: report.processes))
                if report.assessment == .noVisibleOccupancy { self.confirmSafeUnload() }
            }
        }
    }

    public func cancelSafetyCheck() {
        guard safetyCheck != nil else { return }
        safetyGeneration &+= 1
        safetyWaitTask?.cancel(); safetyWaitTask = nil
        safetyCheck = nil
        activePreparationToken = nil
        isBusy = false
    }

    /// Waiting repeats observations only. Becoming clear offers Continue; it never
    /// unloads in the background, and execution performs its own fresh activity check.
    public func waitForSafeUnload() {
        guard let check = safetyCheck, !isBusy else { return }
        safetyWaitTask?.cancel()
        safetyGeneration &+= 1
        let generation = safetyGeneration
        let service = self.service
        safetyCheck = .init(target: check.target, name: check.name, activity: check.activity,
            processes: check.processes, applications: check.applications, waiting: true)
        safetyWaitTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                let report = await Task.detached(priority: .utility) {
                    switch check.target {
                    case .volume(let id): return service.profileActivityReport(profileID: id)
                    case .drive(_, let id): return service.wholeDeviceActivityReport(physicalIdentity: id)
                    }
                }.value
                guard !Task.isCancelled, let self, self.safetyGeneration == generation,
                      self.safetyCheck?.target == check.target else { return }
                let clear = report.assessment == .noVisibleOccupancy
                self.safetyCheck = .init(target: check.target, name: check.name, activity: report.assessment,
                    processes: report.processes, applications: self.applicationQuitter.applications(using: report.processes),
                    waiting: !clear)
                if clear { self.safetyWaitTask = nil; return }
            }
        }
    }

    public func recheckSafeUnload() {
        guard let check = safetyCheck, !isBusy else { return }
        prepareSafetyCheck(target: check.target, name: check.name)
    }

    /// Called only by the explicit, named Quit-and-retry button. It never force
    /// terminates apps and never treats an accepted quit request as disk safety.
    public func quitBlockingApplicationsAndRetry() {
        guard let check = safetyCheck, !check.waiting, !isBusy, !check.applications.isEmpty else { return }
        safetyWaitTask?.cancel()
        safetyGeneration &+= 1
        let generation = safetyGeneration
        let currentApps = applicationQuitter.applications(using: check.processes)
        // Consent belongs to the displayed PID/bundle identities, not a newly
        // launched replacement application or a new blocker discovered later.
        let approvedApps = currentApps.filter { check.applications.contains($0) }
        guard !approvedApps.isEmpty else { recheckSafeUnload(); return }
        var progress = check
        progress.waiting = true
        progress.quitNotice = .init(english: "Waiting for the selected apps to quit. Save any open work when asked.",
                                   chinese: "正在等待所选应用退出；如出现保存提示，请先保存工作。")
        safetyCheck = progress
        safetyWaitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await SectoriumApplicationQuitSequence.run(applications: approvedApps, quitter: self.applicationQuitter)
            guard !Task.isCancelled, self.safetyGeneration == generation,
                  self.safetyCheck?.target == check.target else { return }
            self.safetyWaitTask = nil
            switch result {
            case .finished:
                self.prepareSafetyCheck(target: check.target, name: check.name)
            case .cancelled:
                self.cancelSafetyCheck()
            case .refused(let names), .stillRunning(let names):
                var stopped = check
                stopped.waiting = false
                let list = names.joined(separator: ", ")
                stopped.quitNotice = .init(english: "\(list) is still open. Finish its save or quit prompt, then Recheck. No unload or disconnect was attempted.",
                                          chinese: "\(list) 尚未退出。请完成保存或退出提示，然后重新检查。本次未执行卸载或断开。")
                self.safetyCheck = stopped
            }
        }
    }

    public func confirmSafeUnload() {
        guard let check = safetyCheck, check.canProceed, !isBusy else { return }
        cancelSafetyCheck()
        let service = self.service
        let preparation = beginPreparation()
        Task.detached(priority: .userInitiated) { [weak self] in
            switch check.target {
            case .volume(let id):
                let confirmation = service.prepareStopDevelopmentDiskConfirmation(profileID: id)
                await MainActor.run {
                    guard let self, self.finishPreparation(preparation) else { return }
                    guard let confirmation else {
                        self.userNotice = .init(english: "The volume changed. Refresh before unloading.", chinese: "开发卷状态已变化。请刷新后再卸载。")
                        return
                    }
                    self.performWorkbench({ $0.unloadDevelopmentDisk(profileID: id, checkpoint: confirmation) },
                        operationTargetID: self.volumeRows.first { $0.id == id }?.parentDeviceID,
                        profileID: id, actionKind: .unload)
                }
            case .drive(_, let id):
                let confirmation = service.prepareWholeDeviceEjectConfirmation(physicalIdentity: id)
                await MainActor.run {
                    guard let self, self.finishPreparation(preparation) else { return }
                    self.explicitEjectDeviceID = id
                    self.wholeDeviceEjectConfirmation = confirmation?.physicalIdentity == id ? confirmation : nil
                    if self.wholeDeviceEjectConfirmation == nil {
                        self.userNotice = .init(english: "The drive or affected volumes changed. Refresh and try again.", chinese: "硬盘或受影响卷已变化。请刷新后重试。")
                    }
                }
            }
        }
    }

    public func createDevelopmentDisk(deviceID: String, parentDirectory: URL, name: String, capacityGiB: Int,
                                      caseSensitive: Bool, password: String?, startAfterCreation: Bool = false) {
        performWorkbench({ service in
            let created = service.createDevelopmentDisk(deviceID: deviceID, parentDirectory: parentDirectory, name: name,
                capacityGiB: capacityGiB, caseSensitive: caseSensitive, password: password)
            guard created.succeeded, startAfterCreation else { return created }
            let started = service.startDevelopmentDisk(password: password)
            return OperationResult(operationID: started.operationID, mode: started.mode,
                steps: created.steps + started.steps, failure: started.failure)
        })
    }

    public func adoptDevelopmentDisk(deviceID: String, imageURL: URL) {
        guard !isBusy, !isPreviewFixture, let device = workbench.devices.first(where: {
            $0.id == deviceID && $0.identityVerified && $0.isVirtual == false
        }) else { return }
        selectObservedAdoptionTarget(device)
        performWorkbench({ service in
            service.selectSectoriumDevice(device.id, observedBSDName: device.bsdName, observedDevice: device)
            return service.adoptDevelopmentDisk(deviceID: device.id, imageURL: imageURL)
        }, operationTargetID: device.id)
    }
    public func adoptConfiguredLegacyDevelopmentDisk(deviceID: String) {
        guard !isBusy, !isPreviewFixture, let device = workbench.devices.first(where: {
            $0.id == deviceID && $0.identityVerified && $0.isVirtual == false
        }), let legacy = legacyDevelopmentByDevice[deviceID], legacy.state != .unknown else { return }
        selectObservedAdoptionTarget(device)
        performWorkbench({ service in
            service.selectSectoriumDevice(device.id, observedBSDName: device.bsdName, observedDevice: device)
            return service.adoptConfiguredLegacyDevelopmentDisk(deviceID: device.id)
        }, operationTargetID: device.id)
    }

    /// A verified legacy row can appear before the full refresh chooses a default
    /// drive. Retain the clicked parent immediately; service binding and fresh
    /// adoption checks stay on the background operation, never on the UI thread.
    private func selectObservedAdoptionTarget(_ device: SectoriumPhysicalDevice) {
        cancelSafetyCheck()
        explicitEjectDeviceID = nil
        wholeDeviceEjectConfirmation = nil
        stopConfirmation = nil
        canBeginWholeDeviceEject = false
        canContinueWholeDeviceEject = false
        canReturnFromWholeDeviceEject = false
        invalidateCounterSample(clearReading: true)
        let profiles = workbench.profiles.filter { $0.deviceID == device.id }
        workbench = .init(devices: workbench.devices, selectedDeviceID: device.id,
            profiles: workbench.profiles, selectedProfileID: profiles.count == 1 ? profiles.first?.id : nil,
            readiness: workbench.pendingOperation.map(SectoriumWorkbenchReadiness.operationInProgress) ?? .connected,
            pendingOperation: workbench.pendingOperation,
            io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
            operationSteps: workbench.operationSteps, safeToUnplug: false)
    }
    public func startDevelopmentDisk(password: String? = nil) {
        performWorkbench({ $0.startDevelopmentDisk(password: password) })
    }
    public func prepareStopDevelopmentDiskConfirmation() {
        guard !isBusy, !isPreviewFixture else { return }
        let preparation = beginPreparation()
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let confirmation = service.prepareStopDevelopmentDiskConfirmation()
            await MainActor.run {
                guard let self, self.finishPreparation(preparation) else { return }
                self.stopConfirmation = confirmation
                if confirmation == nil { self.lastResult = "Mounted image identity could not be verified for Stop" }
            }
        }
    }
    public func cancelStopConfirmation() { stopConfirmation = nil }
    public func stopDevelopmentDisk(knownWritersClosed: Bool) {
        guard let confirmation = stopConfirmation else { return }
        stopConfirmation = nil
        performWorkbench({ $0.stopDevelopmentDisk(checkpoint: confirmation, knownWritersClosed: knownWritersClosed) })
    }
    public func ejectSelectedExternalDevice() { prepareWholeDeviceEjectConfirmation() }

    /// Separate windows retain separate selections while sharing one service instance.
    /// An initial eject stays bound to the visible drive; recovery stays bound to the
    /// durable journal target even if another drive is now selected.
    func acceptsWholeDeviceEjectConfirmation(_ confirmation: SectoriumWholeDeviceEjectConfirmation?,
                                             requestedDeviceID: String) -> Bool {
        guard let confirmation else { return false }
        guard confirmation.physicalIdentity == requestedDeviceID else { return false }
        if confirmation.isContinuation {
            return workbench.pendingOperation?.hasPrefix("eject:") == true
                && pendingWholeDeviceEjectTargetID == requestedDeviceID
        }
        return (explicitEjectDeviceID ?? workbench.selectedDeviceID) == requestedDeviceID
    }

    public func prepareWholeDeviceEjectConfirmation() {
        guard !isBusy, !isPreviewFixture, workbench.pendingOperation == nil,
              let selectedID = workbench.selectedDeviceID,
              workbench.devices.contains(where: { $0.id == selectedID && $0.isExternal
                  && $0.isVirtual == false && $0.identityVerified }) else { return }
        let preparation = beginPreparation()
        wholeDeviceEjectConfirmation = nil
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let confirmation = service.prepareWholeDeviceEjectConfirmation(physicalIdentity: selectedID)
            await MainActor.run {
                guard let self, self.finishPreparation(preparation) else { return }
                let matchesSelection = self.acceptsWholeDeviceEjectConfirmation(
                    confirmation, requestedDeviceID: selectedID)
                self.wholeDeviceEjectConfirmation = matchesSelection ? confirmation : nil
                if !matchesSelection { self.lastResult = "Target or complete affected-member scope could not be verified" }
            }
        }
    }
    public func prepareContinueWholeDeviceEjectConfirmation() {
        guard !isBusy, !isPreviewFixture, workbench.pendingOperation?.hasPrefix("eject:") == true,
              let recoveryID = pendingWholeDeviceEjectTargetID else { return }
        let preparation = beginPreparation()
        wholeDeviceEjectConfirmation = nil
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let confirmation = service.prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: recoveryID)
            await MainActor.run {
                guard let self, self.finishPreparation(preparation) else { return }
                let matchesSelection = self.acceptsWholeDeviceEjectConfirmation(
                    confirmation, requestedDeviceID: recoveryID)
                if matchesSelection, confirmation?.isObservationOnly == true {
                    // Read-only final-state reconciliation is automatic; no second
                    // user confirmation or replay of the physical eject is needed.
                    self.needsConnectionRefresh = true
                    self.startPendingConnectionRefresh()
                    return
                }
                self.wholeDeviceEjectConfirmation = matchesSelection ? confirmation : nil
                if !matchesSelection { self.lastResult = "Interrupted physical eject no longer matches its durable recovery journal" }
            }
        }
    }
    public func cancelWholeDeviceEjectConfirmation() { wholeDeviceEjectConfirmation = nil; explicitEjectDeviceID = nil }
    public func confirmWholeDeviceEject() {
        guard let confirmation = wholeDeviceEjectConfirmation,
              acceptsWholeDeviceEjectConfirmation(confirmation,
                  requestedDeviceID: confirmation.physicalIdentity) else {
            wholeDeviceEjectConfirmation = nil
            userNotice = .init(english: "The drive or pending operation changed. Refresh before trying again.",
                               chinese: "硬盘或待完成操作已变化，请刷新后重试。")
            return
        }
        wholeDeviceEjectConfirmation = nil
        explicitEjectDeviceID = nil
        performWorkbench({ $0.ejectExternalDevice(physicalIdentity: confirmation.physicalIdentity,
            confirmation: confirmation) }, wholeDeviceEjectTargetID: confirmation.physicalIdentity, actionKind: .disconnect)
    }

    public func resumePendingOperation() {
        let action: SectoriumCommandAction = workbench.pendingOperation?.hasPrefix("unload:") == true
            ? .unload : workbench.pendingOperation?.hasPrefix("start:") == true ? .load : .other
        performWorkbench({ $0.resumePendingSectoriumOperation() }, actionKind: action)
    }
    public func returnToDevelopment() {
        guard let recoveryID = Self.ejectRecoveryTarget(selectedDeviceID: workbench.selectedDeviceID,
            pendingOperation: workbench.pendingOperation,
            pendingEjectTargetID: pendingWholeDeviceEjectTargetID) else { return }
        performWorkbench({ $0.returnToDevelopment(physicalIdentity: recoveryID) },
            operationTargetID: recoveryID)
    }

    private func performWorkbench(_ action: @escaping @Sendable (HESectoriumService) -> OperationResult,
                                  wholeDeviceEjectTargetID: String? = nil,
                                  operationTargetID: String? = nil,
                                  profileID: String? = nil, actionKind: SectoriumCommandAction = .other) {
        guard !isBusy, !isPreviewFixture, !registryUnavailable else { return }
        verifiedEjectDeviceID = nil
        safeToUnplugDriveName = nil
        userNotice = nil
        verifiedVolumeCommandNotice = nil
        activeWorkbenchAction = actionKind
        isBusy = true
        let service = self.service
        let ejectName = wholeDeviceEjectTargetID.flatMap { target in
            workbench.devices.first { $0.id == target }?.name
                ?? volumeRows.first { $0.parentDeviceID == target }?.parentName
        }
        let selectedID = workbench.selectedDeviceID
        let selectedProfileID = workbench.selectedProfileID
        observationGeneration &+= 1
        let token = UUID()
        activeWorkbenchOperationToken = token
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = action(service)
            let pending = service.pendingSectoriumOperation()
            await MainActor.run {
                guard let self, self.activeWorkbenchOperationToken == token else { return }
                self.activeWorkbenchOperationToken = nil
                // The actual operation has finished. Do not keep a global busy
                // indicator through another uncached traversal of every drive.
                // Revoke old action permissions and let the one cached observation
                // publish inventory and each registered volume progressively.
                let recoveryProfileID = result.steps.first { step in
                    step.status == .succeeded
                        && ((actionKind == .unload && step.step == "verifyDevelopmentVolumeUnloaded")
                            || (actionKind == .load && step.step == "validateMountedChain"))
                        && self.volumeRows.contains { $0.id == step.detail }
                }?.detail
                let completedProfileID = profileID ?? recoveryProfileID
                let target = wholeDeviceEjectTargetID ?? operationTargetID
                    ?? completedProfileID.flatMap { id in self.volumeRows.first { $0.id == id }?.parentDeviceID } ?? selectedID
                self.completedWorkbenchAction = (result, wholeDeviceEjectTargetID, target, ejectName, completedProfileID, actionKind)
                let resultText = result.failure.map { "Failed: \($0)" } ?? "Completed"
                self.lastResult = target.map { "Physical drive \($0): \(resultText)" } ?? resultText
                let targetDisconnected = self.volumeRows.contains {
                    $0.parentDeviceID == target && !$0.parentConnected && $0.verifiedLoaded == false
                }
                self.userNotice = result.succeeded || targetDisconnected ? nil : .operation(result, observed: false)
                let published = self.publishVerifiedCommandCompletion(result: result, action: actionKind,
                    profileID: completedProfileID, deviceID: target, name: ejectName, pending: pending)
                if published {
                    self.completedWorkbenchAction = nil
                } else {
                    // An unknown or failed outcome revokes its target, not every
                    // other drive. Its later observation may resolve the state.
                    self.volumeRows = self.volumeRows.map { row in
                        guard row.parentDeviceID == target,
                              row.parentConnected || row.verifiedLoaded != false else { return row }
                        return Self.unverified(row)
                    }
                    self.workbench = .init(devices: self.workbench.devices,
                        selectedDeviceID: selectedID, profiles: self.workbench.profiles,
                        selectedProfileID: selectedProfileID, readiness: self.workbench.readiness,
                        pendingOperation: pending, operationSteps: result.steps)
                }
                self.needsConnectionRefresh = true
                self.finishOperationObservation()
            }
        }
    }

    /// The native action has already verified its postcondition. Publish that
    /// receipt now; unrelated service, internal-drive and document reads may follow.
    @discardableResult
    func publishVerifiedCommandCompletion(result: OperationResult, action: SectoriumCommandAction,
        profileID: String?, deviceID: String?, name: String?, pending: String?) -> Bool {
        guard action.isVerified(by: result, pending: pending), let deviceID else { return false }
        if action == .disconnect {
            volumeRows = volumeRows.map { $0.parentDeviceID == deviceID ? Self.disconnected($0) : $0 }
            recordVerifiedEjection(deviceID: deviceID, name: name)
        } else {
            guard let profileID, let index = volumeRows.firstIndex(where: { $0.id == profileID }),
                  volumeRows[index].parentDeviceID == deviceID, volumeRows[index].parentConnected else { return false }
            let row = volumeRows[index], loaded = action == .load
            volumeRows[index] = .init(profile: row.profile, parentDeviceID: row.parentDeviceID,
                parentName: row.parentName, isExternal: row.isExternal, verifiedLoaded: loaded,
                parentConnected: true, canLoad: !loaded && row.profile.hasVerifiedImageFormat,
                canUnloadOnly: loaded, canSafeUnloadAndEject: false, isBusy: false,
                importantDocumentURL: nil, documentationPending: row.documentationPending,
                documentHistory: row.documentHistory, capacityChangeUnavailableReason: row.capacityChangeUnavailableReason)
        }
        userNotice = action.success
        verifiedVolumeCommandNotice = action == .disconnect ? nil : (deviceID, action.success)
        let safe = action == .disconnect
        let readiness: SectoriumWorkbenchReadiness = safe ? .ejected : action == .load ? .ready : .notStarted
        workbench = .init(devices: safe ? workbench.devices.filter { $0.id != deviceID } : workbench.devices,
            selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: workbench.selectedProfileID,
            readiness: workbench.selectedDeviceID == deviceID ? readiness : workbench.readiness,
            pendingOperation: pending, io: workbench.io, operationSteps: result.steps, safeToUnplug: safe)
        return true
    }

    private func publishCompletedWorkbenchAction(devices: [SectoriumPhysicalDevice]?, pending: String?) {
        guard let completion = completedWorkbenchAction else { return }
        completedWorkbenchAction = nil
        let absent = completion.target.map { target in
            if let profile = workbench.profiles.first(where: { $0.deviceID == target }) {
                return Self.parentPresence(profile: profile, devices: devices) == false
            }
            return devices.map { observed in
                !observed.contains { $0.id == target }
                    && !observed.contains { !$0.identityVerified && !$0.isInternalConfirmed && $0.isVirtual != true }
            } == true
        } == true
        let safe = completion.ejectTarget != nil
            && SectoriumCommandAction.disconnect.isVerified(by: completion.result, pending: pending)
            && (absent || verifiedEjectDeviceID == completion.ejectTarget)
        if safe {
            recordVerifiedEjection(deviceID: completion.ejectTarget, name: completion.name)
            userNotice = .init(english: "Drive disconnected safely. You can unplug it.", chinese: "硬盘已安全断开，可以拔出。")
        } else if absent {
            userNotice = .init(english: "The drive is disconnected. The previous operation result is retained.",
                chinese: "硬盘已断开，已保留此前操作结果。")
        } else {
            userNotice = .operation(completion.result,
                observed: devices != nil && volumeRows.filter { row in
                    completion.profileID.map { $0 == row.id } ?? (row.parentDeviceID == completion.target)
                }.allSatisfy { $0.verifiedLoaded != nil })
        }
        workbench = .init(devices: workbench.devices, selectedDeviceID: workbench.selectedDeviceID,
            profiles: workbench.profiles, selectedProfileID: workbench.selectedProfileID,
            readiness: workbench.readiness, pendingOperation: pending, io: workbench.io,
            operationSteps: completion.result.steps, safeToUnplug: safe)
    }

    func recordVerifiedEjection(deviceID: String?, name: String?) {
        verifiedEjectDeviceID = deviceID
        verifiedEjectBSDName = workbench.devices.first { $0.id == deviceID }?.bsdName
        safeToUnplugDriveName = name
    }

    public func mountDEV() { perform { service in
        let result = service.mountDEV()
        return result.failure.map { "Failed: \($0)" } ?? "Completed"
    } }
    public func safeEjectHE() { perform { service in
        let result = service.safeEjectHE()
        return result.failure.map { "Failed: \($0)" } ?? "Completed"
    } }
    public func installRepair() { performInstall(.repair) }
    public func install() { performInstall(.install) }
    public func setAutomation(_ enabled: Bool) {
        guard !isBusy, !isPreviewFixture else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = service.setAutomationEnabled(enabled)
            let status = service.refreshStatus()
            await MainActor.run {
                guard let self else { return }
                defer { self.finishOperationObservation() }
                self.isBusy = false
                guard self.observationGeneration == generation else { return }
                self.lastResult = result.summary
                self.userNotice = result.succeeded
                    ? .init(english: "Background loading settings were saved. The service state is shown in details.", chinese: "后台加载设置已保存；实际服务状态见详情。")
                    : .init(english: "Background loading could not be changed. Your volume settings remain unchanged; review the diagnostics.", chinese: "后台加载设置未能更改。开发卷设置未改变，请查看诊断。")
                self.snapshot = status
                self.hasObservedStatus = true
            }
        }
    }

    private func perform(_ action: @escaping @Sendable (HESectoriumService) -> String) {
        guard !isBusy, !isPreviewFixture else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = action(service)
            let status = service.refreshStatus()
            await MainActor.run {
                guard let self else { return }
                defer { self.finishOperationObservation() }
                self.isBusy = false
                guard self.observationGeneration == generation else { return }
                self.lastResult = result
                self.snapshot = status
                self.hasObservedStatus = true
            }
        }
    }

    private func performInstall(_ action: HESectoriumInstallAction) {
        guard !isBusy, !isPreviewFixture else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let token = UUID()
        activeInstallOperationToken = token
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = service.installRepair(action)
            await MainActor.run {
                guard let self, self.activeInstallOperationToken == token else { return }
                self.activeInstallOperationToken = nil
                self.lastResult = result.summary
                self.userNotice = result.succeeded
                    ? .init(english: "Components are ready. This does not load or eject a development volume.", chinese: "组件已准备好；此操作不会加载或弹出开发卷。")
                    : .init(english: "Component setup did not finish. Review the diagnostics before trying again.", chinese: "组件配置未完成。请查看诊断后重试。")
                // The installer receipt is final even if native disk events or
                // navigation changed the passive observation generation. Optional
                // service/disk checks follow without holding the operation spinner.
                self.hasObservedStatus = false
                self.needsConnectionRefresh = true
                self.finishOperationObservation()
            }
        }
    }
}

#if DEBUG
private final class SectoriumPreviewNoCommands: HESectoriumCommandRunning, SectoriumDeviceObserving, SectoriumDeviceIOCounterSampling {
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        .init(exitCode: 126, detail: "Synthetic preview: commands are disabled")
    }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { [] }
    func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters? { nil }
}
#endif
