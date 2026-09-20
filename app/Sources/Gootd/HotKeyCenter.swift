import AppKit
import Carbon.HIToolbox

/// Registers the global hotkey through Carbon, which is the one route that
/// still works with no Accessibility permission and no prompt on first launch.
final class HotKeyCenter: ObservableObject {

    static let shared = HotKeyCenter()

    @Published var shortcut: Shortcut {
        didSet {
            guard shortcut != oldValue else { return }
            persist()
            register()
        }
    }

    /// True while the UI is listening for a new combination; the global hotkey
    /// stays unregistered during that window so it cannot fire on itself.
    @Published var isRecording = false {
        didSet { isRecording ? unregister() : register() }
    }

    var onFire: (() -> Void)?

    /// Non-zero when the last registration attempt failed, so the UI can say so
    /// instead of presenting a shortcut that will never fire.
    @Published private(set) var lastRegistration: OSStatus = 0

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature = OSType(0x474F_4F54) // 'GOOT'
    private static let defaultsKey = "shortcut"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
    }

    // MARK: - Registration

    func start() {
        installHandler()
        register()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            Log.say("hotkey fired")
            DispatchQueue.main.async { center.onFire?() }
            return noErr
        }, 1, &spec, context, &handler)
        Log.say("installHandler: \(Log.status(status))")
    }

    private func register() {
        unregister()
        guard !isRecording else { return }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &reference)
        lastRegistration = status
        Log.say("register \(shortcut.display) (keyCode \(shortcut.keyCode), "
                + "carbonModifiers \(shortcut.carbonModifiers)): \(Log.status(status))")
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
