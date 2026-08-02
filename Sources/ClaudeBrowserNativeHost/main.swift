import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Darwin
import Foundation

private enum NativeHostExit: Int32 {
    case success = 0
    case rejected = 2
    case unavailable = 3
}

@main
enum ClaudeBrowserNativeHostMain {
    static func main() {
        guard CommandLine.arguments.count >= 2,
              ClaudeBrowserMessageDecoder.isAllowedChromiumOrigin(CommandLine.arguments[1])
        else {
            respond(ok: false)
            Darwin.exit(NativeHostExit.rejected.rawValue)
        }

        do {
            let frame = try readNativeFrame()
            let payload = try ClaudeBrowserNativeMessagingFrame.decode(frame)
            let envelope = try ClaudeBrowserMessageDecoder.decode(payload)
            guard envelope.browserFamily == .chromium else {
                throw ClaudeBrowserBridgeError.invalidContract
            }
            try ClaudeBrowserFileHandoffWriter.write(payload)
            respond(ok: true)
            Darwin.exit(NativeHostExit.success.rawValue)
        } catch {
            respond(ok: false)
            Darwin.exit(NativeHostExit.unavailable.rawValue)
        }
    }

    private static func readNativeFrame() throws -> Data {
        let header = try readExactly(ClaudeBrowserNativeMessagingFrame.headerByteCount)
        let length = header.withUnsafeBytes { bytes -> UInt32 in
            var value: UInt32 = 0
            memcpy(&value, bytes.baseAddress, ClaudeBrowserNativeMessagingFrame.headerByteCount)
            return UInt32(littleEndian: value)
        }
        guard length > 0, Int(length) <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.nativeMessagingFrameMalformed
        }
        var frame = header
        frame.append(try readExactly(Int(length)))
        return frame
    }

    private static func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let readCount = data.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return -1 }
            var offset = 0
            while offset < count {
                let current = Darwin.read(STDIN_FILENO, base.advanced(by: offset), count - offset)
                guard current > 0 else { return -1 }
                offset += current
            }
            return offset
        }
        guard readCount == count else { throw ClaudeBrowserBridgeError.socketReadFailed }
        return data
    }

    private static func respond(ok: Bool) {
        let payload = Data(ok ? #"{"ok":true}"#.utf8 : #"{"ok":false}"#.utf8)
        guard let frame = try? ClaudeBrowserNativeMessagingFrame.encode(payload) else { return }
        frame.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(STDOUT_FILENO, base.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}
