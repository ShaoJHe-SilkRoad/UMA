import ClaudeBrowserBridgeProtocol
import Foundation

public enum ClaudeBrowserNativeMessagingFrame {
    public static let headerByteCount = 4

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw ClaudeBrowserBridgeError.messageEmpty }
        guard payload.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        var length = UInt32(payload.count).littleEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(payload)
        return framed
    }

    public static func decode(_ frame: Data) throws -> Data {
        guard frame.count >= headerByteCount else {
            throw ClaudeBrowserBridgeError.nativeMessagingFrameMalformed
        }
        let length = frame.prefix(headerByteCount).withUnsafeBytes { bytes -> UInt32 in
            var value: UInt32 = 0
            memcpy(&value, bytes.baseAddress, headerByteCount)
            return UInt32(littleEndian: value)
        }
        guard length > 0,
              Int(length) <= ClaudeBrowserBridgeContract.maximumMessageBytes,
              frame.count == headerByteCount + Int(length)
        else {
            throw ClaudeBrowserBridgeError.nativeMessagingFrameMalformed
        }
        return frame.dropFirst(headerByteCount)
    }
}
