import Darwin
import Foundation

enum SwapError: Error { case usage, unsafe(String), system(Int32) }
func metadata(_ path: String) throws -> stat? {
    var value = stat()
    if lstat(path, &value) == 0 {
        guard value.st_mode & S_IFMT != S_IFLNK else { throw SwapError.unsafe(path) }
        return value
    }
    if errno == ENOENT { return nil }
    throw SwapError.system(errno)
}
do {
    guard CommandLine.arguments.count == 3 else { throw SwapError.usage }
    let staged = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let target = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    guard staged.deletingLastPathComponent() == target.deletingLastPathComponent(),
          let source = try metadata(staged.path), source.st_mode & S_IFMT == S_IFDIR
    else { throw SwapError.unsafe(staged.path) }
    let existing = try metadata(target.path)
    let result = staged.path.withCString { sourcePointer in
        target.path.withCString { targetPointer in
            existing == nil
                ? rename(sourcePointer, targetPointer)
                : renameatx_np(AT_FDCWD, sourcePointer, AT_FDCWD, targetPointer, UInt32(RENAME_SWAP))
        }
    }
    guard result == 0 else { throw SwapError.system(errno) }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
}
