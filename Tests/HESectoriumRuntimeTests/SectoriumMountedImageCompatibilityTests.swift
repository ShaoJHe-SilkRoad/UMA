import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

@Suite("Sectorium mounted-image compatibility")
struct SectoriumMountedImageCompatibilityTests {
    private func fixtureRoot() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/sectorium-mounted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url.resolvingSymlinksInPath()
    }

    @Test func mountedBundleMetadataIsStrictAndNeverFollowsLinks() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("Existing.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        let metadata = image.appendingPathComponent("Info.plist")
        let original: [String: Any] = [
            "diskimage-bundle-type": "com.apple.diskimage.sparsebundle",
            "bundle-backingstore-version": 2, "band-size": 8_388_608, "size": UInt64(322_122_547_200)
        ]
        func write(_ info: [String: Any]) throws {
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: metadata)
        }
        try write(original)
        #expect(HESectoriumService.mountedSparsebundleMetadataFormat(image) == "UDSB")
        for (key, invalid) in [
            ("diskimage-bundle-type", "com.apple.diskimage.sparseimage" as Any),
            ("bundle-backingstore-version", 99 as Any), ("band-size", 0 as Any),
            ("band-size", 1234 as Any), ("size", -1 as Any), ("size", true as Any)
        ] {
            var info = original; info[key] = invalid; try write(info)
            #expect(HESectoriumService.mountedSparsebundleMetadataFormat(image) == nil)
        }
        try Data(repeating: 65, count: 65_537).write(to: metadata)
        #expect(HESectoriumService.mountedSparsebundleMetadataFormat(image) == nil)
        try FileManager.default.removeItem(at: metadata)
        let external = root.appendingPathComponent("other.plist")
        try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0).write(to: external)
        try FileManager.default.createSymbolicLink(at: metadata, withDestinationURL: external)
        #expect(HESectoriumService.mountedSparsebundleMetadataFormat(image) == nil)
        let alias = root.appendingPathComponent("Alias.sparsebundle")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: image)
        #expect(HESectoriumService.mountedSparsebundleMetadataFormat(alias) == nil)
    }

    @Test func machineFormatStdoutIsSeparatedFromDeprecationWarnings() {
        let warning = Data("hdiutil: WARNING: imageinfo is deprecated\n".utf8)
        let command = ["imageinfo", "/fixture/Existing.sparsebundle", "-format"]
        let success = ProcessCommandRunner.result(executable: "/usr/bin/hdiutil", arguments: command,
            exitCode: 0, stdout: Data("UDSB\n".utf8), stderr: warning)
        #expect(HESectoriumService.documentedSparsebundleFormat(success.detail) == "UDSB")
        let failed = ProcessCommandRunner.result(executable: "/usr/bin/hdiutil", arguments: command,
            exitCode: 1, stdout: Data(), stderr: warning)
        #expect(!failed.succeeded && failed.detail.contains("WARNING"))
        let action = ProcessCommandRunner.result(executable: "/usr/bin/hdiutil", arguments: ["attach", "/fixture/image"],
            exitCode: 0, stdout: Data("output".utf8), stderr: warning)
        #expect(action.detail.contains("WARNING"))
    }

    /// Optional raw capture replay: no native command can run. Only fixed captured
    /// metadata files are read; filesystem paths are relocated into a disposable root.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_SECTORIUM_NATIVE_SNAPSHOT"] != nil))
    func capturedMountedLegacyCanBeDisplayedAndAdoptedWithoutReopeningImage() throws {
        let snapshot = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AUV_SECTORIUM_NATIVE_SNAPSHOT"]))
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = try CapturedMountedImageRunner(snapshot: snapshot, root: root)
        // Inventory parsing uses the original native paths and all original keys.
        runner.relocate = false
        let native = try SystemSectoriumDeviceObserver(runner: runner, workingDirectory: root).observeDevices()
        #expect(native.filter { $0.isVirtual == false }.count == 2)
        let physical = try #require(native.first { $0.isVirtual == false && $0.isExternal })
        #expect(physical.identityVerified && physical.wholeDeviceBytes == 1_024_209_543_168)
        runner.relocate = true
        let relocated = native.map(runner.relocatedDevice)
        let selected = try #require(relocated.first { $0.id == physical.id })
        let paths = HESectoriumPaths(root: root.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runner.dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runner.image, withIntermediateDirectories: true)
        try Data(contentsOf: snapshot.appendingPathComponent("image-Info.plist"))
            .write(to: runner.image.appendingPathComponent("Info.plist"))
        let outerInfo = try runner.dictionary("he-info.plist")
        let devInfo = try runner.dictionary("dev-info.plist")
        let policy = StorageIdentityPolicy(
            outerUUID: try #require(UUID(uuidString: outerInfo["VolumeUUID"] as? String ?? "")),
            devUUID: try #require(UUID(uuidString: devInfo["VolumeUUID"] as? String ?? "")),
            outerMountPoint: runner.outer.path, devMountPoint: runner.dev.path,
            devVolumeName: "DEV_APFS", imagePath: runner.image.path)
        let service = HESectoriumService(paths: paths, runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: CapturedMountedDeviceObserver(relocated),
            portableDocumentWriter: CapturedMountedDocumentWriter())
        service.selectSectoriumDevice(selected.id, observedBSDName: selected.bsdName, observedDevice: selected)
        #expect(!FileManager.default.fileExists(atPath: paths.sectoriumProfiles.path))
        let legacy = try #require(service.legacyDevelopmentDisplay(deviceID: selected.id, devices: relocated))
        #expect(legacy.state == .mounted && legacy.name == "DEV_APFS")
        #expect(legacy.logicalCapacityBytes == 321_912_791_040)
        // Preserve the real regression: the old native format command is busy,
        // and an invalid bundle descriptor must not become a successful adoption.
        let nativeFailure = try #require(JSONSerialization.jsonObject(with:
            Data(contentsOf: snapshot.appendingPathComponent("image-format-native.json"))) as? [String: Any])
        #expect(nativeFailure["exit"] as? Int == 1)
        #expect((nativeFailure["stderr"] as? String)?.contains("Resource temporarily unavailable") == true)
        let metadataURL = runner.image.appendingPathComponent("Info.plist")
        let descriptor = try Data(contentsOf: metadataURL)
        try Data("invalid fixture descriptor".utf8).write(to: metadataURL)
        let refused = service.adoptConfiguredLegacyDevelopmentDisk(deviceID: selected.id)
        #expect(!refused.succeeded)
        #expect(!FileManager.default.fileExists(atPath: paths.sectoriumProfiles.path))
        #expect(service.legacyDevelopmentDisplay(deviceID: selected.id, devices: relocated)?.state == .mounted)
        #expect(service.resumePendingSectoriumOperation().succeeded)
        try descriptor.write(to: metadataURL)
        let commandsBeforeValidAdoption = runner.commands.count
        let adopted = service.adoptConfiguredLegacyDevelopmentDisk(deviceID: selected.id)
        #expect(adopted.succeeded, "\(String(describing: adopted.failure))")
        let profile = try #require(service.sectoriumProfiles().first)
        #expect(profile.devUUID == policy.devUUID && profile.imageFormat == "UDSB")
        #expect(profile.encrypted == false)
        #expect(profile.logicalCapacityBytes == legacy.logicalCapacityBytes)
        #expect(profile.logicalCapacityBytes == 321_912_791_040)
        #expect(profile.logicalCapacityBytes != 322_122_547_200) // Info.plist's image upper bound is not volume capacity.
        #expect(profile.filesystem == .apfs && profile.caseSensitive == false)
        #expect(service.verifiedLoadedState(profileID: profile.id) == true)
        let load = service.startDevelopmentDisk(profileID: profile.id)
        #expect(load.succeeded, "\(String(describing: load.failure))")
        #expect(load.steps.contains { $0.step == "reuseVerifiedImage" })
        #expect(service.sectoriumProfiles().first?.logicalCapacityBytes == legacy.logicalCapacityBytes)
        #expect(!runner.commands.dropFirst(commandsBeforeValidAdoption).contains { $0.contains("imageinfo") || $0.contains("isencrypted") })
        #expect(runner.unexpectedCommands.isEmpty)
    }
}

private final class CapturedMountedDeviceObserver: SectoriumDeviceObserving {
    let devices: [SectoriumPhysicalDevice]
    init(_ devices: [SectoriumPhysicalDevice]) { self.devices = devices }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { devices }
}

private final class CapturedMountedDocumentWriter: SectoriumPortableDocumentWriting {
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult { .updated }
    func update(context: SectoriumPortableDocumentContext, events: [SectoriumPortableDocumentEvent]) -> SectoriumPortableDocumentResult { .updated }
}

private final class CapturedMountedImageRunner: HESectoriumCommandRunning {
    let snapshot: URL
    let outer: URL, dev: URL, image: URL
    var relocate = true
    var commands: [[String]] = [], unexpectedCommands: [[String]] = []
    init(snapshot: URL, root: URL) throws {
        self.snapshot = snapshot
        outer = root.appendingPathComponent("HE")
        dev = outer.appendingPathComponent("DEV")
        image = outer.appendingPathComponent(".DEV-APFS.sparsebundle")
    }
    func path(_ value: String) -> String {
        value.replacingOccurrences(of: "/Volumes/HE", with: outer.path)
    }
    func dictionary(_ name: String) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: snapshot.appendingPathComponent(name)), options: [], format: nil) as? [String: Any])
    }
    private func transform(_ value: Any) -> Any {
        if let string = value as? String { return relocate ? path(string) : string }
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(transform) }
        if let array = value as? [Any] { return array.map(transform) }
        return value
    }
    func relocatedDevice(_ d: SectoriumPhysicalDevice) -> SectoriumPhysicalDevice {
        .init(id: d.id, bsdName: d.bsdName, name: d.name, isExternal: d.isExternal, identityVerified: d.identityVerified,
            wholeDeviceBytes: d.wholeDeviceBytes, mountedVolumePaths: d.mountedVolumePaths.map(path), volumeUUIDs: d.volumeUUIDs,
            readBytes: nil, writtenBytes: nil, volumeMembers: d.volumeMembers.map {
                .init(volumeUUID: $0.volumeUUID, bsdName: $0.bsdName, mountPoint: $0.mountPoint.map(path), name: $0.name, capacityBytes: $0.capacityBytes)
            }, topologyComplete: d.topologyComplete, isVirtual: d.isVirtual, identityBasis: d.identityBasis,
            wholeMediaUUID: d.wholeMediaUUID, requiresFreshParentCheck: d.requiresFreshParentCheck,
            apfsContainers: d.apfsContainers, hasAmbiguousPhysicalStores: d.hasAmbiguousPhysicalStores)
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        commands.append([executable] + arguments)
        let file: String?
        if executable == "/usr/sbin/diskutil", arguments == ["list", "-plist"] { file = "disk-list.plist" }
        else if executable == "/usr/sbin/diskutil", arguments == ["apfs", "list", "-plist"] { file = "apfs-list.plist" }
        else if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"] { file = "images.plist" }
        else if executable == "/usr/sbin/diskutil", arguments.count == 3, arguments.prefix(2) == ["info", "-plist"] {
            let target = arguments[2]
            if target == outer.path { file = "he-info.plist" }
            else if target == dev.path { file = "dev-info.plist" }
            else if target.range(of: #"^/dev/disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil {
                file = "info-\(target.dropFirst(5)).plist"
            } else { file = nil }
        } else if executable == "/bin/df", arguments == ["-P", image.path],
                  let text = try? String(contentsOf: snapshot.appendingPathComponent("image-df.stdout"), encoding: .utf8) {
            return .init(exitCode: 0, detail: path(text))
        } else if executable == "/usr/bin/hdiutil", arguments == ["imageinfo", image.path, "-format"] {
            return .init(exitCode: 1, detail: (try? String(contentsOf: snapshot.appendingPathComponent("image-format-native.stderr"), encoding: .utf8)) ?? "captured imageinfo unavailable")
        } else { file = nil }
        if let file, let dictionary = try? dictionary(file),
           let data = try? PropertyListSerialization.data(fromPropertyList: transform(dictionary), format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        unexpectedCommands.append([executable] + arguments)
        return .init(exitCode: 127, detail: "Capture replay forbids uncaptured commands; no native fallback exists")
    }
}
