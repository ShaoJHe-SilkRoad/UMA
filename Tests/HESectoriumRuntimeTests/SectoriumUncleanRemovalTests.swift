import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

@Suite("Unplugged without Disconnect")
struct SectoriumUncleanRemovalTests {
    private let image = "/Volumes/HE/.DEV-APFS.sparsebundle"

    private func info(mounted: String?) -> [String: Any] {
        ["images": [["image-path": image, "system-entities": [
            ["dev-entry": "/dev/disk5", "content-hint": "GUID_partition_scheme"],
            ["dev-entry": "/dev/disk5s1", "content-hint": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"],
            ["dev-entry": "/dev/disk5s2", "content-hint": "7C3457EF-0000-11AA-AA11-00306543ECAC"],
            ["dev-entry": "/dev/disk6", "content-hint": "EF57347C-0000-11AA-AA11-00306543ECAC"],
            ["dev-entry": "/dev/disk6s1", "content-hint": "41504653-0000-11AA-AA11-00306543ECAC",
             "mount-point": mounted ?? ""]]]]]
    }

    @Test("The orphaned attachment of exactly this image is found with its mounted volume")
    func findsOrphan() {
        let mounted = SectoriumOrphanedAttachment.find(imagePath: image, in: info(mounted: "/Volumes/HE/DEV"))
        #expect(mounted == .init(wholeDisk: "disk5", mountPoints: ["/Volumes/HE/DEV"]))
        #expect(SectoriumOrphanedAttachment.find(imagePath: image, in: info(mounted: nil))?.mountPoints.isEmpty == true)
        #expect(SectoriumOrphanedAttachment.find(imagePath: "/Volumes/X/other.sparsebundle", in: info(mounted: nil)) == nil)
        #expect(SectoriumOrphanedAttachment.find(imagePath: image, in: nil) == nil)
    }

    @Test("The registry survives a restart, keeps a mounted removal and clears after a passed check")
    func registryRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("unclean-\(UUID().uuidString)").appendingPathComponent("unclean.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let registry = SectoriumUncleanRemovalRegistry(url: url)
        #expect(registry.entry("A") == nil)
        #expect(registry.mark("A", volumeWasMounted: true))
        #expect(registry.mark("A", volumeWasMounted: false))
        let reopened = SectoriumUncleanRemovalRegistry(url: url)
        #expect(reopened.entry("A")?.volumeWasMounted == true)
        #expect(reopened.clear("A"))
        #expect(reopened.entry("A") == nil)
    }

    @Test("Only a clean exit of the read-only check passes")
    func verifyRule() {
        #expect(MacStorageBackend.verifyVolumePassed(.init(exitCode: 0, detail: "appears to be OK")))
        #expect(!MacStorageBackend.verifyVolumePassed(.init(exitCode: 1, detail: "error")))
        #expect(!MacStorageBackend.verifyVolumePassed(.init(exitCode: -1, detail: "timed out")))
    }
}
