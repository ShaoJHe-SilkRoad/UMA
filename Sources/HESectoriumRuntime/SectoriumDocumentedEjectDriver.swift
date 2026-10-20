import Foundation
import HESectoriumCore

/// Runs the durable portable-history precondition inside Core's existing operation
/// lock immediately before the first native mutation. Read-only observations remain
/// transparent, including the final offline/absence check.
final class SectoriumDocumentedEjectDriver: WholeDeviceEjectDriving {
    private let base: WholeDeviceEjectDriving
    private let beforeMutation: () -> Bool
    private var recorded = false
    init(base: WholeDeviceEjectDriving, beforeMutation: @escaping () -> Bool) {
        self.base = base; self.beforeMutation = beforeMutation
    }
    private func perform(_ action: () -> WholeDeviceActionReceipt) -> WholeDeviceActionReceipt {
        if !recorded {
            guard beforeMutation() else { return .failed("Portable operation history could not be durably recorded") }
            recorded = true
        }
        return action()
    }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? { base.observe(physicalIdentity: physicalIdentity) }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String], from target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        perform { base.unmountImageVolumesNonForce(imageIdentity, volumeIdentities: volumeIdentities, from: target) }
    }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        perform { base.detachImageNonForce(imageIdentity, from: target) }
    }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        perform { base.unmountAllPhysicalVolumesNonForce(target) }
    }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        perform { base.ejectWholeDeviceNonForce(target) }
    }
    func presence(physicalIdentity: String) -> WholeDevicePresence { base.presence(physicalIdentity: physicalIdentity) }
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence { base.presence(of: target) }
    func successfulEjectHasUnmountedPostcondition(of target: WholeDeviceTopology) -> Bool {
        base.successfulEjectHasUnmountedPostcondition(of: target)
    }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { base.freshReturnIdentityMatches(journal) }
    func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { base.freshPhysicalContinuationMatches(journal) }
    func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery { base.freshEjectIssuedRecovery(journal) }
}
