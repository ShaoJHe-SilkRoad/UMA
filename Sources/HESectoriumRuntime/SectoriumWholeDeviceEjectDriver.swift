import Foundation
import HESectoriumCore

public struct SectoriumWholeDeviceEjectConfirmation: Identifiable, Equatable, Sendable {
    public let id: String
    public let physicalIdentity: String
    public let bsdName: String
    public let memberKey: String
    public let affectedMembers: [String]
    public let attachedImageIdentities: [String]
    public let observedAt: Date
    public let dependenciesCanFinishOffTarget: Bool
    public let isContinuation: Bool
    public let isObservationOnly: Bool

    public init(topology: WholeDeviceTopology, observedAt: Date = Date(), dependenciesCanFinishOffTarget: Bool,
                isContinuation: Bool = false, isObservationOnly: Bool = false) {
        id = UUID().uuidString
        physicalIdentity = topology.physicalIdentity
        bsdName = topology.bsdName
        memberKey = topology.memberKey
        affectedMembers = topology.volumes.map(\.identity).sorted()
        attachedImageIdentities = topology.images.filter(\.attached).map(\.identity).sorted()
        self.observedAt = observedAt
        self.dependenciesCanFinishOffTarget = dependenciesCanFinishOffTarget
        self.isContinuation = isContinuation
        self.isObservationOnly = isObservationOnly
    }

    /// The freshness window is bound to the observation shown to the user. Confirming later
    /// cannot renew an old topology snapshot by substituting the click time.
    public func checkpoint(knownWritersClosed: Bool, confirmedAt: Date? = nil) -> WholeDeviceEjectCheckpoint {
        .init(confirmedExactTargetAndScope: true, knownWritersClosed: knownWritersClosed,
              dependenciesCanFinishOffTarget: dependenciesCanFinishOffTarget,
              confirmedPhysicalIdentity: physicalIdentity, confirmedMemberKey: memberKey,
              confirmedAt: confirmedAt ?? observedAt)
    }
}

/// The whole-device bridge uses the existing injected device observer and command runner.
/// It reads hdiutil's attached-image metadata in memory to map image entities to a configured
/// physical volume. Paths are neither persisted nor returned; journal identities use attached
/// virtual BSD names. No directory contents or process/open-file inventory is read.
public final class SectoriumWholeDeviceEjectDriver: WholeDeviceEjectDriving {
    private static let actionTimeout: TimeInterval = 120
    private let observer: SectoriumDeviceObserving
    private let runner: HESectoriumCommandRunning
    private let cwd: URL
    private let independentReturnValidator: (WholeDeviceEjectJournalRecord) -> Bool
    private let independentLoadedReturnValidator: (WholeDeviceEjectJournalRecord) -> Bool
    private let independentContinuationValidator: (WholeDeviceEjectJournalRecord) -> Bool
    private var imageWholeDiskByIdentity: [String: String] = [:]
    private var imageVolumesByIdentity: [String: Set<String>] = [:]

    public init(observer: SectoriumDeviceObserving, runner: HESectoriumCommandRunning,
                workingDirectory: URL,
                independentReturnValidator: @escaping (WholeDeviceEjectJournalRecord) -> Bool = { _ in false },
                independentLoadedReturnValidator: @escaping (WholeDeviceEjectJournalRecord) -> Bool = { _ in false },
                independentContinuationValidator: @escaping (WholeDeviceEjectJournalRecord) -> Bool = { _ in false }) {
        self.observer = observer; self.runner = runner; self.cwd = workingDirectory
        self.independentReturnValidator = independentReturnValidator
        self.independentLoadedReturnValidator = independentLoadedReturnValidator
        self.independentContinuationValidator = independentContinuationValidator
    }

    public func observe(physicalIdentity: String) -> WholeDeviceTopology? {
        withObservation { observeTopology(physicalIdentity: physicalIdentity) }
    }

    private func withObservation<T>(_ body: () -> T) -> T {
        if let scoped = runner as? SectoriumObservationCommandRunner {
            return scoped.withObservation(body)
        }
        return body()
    }

    private func observeTopology(physicalIdentity: String) -> WholeDeviceTopology? {
        guard let devices = try? observer.observeDevices(),
              let matches = Optional(devices.filter { $0.id == physicalIdentity }), matches.count == 1,
              let device = matches.first, device.isVirtual == false, device.identityVerified, device.topologyComplete,
              device.isExternal, !device.volumeMembers.isEmpty,
              Set(device.volumeMembers.map(\.volumeUUID)).count == device.volumeMembers.count,
              let systemRoots = systemPhysicalRoots(),
              let targetRoots = SectoriumPhysicalBackingResolver(runner: runner, cwd: cwd).physicalRoots(forDevice: device.bsdName),
              !targetRoots.isEmpty, systemRoots.isDisjoint(with: targetRoots),
              let imageInventory = attachedImages(for: device, among: devices) else { return nil }
        let members = device.volumeMembers.map {
            WholeDeviceTopology.Volume(identity: "\($0.volumeUUID.uuidString.lowercased())|\($0.bsdName)", mounted: $0.mounted)
        }
        let topology = WholeDeviceTopology(physicalIdentity: device.id, bsdName: device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: members, images: imageInventory)
        return topology.hasUniqueMembers ? topology : nil
    }

    public func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String],
                                             from target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        guard let expected = imageVolumesByIdentity[imageIdentity], Set(volumeIdentities) == expected,
              let fresh = observe(physicalIdentity: target.physicalIdentity),
              target.matchesPhysicalIdentityAndVolumes(fresh),
              Set(fresh.images.map(\.identity)).contains(imageIdentity),
              let currentImage = fresh.images.first(where: { $0.identity == imageIdentity }),
              currentImage.attached else { return .failed("attached image identity or volume inventory changed") }
        var completed: [String] = []
        let mounted = currentImage.mountedVolumeIdentities ?? currentImage.volumeIdentities
        for identity in mounted {
            guard expected.contains(identity), let bsd = memberBSDName(identity),
                  bsd.range(of: #"^disk[0-9]+(?:s[0-9]+)+$"#, options: .regularExpression) != nil else {
                return .failed("attached image volume identity is malformed")
            }
            guard let outcome = runBoundedDiskAction(["unmount", "/dev/\(bsd)"]) else {
                return completed.isEmpty ? .failed("bounded action runner is unavailable")
                    : .partial("image-volume unmount runner became unavailable", completedMembers: completed)
            }
            guard outcome.exitCode == 0 else {
                let receipt = actionReceipt(outcome)
                return completed.isEmpty ? receipt
                    : .partial("image-volume unmount stopped after \(completed.count) success(es): \(receipt)",
                                completedMembers: completed)
            }
            completed.append(identity)
        }
        return .completed("all \(completed.count) observed image volume(s) unmounted without force")
    }

    public func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        guard let wholeDisk = imageWholeDiskByIdentity[imageIdentity],
              wholeDisk.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              let fresh = observe(physicalIdentity: target.physicalIdentity),
              target.matchesPhysicalIdentityAndVolumes(fresh),
              let image = fresh.images.first(where: { $0.identity == imageIdentity }), image.attached,
              (image.mountedVolumeIdentities ?? image.volumeIdentities).isEmpty else {
            return .failed("image attachment or unmounted postcondition changed before detach")
        }
        guard let outcome = runBoundedImageAction(["detach", "/dev/\(wholeDisk)"]) else {
            return .failed("bounded image detach runner is unavailable")
        }
        return actionReceipt(outcome)
    }

    public func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        guard let fresh = observe(physicalIdentity: target.physicalIdentity),
              target.matchesPhysicalIdentityAndVolumes(fresh), fresh.images.isEmpty else {
            return .failed("physical member inventory changed before unmount")
        }
        var completed: [String] = []
        for member in fresh.volumes where member.mounted {
            guard let bsd = memberBSDName(member.identity),
                  bsd.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil else {
                return .failed("physical member identity is malformed")
            }
            guard let outcome = runBoundedAction(["unmount", "/dev/\(bsd)"]) else {
                return completed.isEmpty ? .failed("bounded action runner is unavailable")
                    : .partial("bounded action runner became unavailable", completedMembers: completed)
            }
            guard outcome.exitCode == 0 else {
                let receipt = actionReceipt(outcome)
                guard !completed.isEmpty else { return receipt }
                return .partial("member \(bsd) stopped after \(completed.count) successful unmount(s): \(receipt)",
                                completedMembers: completed)
            }
            completed.append(member.identity)
        }
        return .completed("all observed physical volumes unmounted without force")
    }

    public func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        guard let fresh = observe(physicalIdentity: target.physicalIdentity), target.matchesPhysicalIdentityAndVolumes(fresh),
              fresh.volumes.allSatisfy({ !$0.mounted }), fresh.images.isEmpty,
              fresh.bsdName.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
            return .failed("target or complete unmounted postcondition changed before eject")
        }
        guard let outcome = runBoundedAction(["eject", "/dev/\(fresh.bsdName)"]) else {
            return .failed("bounded action runner is unavailable")
        }
        return actionReceipt(outcome)
    }

    public func presence(physicalIdentity: String) -> WholeDevicePresence {
        guard let devices = try? observer.observeDevices() else { return .unknown("device inventory unavailable") }
        let matches = devices.filter { $0.id == physicalIdentity }
        if matches.isEmpty { return .unknown("original physical topology is required to verify absence") }
        guard matches.count == 1, matches[0].identityVerified else { return .unknown("physical identity is ambiguous") }
        return .present
    }

    /// A catalog ID can disappear while the same physical media remains connected with
    /// unverified identity (for example, a single-volume anchor gains another member).
    /// Only a complete fresh inventory with no plausible old media may report absence.
    public func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        withObservation { observePresence(of: target) }
    }

    public func successfulEjectHasUnmountedPostcondition(of target: WholeDeviceTopology) -> Bool {
        withObservation {
            guard let current = observeTopology(physicalIdentity: target.physicalIdentity),
                  target.matchesPhysicalIdentityAndVolumes(current), current.hasUniqueMembers,
                  current.volumes.allSatisfy({ !$0.mounted }), current.images.isEmpty else { return false }
            return true
        }
    }

    private func observePresence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        guard target.isWholeDevice, target.isExternal, !target.isSystemDevice,
              target.inventoryComplete, target.hasUniqueMembers,
              let originalUUIDs = Self.physicalMemberUUIDs(target) else {
            return .unknown("target identity is unavailable")
        }
        // A complete native list containing no external physical media proves
        // this external target is gone. Do not inspect every internal APFS volume
        // (or wait for their unavailable identity) after a successful OS eject.
        // A failed, malformed or nonempty result needs the full identity path.
        let external = runner.run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"], cwd: cwd)
        if external.succeeded, let root = Self.plist(external.detail),
           let rows = root["AllDisksAndPartitions"] as? [[String: Any]], rows.isEmpty,
           (root["AllDisks"] == nil || (root["AllDisks"] as? [String])?.isEmpty == true) {
            return .absent
        }
        guard let devices = try? observer.observeDevices() else {
            return .unknown("target or device inventory is unavailable")
        }
        let exact = devices.filter { $0.id == target.physicalIdentity }
        if !exact.isEmpty {
            guard exact.count == 1, exact[0].identityVerified, exact[0].isVirtual == false else {
                return .unknown("physical identity is ambiguous")
            }
            return .present
        }
        for device in devices {
            let observedUUIDs = Set(device.volumeMembers.map(\.volumeUUID)).union(device.volumeUUIDs)
            if device.bsdName == target.bsdName || !observedUUIDs.isDisjoint(with: originalUUIDs) {
                return .unknown("possible original physical media remains connected")
            }
            if device.isVirtual != true && !device.identityVerified
                && (device.isExternal || !device.topologyComplete) {
                // Apple internal storage may have no stable media identity. Its unrelated
                // incomplete APFS catalog must not hold an external eject open forever.
                // Require native Internal evidence; an unknown location still fails closed.
                let info = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/" + device.bsdName], cwd: cwd)
                guard !device.isExternal, info.succeeded, let row = Self.plist(info.detail),
                      row["Internal"] as? Bool == true,
                      (row["DeviceLocation"] as? String)?.lowercased() != "external",
                      row["DeviceIdentifier"] as? String == device.bsdName else {
                    return .unknown("unverified physical media prevents absence confirmation")
                }
            }
        }
        guard Self.completeWholeDiskInventory(devices, runner: runner, workingDirectory: cwd) else {
            return .unknown("whole-disk inventory is incomplete or changed")
        }
        return .absent
    }

    public func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        withObservation { observeReturnIdentityMatches(journal) }
    }

    private func observeReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        let current = observe(physicalIdentity: journal.target.physicalIdentity)
            ?? (journal.canCancelUnissuedEject ? freshUnissuedCancellationTopology(journal) : nil)
        guard let current,
              current.volumes.allSatisfy(\.mounted) else { return false }
        if journal.canCancelUnissuedEject {
            guard journal.target.canCancelUnissuedEject(on: current),
                  current.images.allSatisfy({ image in
                      guard image.attached, let mounted = image.mountedVolumeIdentities else { return false }
                      return Set(mounted) == Set(image.volumeIdentities)
                  }) else { return false }
            return independentReturnValidator(journal)
        }
        let reconnectBoundary = journal.safelyEjected || journal.phase == .disconnected
            || journal.issuedEjectCanReconcileRemount
        let physicalIdentityMatches = reconnectBoundary
            ? journal.target.matchesStablePhysicalIdentityAndVolumes(current)
            : journal.target.matchesPhysicalIdentityAndVolumes(current)
        guard physicalIdentityMatches else { return false }
        if reconnectBoundary {
            // A new connection can already have been mounted by the user's terminal or
            // the existing automounter. Recognize the exact stable image/APFS chain even
            // when the kernel assigned new disk numbers; never detach it to restore history.
            guard current.images.isEmpty || (sameLoadedImageVolumes(journal.target.images, current.images)
                && independentLoadedReturnValidator(journal)) else { return false }
            return independentReturnValidator(journal)
        }
        let detached = Set(journal.target.images
            .filter { journal.completedSteps.contains("detachImage:\($0.identity)") }.map(\.identity))
        let expected = Dictionary(uniqueKeysWithValues: journal.target.images
            .filter { !detached.contains($0.identity) }
            .map { ($0.identity, Set($0.volumeIdentities)) })
        let allImagesDetached = detached.count == journal.target.images.count
        let recordedDetachBoundary = allImagesDetached
            && (journal.phase == .imagesDetached || journal.safelyEjected)
        let busyImageBoundary: Bool = {
            guard journal.phase == .interrupted, journal.lastIssuedAction == .imageVolumesUnmount,
                  !expected.isEmpty, case .busy? = journal.lastReceipt else { return false }
            return true
        }()
        guard (recordedDetachBoundary && current.images.isEmpty)
                || (busyImageBoundary && current.images.count == expected.count
                    && Set(current.images.map(\.identity)) == Set(expected.keys)
                    && current.images.allSatisfy({ image in
                        guard image.attached, let mounted = image.mountedVolumeIdentities,
                              let volumes = expected[image.identity] else { return false }
                        return Set(image.volumeIdentities) == volumes && Set(mounted) == volumes
                    })) else { return false }
        return independentReturnValidator(journal)
    }

    private func sameLoadedImageVolumes(_ expected: [WholeDeviceTopology.Image],
                                       _ current: [WholeDeviceTopology.Image]) -> Bool {
        func keys(_ images: [WholeDeviceTopology.Image]) -> [String]? {
            var groups: [String] = []
            for image in images {
                guard image.attached, !image.volumeIdentities.isEmpty,
                      let mounted = image.mountedVolumeIdentities,
                      Set(mounted) == Set(image.volumeIdentities) else { return nil }
                let ids = image.volumeIdentities.compactMap { value -> String? in
                    let parts = value.split(separator: "|", omittingEmptySubsequences: false)
                    guard parts.count == 2, let uuid = UUID(uuidString: String(parts[0])) else { return nil }
                    return uuid.uuidString.lowercased()
                }
                guard ids.count == image.volumeIdentities.count, Set(ids).count == ids.count else { return nil }
                groups.append(ids.sorted().joined(separator: ","))
            }
            return Set(groups).count == groups.count ? groups.sorted() : nil
        }
        guard let original = keys(expected), let observed = keys(current) else { return false }
        return original == observed
    }

    public func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        withObservation { observePhysicalContinuationMatches(journal) }
    }

    private func observePhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        guard journal.lastIssuedAction == .physicalVolumesUnmount,
              journal.phase == .interrupted || journal.phase == .physicalVolumesUnmountIssued
                || journal.phase == .physicalVolumesUnmounted,
              journal.target.images.allSatisfy({ journal.completedSteps.contains("detachImage:\($0.identity)") }),
              let current = observe(physicalIdentity: journal.target.physicalIdentity),
              journal.target.matchesPhysicalIdentityAndVolumes(current), current.images.isEmpty else { return false }
        let recordedRows = journal.completedSteps.compactMap { step -> String? in
            guard step.hasPrefix("unmountPhysicalVolume:") else { return nil }
            return String(step.dropFirst("unmountPhysicalVolume:".count))
        }
        let recorded = Set(recordedRows)
        let known = Set(journal.target.volumes.map(\.identity))
        guard recorded.count == recordedRows.count, recorded.isSubset(of: known) else { return false }
        let allRecorded = journal.completedSteps.contains("unmountAllPhysicalVolumes")
        let original = Dictionary(uniqueKeysWithValues: journal.target.volumes.map { ($0.identity, $0.mounted) })
        let reconciled = current.volumes.allSatisfy { volume in
            guard let wasMounted = original[volume.identity] else { return false }
            if allRecorded || recorded.contains(volume.identity) { return !volume.mounted }
            // A request may have taken effect before the process could persist its receipt.
            // Fresh exact identity/member observation lets explicit Continue skip that member.
            // A volume unmounted before the operation must not silently reappear.
            return wasMounted || !volume.mounted
        }
        return reconciled && independentContinuationValidator(journal)
    }

    public func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery {
        withObservation { observeEjectIssuedRecovery(journal) }
    }

    private func observeEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery {
        guard journal.phase == .ejectIssued, journal.lastIssuedAction == .ejectWholeDevice,
              journal.target.isExternal, journal.target.isWholeDevice, !journal.target.isSystemDevice,
              journal.target.inventoryComplete, journal.target.hasUniqueMembers,
              journal.target.images.allSatisfy({ journal.completedSteps.contains("detachImage:\($0.identity)") }),
              journal.completedSteps.contains("unmountAllPhysicalVolumes")
                || journal.target.volumes.allSatisfy({ volume in
                    journal.completedSteps.contains("unmountPhysicalVolume:\(volume.identity)")
                }) else { return .refused }
        switch presence(of: journal.target) {
        case .absent:
            // This is a new observation of identity absence, not a reconstructed OS receipt.
            return .exactTargetAbsent
        case .unknown:
            return .refused
        case .present:
            guard let current = observe(physicalIdentity: journal.target.physicalIdentity),
                  journal.target.matchesPhysicalIdentityAndVolumes(current), current.images.isEmpty,
                  current.volumes.allSatisfy({ !$0.mounted }),
                  independentContinuationValidator(journal) else { return .refused }
            return .exactTargetPresentUnmounted
        }
    }

    /// Read-only recovery of the original unique backing-volume anchor after catalog ID
    /// degradation. This candidate never authorizes unmount, detach, or eject; it is used
    /// solely to cancel a journal proving no action was ever issued.
    public static func freshUnissuedCancellationCandidate(
        journal: WholeDeviceEjectJournalRecord, devices: [SectoriumPhysicalDevice],
        runner: HESectoriumCommandRunning, workingDirectory: URL
    ) -> SectoriumPhysicalDevice? {
        guard journal.canCancelUnissuedEject,
              journal.target.isWholeDevice, journal.target.isExternal, !journal.target.isSystemDevice,
              journal.target.inventoryComplete, journal.target.hasUniqueMembers,
              journal.target.volumes.count == 1,
              let anchor = UUID(uuidString: journal.target.physicalIdentity),
              let originalMember = journal.target.volumes.first,
              let original = physicalMemberIdentity(originalMember.identity),
              original.uuid == anchor,
              original.bsd.hasPrefix(journal.target.bsdName + "s"),
              journal.target.bsdName.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              completeWholeDiskInventory(devices, runner: runner, workingDirectory: workingDirectory) else {
            return nil
        }
        let physical = devices.filter { $0.isVirtual != true }
        let candidates = physical.filter { device in
            device.volumeMembers.contains { $0.volumeUUID == anchor }
        }
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.bsdName == journal.target.bsdName,
              physical.filter({ $0.bsdName == candidate.bsdName }).count == 1,
              candidate.isVirtual == false, candidate.isExternal, candidate.topologyComplete,
              !candidate.hasAmbiguousPhysicalStores,
              !candidate.volumeMembers.isEmpty,
              candidate.volumeMembers.filter({ $0.volumeUUID == anchor }).count == 1,
              candidate.volumeMembers.first(where: { $0.volumeUUID == anchor })?.bsdName == original.bsd,
              Set(candidate.volumeMembers.map(\.volumeUUID)).count == candidate.volumeMembers.count,
              Set(candidate.volumeMembers.map(\.bsdName)).count == candidate.volumeMembers.count,
              candidate.volumeMembers.allSatisfy(\.mounted) else { return nil }
        let resolver = SectoriumPhysicalBackingResolver(runner: runner, cwd: workingDirectory)
        guard let systemRoots = resolver.physicalRoots(forPath: URL(fileURLWithPath: "/")),
              let candidateRoots = resolver.physicalRoots(forDevice: candidate.bsdName),
              !candidateRoots.isEmpty, systemRoots.isDisjoint(with: candidateRoots) else { return nil }
        for member in candidate.volumeMembers {
            guard member.bsdName.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
                  member.bsdName.hasPrefix(candidate.bsdName + "s") else { return nil }
            let result = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(member.bsdName)"],
                                    cwd: workingDirectory)
            guard result.succeeded, let info = plist(result.detail),
                  info["DeviceIdentifier"] as? String == member.bsdName,
                  SectoriumDeviceCatalog.verifiedParentWholeDisk(info) == candidate.bsdName,
                  let rawUUID = (info["VolumeUUID"] as? String) ?? (info["APFSVolumeUUID"] as? String),
                  UUID(uuidString: rawUUID) == member.volumeUUID else { return nil }
        }
        return candidate
    }

    private func freshUnissuedCancellationTopology(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceTopology? {
        guard let devices = try? observer.observeDevices(),
              let candidate = Self.freshUnissuedCancellationCandidate(journal: journal, devices: devices,
                  runner: runner, workingDirectory: cwd),
              let images = attachedImages(for: candidate, among: devices) else { return nil }
        let volumes = candidate.volumeMembers.map {
            WholeDeviceTopology.Volume(identity: "\($0.volumeUUID.uuidString.lowercased())|\($0.bsdName)",
                                       mounted: $0.mounted)
        }
        let current = WholeDeviceTopology(physicalIdentity: journal.target.physicalIdentity,
            bsdName: candidate.bsdName, isWholeDevice: true, isExternal: true, isSystemDevice: false,
            inventoryComplete: true, volumes: volumes, images: images)
        return current.hasUniqueMembers ? current : nil
    }

    private static func physicalMemberUUIDs(_ target: WholeDeviceTopology) -> Set<UUID>? {
        let values = target.volumes.compactMap { physicalMemberIdentity($0.identity)?.uuid }
        guard values.count == target.volumes.count,
              Set(values).count == target.volumes.count else { return nil }
        return Set(values)
    }

    /// The catalog can omit malformed raw rows. An absence or cancellation decision must
    /// reconcile the complete whole-disk list with the parsed rows, not just inspect the
    /// IDs that survived parsing. A changed list between observations is also uncertain.
    private static func completeWholeDiskInventory(_ devices: [SectoriumPhysicalDevice],
                                                   runner: HESectoriumCommandRunning,
                                                   workingDirectory: URL) -> Bool {
        let result = runner.run("/usr/sbin/diskutil", ["list", "-plist"], cwd: workingDirectory)
        guard result.succeeded, let root = plist(result.detail),
              let rows = root["AllDisksAndPartitions"] as? [[String: Any]] else { return false }
        let raw = rows.compactMap { $0["DeviceIdentifier"] as? String }
        let observed = devices.map(\.bsdName)
        guard raw.count == rows.count, Set(raw).count == raw.count,
              raw.allSatisfy({ $0.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil }),
              Set(observed).count == observed.count,
              observed.allSatisfy({ $0.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil }) else {
            return false
        }
        return Set(raw) == Set(observed)
    }

    private static func physicalMemberIdentity(_ identity: String) -> (uuid: UUID, bsd: String)? {
        let parts = identity.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let uuid = UUID(uuidString: String(parts[0])),
              String(parts[1]).range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return (uuid, String(parts[1]))
    }

    private func systemPhysicalRoots() -> Set<String>? {
        SectoriumPhysicalBackingResolver(runner: runner, cwd: cwd)
            .physicalRoots(forPath: URL(fileURLWithPath: "/"))
    }

    private func memberBSDName(_ identity: String) -> String? {
        guard let separator = identity.lastIndex(of: "|") else { return nil }
        return String(identity[identity.index(after: separator)...])
    }

    private func runBoundedAction(_ arguments: [String]) -> CommandOutcome? {
        runBoundedDiskAction(arguments)
    }

    private func runBoundedDiskAction(_ arguments: [String]) -> CommandOutcome? {
        guard let timedRunner = runner as? HESectoriumTimedCommandRunning else { return nil }
        return timedRunner.run("/usr/sbin/diskutil", arguments, cwd: cwd, timeout: Self.actionTimeout)
    }

    private func runBoundedImageAction(_ arguments: [String]) -> CommandOutcome? {
        guard let timedRunner = runner as? HESectoriumTimedCommandRunning else { return nil }
        return timedRunner.run("/usr/bin/hdiutil", arguments, cwd: cwd, timeout: Self.actionTimeout)
    }

    private func attachedImages(for target: SectoriumPhysicalDevice,
                                among devices: [SectoriumPhysicalDevice]) -> [WholeDeviceTopology.Image]? {
        let backingResolver = SectoriumPhysicalBackingResolver(runner: runner, cwd: cwd)
        let targetPhysicalRoots = backingResolver.physicalRoots(forDevice: target.bsdName)

        let result = runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd)
        guard result.exitCode == 0, let root = Self.plist(result.detail),
              let rows = root["images"] as? [[String: Any]],
              let targetPhysicalRoots, !targetPhysicalRoots.isEmpty else { return nil }

        var seenPaths: Set<String> = []
        var mapped: [WholeDeviceTopology.Image] = []
        var wholeDisks: [String: String] = [:]
        var volumeSets: [String: Set<String>] = [:]
        for row in rows {
            guard let rawPath = row["image-path"] as? String,
                  let imagePath = Self.absolutePath(rawPath), seenPaths.insert(imagePath).inserted else { return nil }
            // hdiutil may report a symlink alias whose lexical path is outside a selected
            // mount root. Establish its actual existing filesystem ancestry before exclusion.
            guard let imagePhysicalRoots = backingResolver.physicalRoots(forPath: URL(fileURLWithPath: imagePath)),
                  !imagePhysicalRoots.isEmpty else { return nil }
            if imagePhysicalRoots.isDisjoint(with: targetPhysicalRoots) { continue }
            guard imagePhysicalRoots == targetPhysicalRoots,
                  let entities = row["system-entities"] as? [[String: Any]], !entities.isEmpty else { return nil }
            var nodes: [String] = []
            var imageVolumes: Set<String> = []
            var mountedVolumes: Set<String> = []
            var validMountPoints = true
            var missingImageVolumeIdentities: [(node: String, mount: String?)] = []
            for entity in entities {
                guard let rawNode = entity["dev-entry"] as? String,
                      let node = Self.deviceNode(rawNode) else { return nil }
                nodes.append(node)
                if let rawVolumeUUID = entity["volume-uuid"] as? String
                    ?? entity["volume-UUID"] as? String {
                    guard let uuid = UUID(uuidString: rawVolumeUUID),
                          node.range(of: #"^disk[0-9]+(?:s[0-9]+)+$"#, options: .regularExpression) != nil else { return nil }
                    let volume = "\(uuid.uuidString.lowercased())|\(node)"
                    guard imageVolumes.insert(volume).inserted else { return nil }
                    if let mount = entity["mount-point"] as? String {
                        guard Self.absolutePath(mount) != nil else { validMountPoints = false; continue }
                        mountedVolumes.insert(volume)
                    }
                } else if node.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil {
                    let mount = entity["mount-point"] as? String
                    if let mount, Self.absolutePath(mount) == nil {
                        validMountPoints = false; continue
                    }
                    missingImageVolumeIdentities.append((node, mount))
                } else if entity["mount-point"] != nil {
                    validMountPoints = false
                }
            }
            guard validMountPoints, Set(nodes).count == nodes.count else { return nil }
            let wholeNodes = nodes.filter { $0.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil }
            guard let wholeDisk = verifiedImageWholeDisk(wholeNodes, entityNodes: Set(nodes)) else { return nil }
            let synthesizedWholeDisks = wholeNodes.filter { $0 != wholeDisk }
            var recoveredAPFSVolume = false
            for missing in missingImageVolumeIdentities {
                let belongsToSynthesized = synthesizedWholeDisks.contains { missing.node.hasPrefix($0 + "s") }
                if !belongsToSynthesized && missing.mount == nil { continue }
                guard let uuid = verifiedAPFSImageVolume(missing.node, mount: missing.mount,
                    imageWholeDisk: wholeDisk, entityNodes: Set(nodes)),
                    imageVolumes.insert("\(uuid.uuidString.lowercased())|\(missing.node)").inserted else { return nil }
                recoveredAPFSVolume = true
                if missing.mount != nil {
                    mountedVolumes.insert("\(uuid.uuidString.lowercased())|\(missing.node)")
                }
            }

            let virtualMatches = devices.filter { $0.bsdName == wholeDisk }
            guard virtualMatches.count == 1, let virtual = virtualMatches.first,
                  virtual.isVirtual == true,
                  (recoveredAPFSVolume
                    ? !imageVolumes.isEmpty
                    : virtual.topologyComplete && Set(virtual.volumeMembers.map {
                        "\($0.volumeUUID.uuidString.lowercased())|\($0.bsdName)"
                    }) == imageVolumes) else { return nil }
            let identity = "image:\(wholeDisk)"
            let image = WholeDeviceTopology.Image(identity: identity, attached: true,
                volumeIdentities: imageVolumes.sorted(), mountedVolumeIdentities: mountedVolumes.sorted())
            mapped.append(image)
            wholeDisks[identity] = wholeDisk
            volumeSets[identity] = imageVolumes
        }
        imageWholeDiskByIdentity = wholeDisks
        imageVolumesByIdentity = volumeSets
        return mapped.sorted { $0.identity < $1.identity }
    }

    private func verifiedImageWholeDisk(_ wholeNodes: [String], entityNodes: Set<String>) -> String? {
        guard !wholeNodes.isEmpty, Set(wholeNodes).count == wholeNodes.count else { return nil }
        if wholeNodes.count == 1 { return wholeNodes[0] }
        let result = runner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], cwd: cwd)
        guard result.succeeded, let root = Self.plist(result.detail),
              let containers = root["Containers"] as? [[String: Any]] ?? root["APFSContainers"] as? [[String: Any]] else { return nil }
        let candidates = wholeNodes.filter { candidate in
            wholeNodes.filter { $0 != candidate }.allSatisfy { child in
                let matches = containers.filter { $0["ContainerReference"] as? String == child }
                guard matches.count == 1,
                      let stores = matches[0]["PhysicalStores"] as? [[String: Any]], stores.count == 1,
                      let rawStore = stores[0]["DeviceIdentifier"] as? String ?? stores[0]["DeviceNode"] as? String,
                      let store = Self.deviceNode(rawStore) else { return false }
                return store.hasPrefix(candidate + "s") && entityNodes.contains(store)
            }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// hdiutil may omit APFS volume UUIDs. Recover them only through a unique
    /// diskutil volume -> APFS container -> image physical-store chain.
    private func verifiedAPFSImageVolume(_ node: String, mount: String?,
                                         imageWholeDisk: String, entityNodes: Set<String>) -> UUID? {
        let volumeResult = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(node)"], cwd: cwd)
        let apfsResult = runner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], cwd: cwd)
        guard volumeResult.succeeded, apfsResult.succeeded,
              node.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
              let info = Self.plist(volumeResult.detail),
              info["DeviceIdentifier"] as? String == node,
              (mount.map { info["MountPoint"] as? String == $0 }
                ?? ((info["MountPoint"] as? String)?.isEmpty != false)),
              let rawUUID = info["VolumeUUID"] as? String ?? info["APFSVolumeUUID"] as? String,
              let uuid = UUID(uuidString: rawUUID),
              let containerID = info["APFSContainerReference"] as? String,
              entityNodes.contains(containerID),
              let apfs = Self.plist(apfsResult.detail),
              let containers = apfs["Containers"] as? [[String: Any]] ?? apfs["APFSContainers"] as? [[String: Any]] else { return nil }
        let matches = containers.filter { $0["ContainerReference"] as? String == containerID }
        guard matches.count == 1, let stores = matches.first?["PhysicalStores"] as? [[String: Any]],
              stores.count == 1,
              let rawStore = stores[0]["DeviceIdentifier"] as? String ?? stores[0]["DeviceNode"] as? String,
              let store = Self.deviceNode(rawStore),
              store.hasPrefix(imageWholeDisk + "s"), entityNodes.contains(store) else { return nil }
        return uuid
    }

    private static func absolutePath(_ raw: String) -> String? {
        guard raw.hasPrefix("/"), !raw.contains("\0"),
              !raw.split(separator: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }

    private static func deviceNode(_ raw: String) -> String? {
        let node = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
        guard node.range(of: #"^disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        return node
    }

    private func actionReceipt(_ outcome: CommandOutcome) -> WholeDeviceActionReceipt {
        guard outcome.exitCode == 0 else {
            let detail = String(outcome.detail.prefix(240))
            if detail.localizedCaseInsensitiveContains("busy") || detail.localizedCaseInsensitiveContains("in use") {
                return .busy(detail)
            }
            if detail.localizedCaseInsensitiveContains("dissenter") { return .dissenter(detail) }
            return .failed("exit=\(outcome.exitCode): \(detail)")
        }
        return .completed(String(outcome.detail.prefix(240)))
    }

    private static func plist(_ text: String) -> [String: Any]? {
        guard let start = text.range(of: "<?xml") ?? text.range(of: "<plist"),
              let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex),
              let data = String(text[start.lowerBound..<end.upperBound]).data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}

/// A truthful dependency check. If any coordination, state, log or current-directory path
/// cannot be resolved by the fixture-backed volume query, or resides on the target, refuse.
public enum SectoriumOffTargetDependencyCheck {
    public static func canFinishOffTarget(paths: HESectoriumPaths, targetBSDName: String,
                                           runner: HESectoriumCommandRunning) -> Bool {
        if let scoped = runner as? SectoriumObservationCommandRunner {
            return scoped.withObservation { observeDependencies(paths: paths, targetBSDName: targetBSDName, runner: runner) }
        }
        return observeDependencies(paths: paths, targetBSDName: targetBSDName, runner: runner)
    }

    private static func observeDependencies(paths: HESectoriumPaths, targetBSDName: String,
                                            runner: HESectoriumCommandRunning) -> Bool {
        guard targetBSDName.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { return false }
        let resolver = SectoriumPhysicalBackingResolver(runner: runner, cwd: paths.workingDirectory)
        guard let targetRoots = resolver.physicalRoots(forDevice: targetBSDName), !targetRoots.isEmpty else { return false }
        let bundle = Bundle.main
        // A nil executable/resources URL is an incomplete dependency inventory, not evidence
        // that the corresponding runtime dependency can survive unplugging the selected disk.
        guard let executable = bundle.executableURL, let resources = bundle.resourceURL else { return false }
        let locations = [paths.root, paths.state, paths.lock, paths.config, paths.sectoriumProfiles,
                         paths.logs, paths.workingDirectory, bundle.bundleURL, executable, resources, URL(fileURLWithPath: "/")]
        for location in locations {
            guard let path = resolver.canonicalExistingPath(location),
                  let roots = resolver.physicalRoots(forPath: path), !roots.isEmpty,
                  roots.isDisjoint(with: targetRoots) else { return false }
        }
        return true
    }
}

/// Resolves only paths explicitly used by the operation. All observations go through the
/// injected runner; no device catalog scan or process/file inventory is performed here.
private struct SectoriumPhysicalBackingResolver {
    let runner: HESectoriumCommandRunning
    let cwd: URL
    private let maximumImageDepth = 8

    func canonicalExistingPath(_ url: URL) -> URL? {
        var candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        while !FileManager.default.fileExists(atPath: candidate.path) {
            guard candidate.path != "/" else { return nil }
            candidate.deleteLastPathComponent()
        }
        let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
        return canonical.path.hasPrefix("/") ? canonical : nil
    }

    func physicalRoots(forPath path: URL) -> Set<String>? {
        physicalRoots(forPath: path, visited: [], imageDepth: 0)
    }

    func physicalRoots(forDevice bsd: String) -> Set<String>? {
        resolveDevice(bsd, visited: [], imageDepth: 0)
    }

    private func physicalRoots(forPath path: URL, visited: Set<String>, imageDepth: Int) -> Set<String>? {
        guard let canonical = canonicalExistingPath(path) else { return nil }
        let result = runner.run("/bin/df", ["-P", canonical.path], cwd: cwd)
        guard result.exitCode == 0 else { return nil }
        let lines = result.detail.split(whereSeparator: \.isNewline)
        guard lines.count >= 2,
              let row = lines.last?.split(whereSeparator: \.isWhitespace), row.count >= 6,
              row[0].hasPrefix("/dev/"), row.last?.hasPrefix("/") == true,
              let bsd = Self.deviceID(String(row[0].dropFirst(5))) else { return nil }
        return resolveDevice(bsd, visited: visited, imageDepth: imageDepth)
    }

    private func resolveDevice(_ bsd: String, visited: Set<String>, imageDepth: Int) -> Set<String>? {
        guard imageDepth <= maximumImageDepth, !visited.contains(bsd),
              let plist = commandPlist("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(bsd)"]),
              Self.deviceID(plist["DeviceIdentifier"] as? String ?? "") == bsd else { return nil }
        var nextVisited = visited
        nextVisited.insert(bsd)
        let isWholeDisk = bsd.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil
        let isPartition = bsd.range(of: #"^disk[0-9]+(?:s[0-9]+)+$"#, options: .regularExpression) != nil
        if let wholeClaim = plist["WholeDisk"] {
            guard let whole = wholeClaim as? Bool, whole == isWholeDisk else { return nil }
        }

        // Partition metadata commonly omits VirtualOrPhysical. Its explicit parent is
        // the first trust edge; following the APFS container reference here can cycle
        // from a physical store back into its own synthesized container.
        if plist["ParentWholeDisk"] != nil || plist["PartOfWhole"] != nil {
            guard let parent = SectoriumDeviceCatalog.verifiedParentWholeDisk(plist) else { return nil }
            if isPartition {
                guard bsd.hasPrefix(parent + "s") else { return nil }
                return resolveDevice(parent, visited: nextVisited, imageDepth: imageDepth)
            }
            // diskutil also reports self-parent claims for physical and synthesized
            // whole disks. They must continue through the APFS/type checks below.
            guard isWholeDisk, parent == bsd else { return nil }
        }

        if let containerID = plist["APFSContainerReference"] as? String {
            guard !containerID.isEmpty,
                  let root = commandPlist("/usr/sbin/diskutil", ["apfs", "list", "-plist"]),
                  let containers = root["Containers"] as? [[String: Any]] ?? root["APFSContainers"] as? [[String: Any]],
                  let container = containers.filter({ $0["ContainerReference"] as? String == containerID }).first,
                  containers.filter({ $0["ContainerReference"] as? String == containerID }).count == 1,
                  let stores = container["PhysicalStores"] as? [[String: Any]], stores.count == 1,
                  let rawStore = stores[0]["DeviceIdentifier"] as? String ?? stores[0]["DeviceNode"] as? String,
                  let store = Self.deviceID(rawStore) else { return nil }
            return resolveDevice(store, visited: nextVisited, imageDepth: imageDepth)
        }

        guard let kind = plist["VirtualOrPhysical"] as? String else { return nil }
        switch kind.lowercased() {
        case "physical":
            guard isWholeDisk else { return nil }
            return [bsd]
        case "unknown":
            // Built-in Apple storage can report Unknown for its physical whole disk.
            // Use the catalog's internal/GUID evidence, plus an explicit self-parent;
            // external, missing, contradictory, or APFS-backed claims remain unknown.
            guard isWholeDisk, SectoriumDeviceCatalog.verifiedParentWholeDisk(plist) == bsd,
                  (plist["Internal"] as? Bool) == true, (plist["WholeDisk"] as? Bool) == true,
                  (plist["Content"] as? String) == "GUID_partition_scheme",
                  (plist["DeviceLocation"] as? String)?.lowercased() != "external",
                  plist["APFSPhysicalStores"] == nil, plist["APFSContainerReference"] == nil else { return nil }
            return [bsd]
        case "virtual":
            guard imageDepth < maximumImageDepth,
                  let root = commandPlist("/usr/bin/hdiutil", ["info", "-plist"]),
                  let images = root["images"] as? [[String: Any]] else { return nil }
            let matching = images.filter { row in
                (row["system-entities"] as? [[String: Any]] ?? []).contains { entity in
                    guard let node = entity["dev-entry"] as? String else { return false }
                    return Self.deviceID(node) == bsd
                }
            }
            guard let image = matching.first, matching.count == 1, let rawPath = image["image-path"] as? String,
                  let imagePath = Self.absolutePath(rawPath) else { return nil }
            return physicalRoots(forPath: URL(fileURLWithPath: imagePath), visited: nextVisited,
                                 imageDepth: imageDepth + 1)
        default:
            return nil
        }
    }

    private func commandPlist(_ executable: String, _ arguments: [String]) -> [String: Any]? {
        let result = runner.run(executable, arguments, cwd: cwd)
        guard result.exitCode == 0, let start = result.detail.range(of: "<?xml") ?? result.detail.range(of: "<plist"),
              let end = result.detail.range(of: "</plist>", range: start.lowerBound..<result.detail.endIndex),
              let data = String(result.detail[start.lowerBound..<end.upperBound]).data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func absolutePath(_ raw: String) -> String? {
        guard raw.hasPrefix("/"), !raw.contains("\0"), !raw.split(separator: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }

    private static func deviceID(_ raw: String) -> String? {
        let value = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
        guard value.range(of: #"^disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
}
