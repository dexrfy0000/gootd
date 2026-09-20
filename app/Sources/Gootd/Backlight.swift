import Foundation

/// The internal keyboard's backlight, via CoreBrightness.
///
/// The obvious route - IOHIDServiceClientSetProperty with "KeyboardBacklight"
/// or "KeyboardBacklightBrightness" - is a trap. Those properties sit on a
/// service whose IOClass is IOHIDSystem, the legacy compatibility shim: it
/// stores whatever you write and hands it straight back, with nothing attached
/// on the far side. Every write returned true, every read agreed, and the
/// keyboard never changed. The giveaway was that the shim read 0 while the
/// keyboard was visibly lit; CoreBrightness reads 1.0, which is the truth.
enum Backlight {

    @objc private protocol KeyboardBrightness {
        func copyKeyboardBacklightIDs() -> NSArray?
        func brightnessForKeyboard(_ id: UInt64) -> Float
        func setBrightness(_ brightness: Float, forKeyboard id: UInt64) -> Bool
        func isKeyboardBuiltIn(_ id: UInt64) -> Bool
    }

    /// CoreBrightness is not linked by default; without this the class lookup
    /// simply returns nil.
    private static let resolved: (client: KeyboardBrightness, id: UInt64)? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                     RTLD_NOW) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else {
            Log.say("backlight: CoreBrightness unavailable")
            return nil
        }
        let client = unsafeBitCast(type.init(), to: KeyboardBrightness.self)
        guard let ids = client.copyKeyboardBacklightIDs() as? [NSNumber] else { return nil }
        // Built in only: an external keyboard's backlight is not ours to take.
        guard let id = ids.map({ $0.uint64Value }).first(where: { client.isKeyboardBuiltIn($0) })
        else {
            Log.say("backlight: no built-in backlit keyboard among \(ids.count)")
            return nil
        }
        Log.say("backlight: keyboard \(id), at \(client.brightnessForKeyboard(id))")
        return (client, id)
    }()

    /// False where there is no controllable internal backlight. The UI reports
    /// this rather than lying.
    static var isAvailable: Bool { resolved != nil }

    static var level: Double? {
        guard let resolved else { return nil }
        return Double(resolved.client.brightnessForKeyboard(resolved.id))
    }

    @discardableResult
    static func set(_ newLevel: Double) -> Bool {
        guard let resolved else { return false }
        let clamped = Float(min(max(newLevel, 0), 1))
        return resolved.client.setBrightness(clamped, forKeyboard: resolved.id)
    }
}
