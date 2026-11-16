import Foundation

/// Bounds reject an oversized record without deleting or truncating its history.
enum SectoriumPortableDocumentLimits {
    static let maximumBytes = 4 * 1_024 * 1_024
    static let journalMaximumBytes = 32 * 1_024 * 1_024
}

public struct SectoriumPortableParentRecord: Codable, Equatable, Sendable {
    public var physicalID: String
    public var name: String?
    public var physicalCapacityBytes: UInt64?
    public var documentVolumeUUID: UUID
    public var rootPath: String
    public var filesystem: String?
    public var totalBytes: UInt64?
    public var availableBytes: UInt64?
    public init(physicalID: String, name: String? = nil, physicalCapacityBytes: UInt64? = nil,
                documentVolumeUUID: UUID, rootPath: String, filesystem: String? = nil,
                totalBytes: UInt64? = nil, availableBytes: UInt64? = nil) {
        self.physicalID = physicalID; self.name = name; self.physicalCapacityBytes = physicalCapacityBytes
        self.documentVolumeUUID = documentVolumeUUID; self.rootPath = rootPath; self.filesystem = filesystem
        self.totalBytes = totalBytes; self.availableBytes = availableBytes
    }
}

/// Facts are supplied by the storage controller. Nil means unverified, never inferred.
/// imagePath may be on another backing volume of the same verified physical parent.
public struct SectoriumPortableVolumeRecord: Codable, Equatable, Sendable {
    public var profileID: String
    public var name: String
    public var volumeUUID: UUID?
    public var filesystem: String?
    public var logicalCapacityBytes: UInt64?
    public var allocatedBytes: UInt64?
    public var imagePath: String
    public var mountPoint: String
    public var autoLoad: Bool
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var lastVerifiedLoadedAt: Date?
    public var formatMethod: String?
    public init(profileID: String, name: String, volumeUUID: UUID? = nil, filesystem: String? = nil,
                logicalCapacityBytes: UInt64? = nil, allocatedBytes: UInt64? = nil,
                imagePath: String, mountPoint: String, autoLoad: Bool, createdAt: Date? = nil,
                modifiedAt: Date? = nil, lastVerifiedLoadedAt: Date? = nil, formatMethod: String? = nil) {
        self.profileID = profileID; self.name = name; self.volumeUUID = volumeUUID; self.filesystem = filesystem
        self.logicalCapacityBytes = logicalCapacityBytes; self.allocatedBytes = allocatedBytes
        self.imagePath = imagePath; self.mountPoint = mountPoint; self.autoLoad = autoLoad
        self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.lastVerifiedLoadedAt = lastVerifiedLoadedAt
        self.formatMethod = formatMethod
    }
}

public struct SectoriumPortableDocumentContext: Codable, Equatable, Sendable {
    public var parent: SectoriumPortableParentRecord
    public var volumes: [SectoriumPortableVolumeRecord]
    public init(parent: SectoriumPortableParentRecord, volumes: [SectoriumPortableVolumeRecord]) {
        self.parent = parent; self.volumes = volumes
    }
}

public enum SectoriumPortableDocumentPhase: String, Codable, Equatable, Sendable {
    case intended, completed
}

public struct SectoriumPortableDocumentEvent: Codable, Equatable, Sendable {
    public let id: String
    public let occurredAt: Date
    public let profileID: String
    public let kind: String
    public let phase: SectoriumPortableDocumentPhase
    public let before: SectoriumPortableVolumeRecord?
    public let after: SectoriumPortableVolumeRecord?
    public let detail: String?
    public init(id: String, occurredAt: Date, profileID: String, kind: String,
                phase: SectoriumPortableDocumentPhase = .completed,
                before: SectoriumPortableVolumeRecord? = nil, after: SectoriumPortableVolumeRecord? = nil,
                detail: String? = nil) {
        self.id = id; self.occurredAt = occurredAt; self.profileID = profileID; self.kind = kind
        self.phase = phase; self.before = before; self.after = after; self.detail = detail
    }
}

struct SectoriumPortableSnapshot: Codable, Equatable {
    let context: SectoriumPortableDocumentContext
    let history: [SectoriumPortableDocumentEvent]
}

enum SectoriumPortableValidation {
    static let kinds: Set<String> = ["registered", "validated", "loaded", "unloaded", "ejected", "reconnected",
        "displayNameChanged", "autoLoadChanged", "mountPointChanged", "capacityChanged", "filesystemChanged",
        "removed", "replaced", "creationIntended", "modificationIntended"]
    static func path(_ path: String) -> Bool {
        !path.isEmpty && path.hasPrefix("/") && !path.contains("\0") &&
        URL(fileURLWithPath: path).standardizedFileURL.path == path
    }
    static func volume(_ volume: SectoriumPortableVolumeRecord) -> Bool {
        UUID(uuidString: volume.profileID) != nil && !volume.name.isEmpty &&
        path(volume.imagePath) && path(volume.mountPoint) &&
        [volume.createdAt, volume.modifiedAt, volume.lastVerifiedLoadedAt].compactMap { $0 }
            .allSatisfy { $0.timeIntervalSince1970.isFinite }
    }
    static func context(_ value: SectoriumPortableDocumentContext) -> Bool {
        let parent = value.parent
        guard !parent.physicalID.isEmpty, parent.physicalID.count <= 256, path(parent.rootPath), parent.rootPath != "/",
              Set(value.volumes.map(\.profileID)).count == value.volumes.count,
              Set(value.volumes.map(\.imagePath)).count == value.volumes.count,
              Set(value.volumes.map(\.mountPoint)).count == value.volumes.count,
              Set(value.volumes.compactMap(\.volumeUUID)).count == value.volumes.compactMap(\.volumeUUID).count,
              value.volumes.allSatisfy(volume) else { return false }
        if let total = parent.totalBytes, let available = parent.availableBytes, available > total { return false }
        return true
    }
    static func event(_ event: SectoriumPortableDocumentEvent) -> Bool {
        !event.id.isEmpty && event.id.count <= 512 && !event.id.contains("\0") &&
        event.occurredAt.timeIntervalSince1970.isFinite && UUID(uuidString: event.profileID) != nil &&
        kinds.contains(event.kind) && (event.detail?.count ?? 0) <= 2_000 &&
        [event.before, event.after].compactMap { $0 }.allSatisfy { $0.profileID == event.profileID && volume($0) }
    }
    static func merge(_ existing: [SectoriumPortableDocumentEvent], _ incoming: [SectoriumPortableDocumentEvent])
        -> [SectoriumPortableDocumentEvent]? {
        var byID: [String: SectoriumPortableDocumentEvent] = [:]
        for event in existing + incoming {
            guard self.event(event), byID[event.id] == nil || byID[event.id] == event else { return nil }
            byID[event.id] = event
        }
        return byID.values.sorted(by: precedes)
    }
    static func precedes(_ left: SectoriumPortableDocumentEvent, _ right: SectoriumPortableDocumentEvent) -> Bool {
        if left.occurredAt != right.occurredAt { return left.occurredAt < right.occurredAt }
        if left.phase != right.phase { return left.phase == .intended }
        return left.id < right.id
    }
}

enum SectoriumPortableV2 {
    static let notesBegin = "<!-- AUV-SECTORIUM-NOTES:BEGIN -->"
    static let notesEnd = "<!-- AUV-SECTORIUM-NOTES:END -->"
    static let dataPrefix = "<!-- AUV-SECTORIUM-DATA:"
    static let defaultNotes = "Add your own notes here. / 在此填写自己的备注。"
    static func line(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "[", with: "\\[")
    }
    static func bytes(_ value: UInt64?) -> String { value.map { "\($0) bytes / 字节" } ?? "not verified / 未核实" }
    static func date(_ value: Date?) -> String { value.map { ISO8601DateFormatter().string(from: $0) } ?? "not recorded / 未记录" }
    static func eventLabel(_ event: String) -> String {
        switch event {
        case "registered": "Registered / 登记"
        case "validated": "Verified / 核验"
        case "loaded": "Loaded / 加载"
        case "unloaded": "Unloaded / 卸载"
        case "ejected": "Ejected / 弹出"
        case "reconnected": "Reconnected / 重新连接"
        case "displayNameChanged": "Name change / 名称变更"
        case "autoLoadChanged": "Automatic loading change / 自动加载变更"
        case "mountPointChanged": "Mount location change / 挂载位置变更"
        case "capacityChanged": "Capacity change / 容量变更"
        case "filesystemChanged": "Filesystem change / 文件系统变更"
        case "removed": "Removal / 移除"
        case "replaced": "Replacement / 替换"
        case "creationIntended": "Creation / 创建"
        case "modificationIntended": "Modification / 修改"
        default: "Unknown / 未知"
        }
    }
    static func volumeLines(_ volume: SectoriumPortableVolumeRecord, prefix: String = "- ") -> [String] {
        ["Name / 名称: \(line(volume.name))",
         "Profile ID / 配置标识: \(volume.profileID)",
         "Volume UUID / 卷标识: \(volume.volumeUUID?.uuidString ?? "not verified / 未核实")",
         "Filesystem / 文件系统: \(line(volume.filesystem ?? "not verified / 未核实"))",
         "Logical capacity / 逻辑容量: \(bytes(volume.logicalCapacityBytes))",
         "Image allocated storage / 镜像实际占用: \(bytes(volume.allocatedBytes))",
         "Image location / 镜像位置: \(line(volume.imagePath))",
         "Expected mount / 预期挂载位置: \(line(volume.mountPoint))",
         "Automatic loading / 自动加载: \(volume.autoLoad ? "on / 开" : "off / 关")",
         "Created / 创建时间: \(date(volume.createdAt))",
         "Last modified / 最近修改: \(date(volume.modifiedAt))",
         "Last verified load / 最近核实加载: \(date(volume.lastVerifiedLoadedAt))",
         "Creation or format method / 创建或格式化方式: \(line(volume.formatMethod ?? "not recorded / 未记录"))"]
            .map { prefix + $0 }
    }
    static let historyEntriesShown = 30
    static let recordNotice = [
        "This record separates intended actions from verified completed operations. It is a human-readable record, never authorization or a source of disk identity.",
        " Earlier versions of this file are in .AUV-Sectorium/previous-versions.",
        "本记录区分拟执行操作与已核验完成的操作。它供人阅读，不授予操作权限，也不是磁盘身份的依据。",
        "本文件的旧版本保存在 .AUV-Sectorium/previous-versions 中。"]

    /// What someone holding this drive needs first: what is on it and how to
    /// use it on a Mac, including the macOS approval that Load asks for.
    static func usageLines(_ snapshot: SectoriumPortableSnapshot) -> [String] {
        let volumes = snapshot.context.volumes.sorted(by: { $0.profileID < $1.profileID })
        var lines = ["## On this drive / 这块硬盘上有什么", ""]
        if volumes.isEmpty {
            lines += ["No registered development volume. / 没有已登记的开发卷。", ""]
        } else {
            for volume in volumes {
                let image = URL(fileURLWithPath: volume.imagePath).lastPathComponent
                lines += ["- \(line(volume.name)): image / 镜像 \(line(image)), mounted at / 挂载到 \(line(volume.mountPoint))"]
            }
            lines += [""]
        }
        lines += ["## Using it on a Mac / 在 Mac 上使用", "",
            "1. Open AUV → Sectorium. If the volume is not listed, choose Register existing… and select the image above (press Command-Shift-. to show hidden files). / 打开 AUV →“分区工”。如果没有列出该开发卷，选择“登记已有开发卷…”，选中上面的镜像（按 Command-Shift-. 显示隐藏文件）。",
            "2. Load: macOS asks for your password or Touch ID before it mounts the volume inside this drive. / 加载：macOS 会请你输入密码或使用 Touch ID，才能把开发卷挂载到这块硬盘中。",
            "3. Before unplugging, choose Disconnect and wait for \"safe to unplug\". Never unplug while a volume is loaded. / 拔盘前点“断开”，等出现“可以拔出”。开发卷加载着时不要拔盘。", ""]
        return lines
    }

    /// The layout a document was written in. Parsing re-renders a document to
    /// prove nobody edited it outside the notes, so every layout AUV has ever
    /// written must stay reproducible here, or upgrading AUV makes each drive's
    /// existing IMPORTANT.md look hand-edited and it is never rewritten again.
    /// current: settings and commands per volume (0.18.10 build 2026111514);
    /// usage: "On this drive" and "Using it on a Mac" (builds 2026111511-13);
    /// original: 0.18.9 and earlier.
    enum Layout: CaseIterable { case current, usage, original }

    /// One block per volume that AUV and a person can both read: what the
    /// volume is, keyed by this drive's disk ID, and the exact macOS commands
    /// that load and unload it. AUV never runs commands read from this file; it
    /// reads the record data at the end and builds its own commands, which are
    /// the same ones shown here.
    static func settingsLines(_ snapshot: SectoriumPortableSnapshot) -> [String] {
        let parent = snapshot.context.parent
        let root = parent.rootPath.hasSuffix("/") ? parent.rootPath : parent.rootPath + "/"
        func relative(_ path: String) -> String { path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path }
        func safe(_ value: String) -> Bool {
            !value.isEmpty && !value.contains(where: { $0.isNewline || $0 == "`" || $0 == "<" || $0 == ">" })
        }
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var lines = ["## Volume settings and commands / 开发卷设置与命令", "",
            "AUV reads these settings when this drive is scanned on a Mac, and applies them only to the drive whose disk ID matches. The commands are the ones AUV runs; they also work in Terminal. / 在 Mac 上扫描这块硬盘时，AUV 读取这些设置，且只用于磁盘标识相符的硬盘。下面的命令就是 AUV 实际运行的命令，也可以在“终端”里直接使用。", ""]
        for volume in snapshot.context.volumes.sorted(by: { $0.profileID < $1.profileID }) {
            lines += ["### \(line(volume.name))", ""]
            guard safe(volume.name), safe(volume.imagePath), safe(volume.mountPoint), safe(parent.rootPath) else {
                lines += ["Settings are not shown because a name or path contains unusual characters. / 名称或路径含特殊字符，未显示设置。", ""]
                continue
            }
            let gib = volume.logicalCapacityBytes.map { Int(($0 + (1 << 30) - 1) >> 30) }
            lines += ["```sectorium",
                "disk-id: \(parent.physicalID)",
                "drive-volume-uuid: \(parent.documentVolumeUUID.uuidString)",
                "name: \(volume.name)",
                "volume-uuid: \(volume.volumeUUID?.uuidString ?? "not recorded yet")",
                "type: \(volume.filesystem ?? "APFS") volume in a sparse bundle disk image",
                "size-bytes: \(volume.logicalCapacityBytes.map(String.init) ?? "not verified")",
                "image: \(relative(volume.imagePath))",
                "mount-point: \(relative(volume.mountPoint))",
                "```", "",
                "```bash",
                "# Load / 装载 (macOS asks for your password or Touch ID / 需要密码或 Touch ID)",
                "hdiutil attach -nomount -nobrowse \(quoted(volume.imagePath))",
                "diskutil mount -mountPoint \(quoted(volume.mountPoint)) \(volume.volumeUUID?.uuidString ?? "<the APFS volume listed by the attach command / 上一条命令列出的 APFS 卷>")",
                "# Unload and release the image / 卸载并释放镜像",
                "hdiutil detach \(quoted(volume.mountPoint))",
                "# Before unplugging: unload every volume, then / 拔盘前：先卸载所有开发卷，再运行",
                "diskutil eject \(quoted(parent.rootPath))"]
            if let gib {
                lines += ["# How it was created (reference only; never run it on an existing image) / 创建方式（仅供参考，切勿对已有镜像运行）",
                          "# hdiutil create -type SPARSEBUNDLE -fs APFS -size \(gib)g -volname \(quoted(volume.name)) \(quoted(volume.imagePath))"]
            }
            lines += ["```", ""]
        }
        return lines
    }

    static func render(_ snapshot: SectoriumPortableSnapshot, notes: String,
                       layout: Layout = .current) -> String {
        let original = layout == .original
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(snapshot) else { return "" }
        let parent = snapshot.context.parent
        let used = parent.totalBytes.flatMap { total in parent.availableBytes.flatMap { $0 <= total ? total - $0 : nil } }
        var lines = ["<!-- AUV-SECTORIUM-IMPORTANT:v2 host=\(parent.documentVolumeUUID.uuidString) -->",
            "# AUV development volumes / AUV 开发盘", ""]
        if original {
            lines += [recordNotice[0], recordNotice[2], ""]
        } else {
            lines += usageLines(snapshot)
            if layout == .current { lines += settingsLines(snapshot) }
            lines += ["## This drive / 这块硬盘", ""]
        }
        lines += [
            "Parent device / 母盘: \(line(parent.name ?? "not recorded / 未记录"))",
            "Physical identity / 物理身份: \(line(parent.physicalID))",
            "Physical device capacity / 物理母盘容量: \(bytes(parent.physicalCapacityBytes))",
            "Document-host volume UUID / 文档所在母卷标识: \(parent.documentVolumeUUID.uuidString)",
            "Document-host mount / 文档所在母卷挂载点: \(line(parent.rootPath))",
            "Document-host filesystem / 文档所在母卷文件系统: \(line(parent.filesystem ?? "not verified / 未核实"))",
            "Document-host capacity / 文档所在母卷容量: \(bytes(parent.totalBytes))",
            "Available filesystem space / 文件系统可用空间: \(bytes(parent.availableBytes))",
            "Used filesystem space / 文件系统已用空间: \(bytes(used))",
            "Available is free capacity inside this filesystem; used is total minus available. Neither is unallocated partition space. Logical development capacity is a limit; image allocated storage is its measured physical consumption. APFS volumes may share container capacity. Unverified values remain unknown.",
            "可用指此文件系统内的空闲容量；已用为总容量减可用容量，两者都不是未分区空间。开发盘逻辑容量是上限；镜像实际占用是测得的物理消耗。APFS 卷可能共享容器容量。未经核实的值保持未知。", "",
            "## Registered volumes on this physical parent / 此物理母盘上的已登记开发盘", ""]
        if snapshot.context.volumes.isEmpty { lines += ["No registered development volumes remain. History is preserved. / 已无登记开发盘；历史保留。", ""] }
        for volume in snapshot.context.volumes.sorted(by: { $0.profileID < $1.profileID }) {
            lines += ["### \(line(volume.name))"] + volumeLines(volume) + [""]
        }
        // The full history stays in the record data at the end of this file and
        // travels with the drive; the readable list shows the latest entries.
        let shown = original ? snapshot.history[...] : snapshot.history.suffix(historyEntriesShown)
        lines += ["## History / 操作历史", "<!-- AUV-SECTORIUM-HISTORY:BEGIN -->"]
        if snapshot.history.count > shown.count {
            let earlier = snapshot.history.count - shown.count
            lines += ["Latest \(shown.count) of \(snapshot.history.count) entries; the \(earlier) earlier ones are kept in the record data at the end of this file. / 显示最近 \(shown.count) 条，共 \(snapshot.history.count) 条；更早的 \(earlier) 条保存在本文件末尾的记录数据中。", ""]
        }
        for event in shown {
            let phase = event.phase == .intended ? "Intended / 拟执行" : "Completed and verified / 已完成并核验"
            lines += ["### \(date(event.occurredAt)) · \(phase) · \(eventLabel(event.kind))",
                      "- Event ID / 事件标识: \(line(event.id))", "- Profile ID / 配置标识: \(event.profileID)"]
            if let detail = event.detail { lines += ["- \(line(detail))"] }
            if let before = event.before { lines += ["Before / 之前:"] + volumeLines(before, prefix: "  - ") }
            if let after = event.after { lines += ["After / 之后:"] + volumeLines(after, prefix: "  - ") }
        }
        lines += ["<!-- AUV-SECTORIUM-HISTORY:END -->", "", "## Inspection and recovery / 检查与恢复", "",
            "Use AUV Sectorium to verify this physical parent, image, mount location, and access before using a volume. Native Disk Utility can inspect the recorded image and volume identities without erasing them. If records disagree, keep storage connected and inspect AUV's local operation history; never erase or recreate an image to fix missing metadata. Active work must finish before normal unmount and physical ejection. Automatic loading may require current macOS authorization; encrypted images may require unlocking.",
            "使用开发盘前，请在 AUV 分区工核实此物理母盘、镜像、挂载位置和访问能力。系统“磁盘工具”可检查记录中的镜像与卷身份，无须擦除。若记录不一致，请保持设备连接并检查 AUV 本地操作历史；不要为补齐元数据而擦除或重建镜像。活跃工作结束后才能正常卸载及物理弹出。自动加载可能需要当前 macOS 授权；加密镜像可能需要解锁。", "",
        ]
        if !original { lines += [recordNotice[0] + recordNotice[1], recordNotice[2] + recordNotice[3], ""] }
        lines += [notesBegin, notes, notesEnd, dataPrefix + encoded.base64EncodedString() + " -->", ""]
        return lines.joined(separator: "\n")
    }
    /// The record carried by a drive's IMPORTANT.md, read when scanning a
    /// drive AUV does not know yet. Only an unedited document AUV wrote is
    /// accepted; the caller still matches its disk ID against the drive.
    static func scannedSnapshot(_ data: Data) -> SectoriumPortableSnapshot? {
        guard data.count <= SectoriumPortableDocumentLimits.maximumBytes,
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("<!-- AUV-SECTORIUM-IMPORTANT:v2 host=") else { return nil }
        let dataLines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix(dataPrefix) }
        guard dataLines.count == 1, let dataLine = dataLines.first, dataLine.hasSuffix(" -->"),
              let encoded = Data(base64Encoded: String(dataLine.dropFirst(dataPrefix.count).dropLast(4))),
              let snapshot = try? JSONDecoder().decode(SectoriumPortableSnapshot.self, from: encoded),
              SectoriumPortableValidation.context(snapshot.context),
              parse(data, parent: snapshot.context.parent) != nil else { return nil }
        return snapshot
    }

    static func parse(_ data: Data, parent: SectoriumPortableParentRecord) -> (SectoriumPortableSnapshot, String)? {
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix("<!-- AUV-SECTORIUM-IMPORTANT:v2 host=\(parent.documentVolumeUUID.uuidString) -->\n"),
              let start = text.range(of: notesBegin + "\n"),
              let end = text.range(of: "\n" + notesEnd, range: start.upperBound..<text.endIndex) else { return nil }
        let notes = String(text[start.upperBound..<end.lowerBound])
        let dataLines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix(dataPrefix) }
        guard dataLines.count == 1, let dataLine = dataLines.first, dataLine.hasSuffix(" -->"),
              let encoded = Data(base64Encoded: String(dataLine.dropFirst(dataPrefix.count).dropLast(4))),
              encoded.count <= SectoriumPortableDocumentLimits.maximumBytes,
              let snapshot = try? JSONDecoder().decode(SectoriumPortableSnapshot.self, from: encoded),
              snapshot.context.parent.physicalID == parent.physicalID,
              snapshot.context.parent.documentVolumeUUID == parent.documentVolumeUUID,
              SectoriumPortableValidation.context(snapshot.context),
              let merged = SectoriumPortableValidation.merge([], snapshot.history), merged == snapshot.history,
              Layout.allCases.contains(where: { render(snapshot, notes: notes, layout: $0) == text }) else { return nil }
        return (snapshot, notes)
    }
}

public extension SectoriumPortableDocumentWriter {
    func update(context: SectoriumPortableDocumentContext,
                events: [SectoriumPortableDocumentEvent]) -> SectoriumPortableDocumentResult {
        guard SectoriumPortableValidation.context(context),
              let incoming = SectoriumPortableValidation.merge([], events) else {
            return .pending("Portable document context or immutable event identity is invalid")
        }
        let parent = context.parent
        let root = URL(fileURLWithPath: parent.rootPath, isDirectory: true)
        guard fileSystem.isVerifiedWritableHost(root, volumeUUID: parent.documentVolumeUUID) else {
            return .pending("Portable document host volume is not verified writable")
        }
        let target = root.appendingPathComponent("IMPORTANT.md")
        do {
            let old = try fileSystem.readRegularFile(target, limit: SectoriumPortableDocumentLimits.maximumBytes)
            var history: [SectoriumPortableDocumentEvent] = []
            var notes = SectoriumPortableV2.defaultNotes
            if let old {
                if let prior = SectoriumPortableV2.parse(old, parent: parent) {
                    history = prior.0.history; notes = prior.1
                } else if let prior = legacyPortableDocument(old, hostUUID: parent.documentVolumeUUID) {
                    history = prior.events; notes = prior.notes
                } else { return .pending("An unrelated, edited, or conflicting IMPORTANT.md was preserved") }
            }
            guard let merged = SectoriumPortableValidation.merge(history, incoming) else {
                return .pending("Portable document event identity conflicts with preserved history")
            }
            let snapshot = SectoriumPortableSnapshot(context: context, history: merged)
            let text = SectoriumPortableV2.render(snapshot, notes: notes)
            let output = Data(text.utf8)
            guard !text.isEmpty, output.count <= SectoriumPortableDocumentLimits.maximumBytes else {
                return .pending("Portable document exceeds the safe size limit; all history was preserved")
            }
            if old == output { return .unchanged }
            guard fileSystem.isVerifiedWritableHost(root, volumeUUID: parent.documentVolumeUUID) else {
                return .pending("Portable document host identity changed before writing")
            }
            try fileSystem.commit(output, to: target, expectedPrior: old)
            return .updated
        } catch { return .pending("Portable document write is pending; storage result is preserved") }
    }

    func verifiedDocumentURL(context: SectoriumPortableDocumentContext) -> URL? {
        guard SectoriumPortableValidation.context(context) else { return nil }
        let root = URL(fileURLWithPath: context.parent.rootPath, isDirectory: true)
        guard fileSystem.isVerifiedReadableHost(root, volumeUUID: context.parent.documentVolumeUUID) else { return nil }
        let target = root.appendingPathComponent("IMPORTANT.md")
        guard let data = try? fileSystem.readRegularFile(target, limit: SectoriumPortableDocumentLimits.maximumBytes),
              SectoriumPortableV2.parse(data, parent: context.parent) != nil ||
                legacyPortableDocument(data, hostUUID: context.parent.documentVolumeUUID) != nil,
              fileSystem.isVerifiedReadableHost(root, volumeUUID: context.parent.documentVolumeUUID) else { return nil }
        return target
    }

    func preservedHistory(context: SectoriumPortableDocumentContext) -> [SectoriumPortableDocumentEvent]? {
        guard SectoriumPortableValidation.context(context) else { return nil }
        let root = URL(fileURLWithPath: context.parent.rootPath, isDirectory: true)
        guard fileSystem.isVerifiedReadableHost(root, volumeUUID: context.parent.documentVolumeUUID),
              let data = try? fileSystem.readRegularFile(root.appendingPathComponent("IMPORTANT.md"),
                  limit: SectoriumPortableDocumentLimits.maximumBytes),
              fileSystem.isVerifiedReadableHost(root, volumeUUID: context.parent.documentVolumeUUID) else { return nil }
        return SectoriumPortableV2.parse(data, parent: context.parent)?.0.history
            ?? legacyPortableDocument(data, hostUUID: context.parent.documentVolumeUUID)?.events
    }

    /// Compatibility only: callers needing authoritative facts and restart-safe history
    /// use the context/event API. Do not infer actual filesystem/capacity from old profiles.
    func update(profiles: [SectoriumDevelopmentProfile], changedProfileID: String,
                event: String) -> SectoriumPortableDocumentResult {
        .pending("Portable document requires an explicit parent context and stable operation event")
    }
}
