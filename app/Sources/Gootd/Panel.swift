import Foundation
import CoreGraphics

/// The display panel's own backlight.
///
/// The obvious route - asking IODisplayWrangler for IORequestIdle, which is
/// what `pmset displaysleepnow` does - reports success on Apple silicon and
/// then leaves the panel lit. Verified on an M4: `IORequestIdle -> ok`, screen
/// still on. It is an Intel-era path.
///
/// DisplayServices drives the backlight directly, which is better suited to
/// this product anyway: the display never sleeps, so there is no sleep/wake
/// cycle to fight, no UserIsActive assertion to hold, restoring is instant,
/// and a stray keypress does not undo it.
enum Panel {

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    /// DisplayServices is not linked by default, so the symbols only resolve
    /// once the framework is in the process. Skipping this dlopen makes every
    /// lookup return nil.
    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        _ = handle
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(p, to: type)
    }

    private static let getBrightness = symbol("DisplayServicesGetBrightness", as: GetFn.self)
    private static let setBrightness = symbol("DisplayServicesSetBrightness", as: SetFn.self)

    static var isAvailable: Bool { getBrightness != nil && setBrightness != nil }

    /// Every attached display, so an external monitor goes out too.
    private static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func level(_ display: CGDirectDisplayID) -> Float? {
        guard let get = getBrightness else { return nil }
        var value: Float = -1
        guard get(display, &value) == 0, value >= 0 else { return nil }
        return value
    }

    /// What every attached display is showing right now. A display already at
    /// zero has nothing worth restoring to, so it is held at full instead of
    /// the dark we are about to apply.
    static func current() -> [CGDirectDisplayID: Float] {
        var levels: [CGDirectDisplayID: Float] = [:]
        for display in displays() {
            let value = level(display) ?? 1
            levels[display] = value > 0 ? value : 1
        }
        return levels
    }

    /// The brightest thing attached right now. Used while dark to notice that
    /// somebody reached for the brightness keys.
    static func highest() -> Float {
        displays().compactMap(level).max() ?? 0
    }

    /// One step of the ramp: every display scaled by the same fraction, so a
    /// laptop panel and an external monitor go out together.
    static func apply(_ levels: [CGDirectDisplayID: Float], scaledBy fraction: Float) {
        guard let set = setBrightness else { return }
        // Walk what is attached NOW, not what was attached when we went dark.
        // Iterating the captured dictionary left a monitor plugged in mid-dark
        // sitting at full brightness with no way for the ramp to reach it.
        for display in displays() { _ = set(display, (levels[display] ?? 1) * fraction) }
    }
}
