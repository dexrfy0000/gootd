import Foundation

/// Diagnostics for the two OS surfaces this app depends on. Both Carbon hotkey
/// registration and the display wrangler fail by returning a status code, not
/// by throwing, so a silent failure is indistinguishable from success unless
/// the codes are actually printed.
///
/// Quiet by default; set GOOTD_DEBUG=1 to turn it on.
enum Log {

    private static let enabled = ProcessInfo.processInfo.environment["GOOTD_DEBUG"] != nil

    static func say(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write("gootd: \(message())\n".data(using: .utf8)!)
    }

    /// Carbon/OSStatus, with the handful of codes that actually come up here.
    static func status(_ code: OSStatus) -> String {
        switch code {
        case 0:        return "ok"
        case -9868:    return "eventHotKeyExistsErr (-9868): that combination is already taken by another app or by the system"
        case -9870:    return "eventHotKeyInvalidErr (-9870)"
        case -50:      return "paramErr (-50)"
        default:       return "OSStatus \(code)"
        }
    }

    /// kern_return_t from IOKit.
    static func mach(_ code: kern_return_t) -> String {
        switch UInt32(bitPattern: code) {
        case 0:          return "ok"
        case 0xE00002C1: return "kIOReturnNotPrivileged (0xe00002c1): needs more privilege than this process has"
        case 0xE00002C2: return "kIOReturnBadArgument (0xe00002c2)"
        case 0xE00002BC: return "kIOReturnUnsupported (0xe00002bc)"
        default:         return String(format: "kern_return_t 0x%08x", UInt32(bitPattern: code))
        }
    }
}
