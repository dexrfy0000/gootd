import Foundation
import AppKit
import CoreGraphics

/// The whole product, in one object: kill the two lights, bring them back.
final class DarkEngine: ObservableObject {

    static let shared = DarkEngine()

    @Published private(set) var isDark = false

    /// Whatever the backlight was doing before we took it, so coming back is
    /// a restore and not a guess.
    private var restoreLevel: Double = 1

    /// What each display's backlight was showing before we took it.
    private var restoreBrightness: [CGDirectDisplayID: Float] = [:]

    private init() {}

    func toggle() { isDark ? wake() : goDark() }

    func goDark() {
        guard !isDark else { return }
        // Capture the level even when it is zero. Skipping zero left the
        // previous (default 1) in place, so waking would switch ON a keyboard
        // light the user had deliberately off - us turning on a light nobody
        // asked for. At zero the ramp simply has nothing to move.
        if let current = Backlight.level { restoreLevel = current }
        restoreBrightness = Panel.current()
        Log.say("goDark: keyboard \(restoreLevel), displays \(restoreBrightness)")
        isDark = true
        ramp(to: 0) { [weak self] in self?.startWatching() }
    }

    func wake() {
        guard isDark else { return }
        Log.say("wake: back to keyboard \(restoreLevel), displays \(restoreBrightness)")
        stopWatching()
        isDark = false
        ramp(to: 1)
    }

    // MARK: - The ramp

    /// Both lights ride one clock, so the keyboard and the panel go out
    /// together instead of one snapping while the other slides.
    private var rampTimer: Timer?
    private var fraction: Float = 1
    private static let duration: Float = 0.42

    private func ramp(to target: Float, then finished: (() -> Void)? = nil) {
        rampTimer?.invalidate()
        let start = fraction
        let distance = target - start
        guard distance != 0 else { finished?(); return }
        let began = Date()

        let step = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Float(Date().timeIntervalSince(began))
            let progress = min(elapsed / Self.duration, 1)
            // Ease in and out, so it leaves and arrives softly rather than
            // starting at full speed.
            let eased = progress < 0.5
                ? 4 * progress * progress * progress
                : 1 - pow(-2 * progress + 2, 3) / 2
            self.set(fraction: start + distance * eased)
            if progress >= 1 {
                timer.invalidate()
                self.rampTimer = nil
                // Land exactly on the target: an eased curve that is stopped a
                // frame early leaves the panel a hair off black or off full.
                self.set(fraction: target)
                self.drivesPanel = true
                finished?()
            }
        }
        // .common, or the ramp stalls while a menu or a scroll is tracking.
        RunLoop.main.add(step, forMode: .common)
        rampTimer = step
    }

    /// Below roughly a tenth, the panel's backlight PWM stops being smooth and
    /// the last of the fade shows banding and uneven patches. Nothing below the
    /// floor is worth rendering, so the ramp cuts straight through it to black.
    private static let panelFloor: Float = 0.12

    /// False while the user is the one holding the brightness keys: the ramp
    /// still runs, but it only carries the keyboard, so nothing of ours writes
    /// over the level they are dialling in.
    private var drivesPanel = true

    private func set(fraction value: Float) {
        fraction = value
        if drivesPanel {
            Panel.apply(restoreBrightness, scaledBy: value < Self.panelFloor ? 0 : value)
        }
        Backlight.set(restoreLevel * Double(value))
    }

    // MARK: - Holding the dark

    /// Dark stays dark until YOU bring it back. macOS keeps trying to relight
    /// things on its own - auto-brightness creeping the panel up from the
    /// ambient sensor, keyboard auto-illumination, the display returning from
    /// idle sleep at its old level - and those are pushed straight back to
    /// zero. But the brightness keys are you, and fighting them made the screen
    /// blink between their level and black. So a rise that looks like a key
    /// press is handed over instead: adopt their level, leave the dark state,
    /// and the next hotkey press goes dark again rather than "waking".
    ///
    /// Telling the two apart: a brightness key moves the panel a whole step
    /// (1/16) at once, and we also see the key itself when macOS lets us.
    /// Auto-brightness only creeps, and a display wake is flagged separately.
    private var watchTimer: Timer?
    private static let externalEpsilon: Float = 0.02
    private static let keyStep: Float = 0.05
    private var lastWake = Date.distantPast
    private var lastBrightnessKey = Date.distantPast
    private var keyMonitor: Any?

    private func startWatching() {
        stopWatching()
        guard isDark else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.holdDark()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
        // Brightness keys arrive as system-defined events (subtype 8, key 2 up
        // / 3 down). If macOS withholds them, the step heuristic still works.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let key = (event.data1 & 0xFFFF0000) >> 16
            if key == 2 || key == 3 { self?.lastBrightnessKey = Date() }
        }
    }

    private func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func holdDark() {
        guard isDark, rampTimer == nil else { return }
        if let keyboard = Backlight.level, keyboard > Double(Self.externalEpsilon) {
            Log.say("keyboard backlight rose to \(keyboard) while dark; holding it at zero")
            Backlight.set(0)
        }
        let panel = Panel.highest()
        guard panel > Self.externalEpsilon else { return }

        let keyPressed = Date().timeIntervalSince(lastBrightnessKey) < 1
        let justWoke = Date().timeIntervalSince(lastWake) < 4
        if keyPressed || (panel >= Self.keyStep && !justWoke) {
            Log.say("brightness keys while dark (panel \(panel)); handing the lights back")
            handOver()
        } else {
            Log.say("panel crept to \(panel) while dark; holding it at zero")
            Panel.apply(restoreBrightness, scaledBy: 0)
        }
    }

    /// The user raised the brightness themselves: their level stands, the
    /// keyboard comes back with it, and we are no longer dark.
    private func handOver() {
        stopWatching()
        isDark = false
        restoreBrightness = Panel.current()   // whatever they dialled to
        drivesPanel = false                   // the panel is theirs for this ramp
        ramp(to: 1)
    }

    /// Straight to a value with no ramp, for quitting: there is no time for a
    /// fade when the process is about to be gone.
    func restoreImmediately() {
        rampTimer?.invalidate()
        rampTimer = nil
        stopWatching()
        guard isDark || fraction < 1 else { return }
        isDark = false
        drivesPanel = true      // on the way out, put everything back ourselves
        set(fraction: 1)
    }

    /// The display woke from idle sleep (or the lock screen) while we were
    /// dark. macOS brings the backlight back at its old level on the way up;
    /// put it back out instead of treating the wake as a request for light.
    func noteDisplayWokeExternally() {
        guard isDark else { return }
        Log.say("display woke while dark; re-applying dark")
        lastWake = Date()
        holdDark()
    }

    /// Design QA only: pose the UI in its dark state without touching hardware.
    func setDarkForPreview(_ value: Bool) { isDark = value }

}
