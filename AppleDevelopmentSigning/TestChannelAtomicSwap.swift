import Darwin
import Foundation

enum AtomicSwapError: Error, CustomStringConvertible {
    case usage
    case sourceMissing(String)
    case symbolicLink(String)
    case differentParentDirectories
    case layoutMismatch(String)
    case preservedExtensionChanged
    case systemCall(String, Int32)

    var description: String {
        switch self {
        case .usage:
            return "usage: TestChannelAtomicSwap [--preserve-nested-extension] <staged-app> <canonical-app>"
        case let .sourceMissing(path):
            return "staged app is missing: \(path)"
        case let .symbolicLink(path):
            return "symbolic links are forbidden: \(path)"
        case .differentParentDirectories:
            return "staged and canonical apps must have the same parent directory"
        case let .layoutMismatch(path):
            return "staged and canonical layouts differ at: \(path)"
        case .preservedExtensionChanged:
            return "APP_ONLY update replaced the frozen nested extension filesystem identity"
        case let .systemCall(name, code):
            return "\(name) failed with errno \(code)"
        }
    }
}

private let fileManager = FileManager.default
private let preservedExtension = "Contents/PlugIns/ClaudeBrowserCompanion.appex"

private func metadata(at path: String) throws -> stat? {
    var value = stat()
    if lstat(path, &value) == 0 {
        if (value.st_mode & S_IFMT) == S_IFLNK {
            throw AtomicSwapError.symbolicLink(path)
        }
        return value
    }
    if errno == ENOENT {
        return nil
    }
    throw AtomicSwapError.systemCall("lstat", errno)
}

private func requireDirectory(_ url: URL, source: Bool = false) throws -> stat {
    guard let value = try metadata(at: url.path), (value.st_mode & S_IFMT) == S_IFDIR else {
        if source { throw AtomicSwapError.sourceMissing(url.path) }
        throw AtomicSwapError.layoutMismatch(url.path)
    }
    return value
}

private func entryNames(at url: URL) throws -> [String] {
    try fileManager.contentsOfDirectory(atPath: url.path).sorted()
}

private func exchange(_ first: URL, _ second: URL) throws {
    guard let firstMetadata = try metadata(at: first.path),
          let secondMetadata = try metadata(at: second.path),
          (firstMetadata.st_mode & S_IFMT) == (secondMetadata.st_mode & S_IFMT)
    else {
        throw AtomicSwapError.layoutMismatch(first.path)
    }
    let result = first.path.withCString { firstPointer in
        second.path.withCString { secondPointer in
            renameatx_np(
                AT_FDCWD,
                firstPointer,
                AT_FDCWD,
                secondPointer,
                UInt32(RENAME_SWAP)
            )
        }
    }
    guard result == 0 else {
        throw AtomicSwapError.systemCall("renameatx_np", errno)
    }
}

private func exchangeMatchingChildren(
    staged: URL,
    canonical: URL,
    excluding excludedName: String? = nil,
    exchanged: inout [(URL, URL)]
) throws {
    let stagedNames = try entryNames(at: staged).filter { $0 != excludedName }
    let canonicalNames = try entryNames(at: canonical).filter { $0 != excludedName }
    guard stagedNames == canonicalNames else {
        throw AtomicSwapError.layoutMismatch(canonical.path)
    }
    for name in stagedNames {
        let pair = (staged.appendingPathComponent(name), canonical.appendingPathComponent(name))
        try exchange(pair.0, pair.1)
        exchanged.append(pair)
    }
}

private func installPreservingNestedExtension(staged: URL, canonical: URL) throws {
    let stagedContents = staged.appendingPathComponent("Contents", isDirectory: true)
    let canonicalContents = canonical.appendingPathComponent("Contents", isDirectory: true)
    let stagedPlugins = stagedContents.appendingPathComponent("PlugIns", isDirectory: true)
    let canonicalPlugins = canonicalContents.appendingPathComponent("PlugIns", isDirectory: true)
    _ = try requireDirectory(stagedContents, source: true)
    _ = try requireDirectory(canonicalContents)
    _ = try requireDirectory(stagedPlugins, source: true)
    _ = try requireDirectory(canonicalPlugins)

    let stagedExtension = staged.appendingPathComponent(preservedExtension, isDirectory: true)
    let canonicalExtension = canonical.appendingPathComponent(preservedExtension, isDirectory: true)
    _ = try requireDirectory(stagedExtension, source: true)
    let originalExtensionMetadata = try requireDirectory(canonicalExtension)

    var exchanged: [(URL, URL)] = []
    do {
        // Keep the canonical app, Contents, PlugIns, and frozen appex directory
        // identities stable. Exchange only the containing app's other signed
        // children, with complete reverse-order rollback on failure.
        try exchangeMatchingChildren(
            staged: staged,
            canonical: canonical,
            excluding: "Contents",
            exchanged: &exchanged
        )
        try exchangeMatchingChildren(
            staged: stagedContents,
            canonical: canonicalContents,
            excluding: "PlugIns",
            exchanged: &exchanged
        )
        try exchangeMatchingChildren(
            staged: stagedPlugins,
            canonical: canonicalPlugins,
            excluding: "ClaudeBrowserCompanion.appex",
            exchanged: &exchanged
        )
    } catch {
        for pair in exchanged.reversed() {
            try? exchange(pair.0, pair.1)
        }
        throw error
    }

    let finalExtensionMetadata = try requireDirectory(canonicalExtension)
    guard originalExtensionMetadata.st_dev == finalExtensionMetadata.st_dev,
          originalExtensionMetadata.st_ino == finalExtensionMetadata.st_ino
    else {
        for pair in exchanged.reversed() {
            try? exchange(pair.0, pair.1)
        }
        throw AtomicSwapError.preservedExtensionChanged
    }
    print("APP_ONLY_IN_PLACE_UPDATE preserved_extension_inode=true swaps=\(exchanged.count)")
}

do {
    let preserveNestedExtension = CommandLine.arguments.count == 4
        && CommandLine.arguments[1] == "--preserve-nested-extension"
    let pathOffset = preserveNestedExtension ? 2 : 1
    guard CommandLine.arguments.count == pathOffset + 2 else {
        throw AtomicSwapError.usage
    }

    let staged = URL(fileURLWithPath: CommandLine.arguments[pathOffset]).standardizedFileURL
    let canonical = URL(fileURLWithPath: CommandLine.arguments[pathOffset + 1]).standardizedFileURL
    guard staged.deletingLastPathComponent() == canonical.deletingLastPathComponent() else {
        throw AtomicSwapError.differentParentDirectories
    }
    _ = try requireDirectory(staged, source: true)

    if preserveNestedExtension {
        _ = try requireDirectory(canonical)
        try installPreservingNestedExtension(staged: staged, canonical: canonical)
    } else {
        let destinationType = try metadata(at: canonical.path)
        let result: Int32
        if destinationType == nil {
            result = staged.path.withCString { sourcePointer in
                canonical.path.withCString { destinationPointer in
                    rename(sourcePointer, destinationPointer)
                }
            }
        } else {
            guard (destinationType!.st_mode & S_IFMT) == S_IFDIR else {
                throw AtomicSwapError.systemCall("destination-not-directory", ENOTDIR)
            }
            result = staged.path.withCString { sourcePointer in
                canonical.path.withCString { destinationPointer in
                    renameatx_np(
                        AT_FDCWD,
                        sourcePointer,
                        AT_FDCWD,
                        destinationPointer,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
        }
        guard result == 0 else {
            throw AtomicSwapError.systemCall(destinationType == nil ? "rename" : "renameatx_np", errno)
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
