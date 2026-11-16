import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

@Suite("Disk images stored on a drive")
struct SectoriumAttachedImagesTests {
    // As on the developer's Mac: DEV_APFS's image on HE, and an installer DMG
    // that was downloaded into DEV and opened from there.
    private let info: [String: Any] = ["images": [
        ["image-path": "/Volumes/HE/.DEV-APFS.sparsebundle", "hdid-pid": 9484, "system-entities": [
            ["dev-entry": "/dev/disk5"], ["dev-entry": "/dev/disk5s1"], ["dev-entry": "/dev/disk5s2"],
            ["dev-entry": "/dev/disk6"], ["dev-entry": "/dev/disk6s1", "mount-point": "/Volumes/HE/DEV"]]],
        ["image-path": "/Volumes/HE/DEV/TOSUMA/dist/AUV_Mac_0.18.10_Universal.dmg", "hdid-pid": 9601, "system-entities": [
            ["dev-entry": "/dev/disk8"], ["dev-entry": "/dev/disk8s1", "mount-point": "/Volumes/AUV 0.18.10"]]],
        ["image-path": "/Users/someone/Downloads/Other.dmg", "hdid-pid": 9700, "system-entities": [
            ["dev-entry": "/dev/disk9"], ["dev-entry": "/dev/disk9s1", "mount-point": "/Volumes/Other"]]]]]

    @Test("hdiutil's list maps to whole disks, helpers and mount points")
    func parses() throws {
        let images = try #require(SectoriumAttachedImages.parse(info))
        #expect(images.map(\.wholeDisk) == ["disk5", "disk8", "disk9"])
        #expect(images.map(\.helperPID) == [9484, 9601, 9700])
        #expect(images[1].mountPoints == ["/Volumes/AUV 0.18.10"])
        #expect(images[1].displayName == "AUV 0.18.10")
        #expect(SectoriumAttachedImages.parse(["images": [["image-path": "/x.dmg"]]]) == nil)
    }

    @Test("An image stored inside the development volume is found; others are not")
    func storedInside() throws {
        let images = try #require(SectoriumAttachedImages.parse(info))
        #expect(images.filter { $0.isStored(under: "/Volumes/HE/DEV") }.map(\.wholeDisk) == ["disk8"])
        #expect(!images[0].isStored(under: "/Volumes/HE/DEV"))
        #expect(images[0].isStored(under: "/Volumes/HE"))
        #expect(!images[0].isStored(under: "/Volumes/H"))
    }

    @Test("An image stored inside another one is detached first")
    func innermostFirst() throws {
        let images = try #require(SectoriumAttachedImages.parse(info))
        let order = SectoriumAttachedImages.innermostFirst([images[0], images[1]]).map(\.wholeDisk)
        #expect(order == ["disk8", "disk5"])
        // Already in order, or unrelated, it keeps a stable order.
        #expect(SectoriumAttachedImages.innermostFirst([images[1], images[2]]).map(\.wholeDisk) == ["disk8", "disk9"])
    }

    @Test("Helpers of images the operation releases do not count as using the drive")
    func helpersAreExcluded() {
        let helper = SectoriumActivityProcess(processID: 9484, command: "diskimages-helper")
        let editor = SectoriumActivityProcess(processID: 42, command: "Code")
        let busy = SectoriumActivityReport(assessment: .busy(processIDs: [42, 9484]), processes: [editor, helper])
        #expect(busy.excluding([9484]).assessment == .busy(processIDs: [42]))
        let onlyHelper = SectoriumActivityReport(assessment: .busy(processIDs: [9484]), processes: [helper])
        #expect(onlyHelper.excluding([9484]).assessment == .noVisibleOccupancy)
        let unknown = SectoriumActivityReport(assessment: .incomplete(reason: "x"))
        #expect(unknown.excluding([9484]) == unknown)
        #expect(onlyHelper.excluding([9484]).merged(with: busy.excluding([9484])).assessment == .busy(processIDs: [42]))
        #expect(busy.merged(with: unknown).assessment == .incomplete(reason: "x"))
    }
}
