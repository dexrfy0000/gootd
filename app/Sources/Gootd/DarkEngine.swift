import Foundation
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

    // MARK: - Somebody reached for the brightness keys

    /// Holding the panel at zero means the brightness keys still work: press
    /// brightness-up while dark and the screen comes back, but nothing told us,
    /// so we sat there still believing we were dark and still holding a
    /// fraction of zero. The next press of the hotkey then slammed the panel
    /// from what they had dialled in back down to black before ramping up - the
    /// flicker. So watch the panel while dark, and the moment it rises under us,
    /// hand it over: adopt their level, leave the dark state, and bring only the
    /// keyboard back up so we are never fighting them for the same control.
    private var watchTimer: Timer?
    private static let externalEpsilon: Float = 0.02

    private func startWatching() {
        stopWatching()
        guard isDark else { return }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkForExternalChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private func checkForExternalChange() {
        guard isDark else { stopWatching(); return }

        // The keyboard keys are the cheap half: adopt whatever they set so that
        // coming back does not yank the light off the level they just chose.
        if let keyboard = Backlight.level, keyboard > Double(Self.externalEpsilon) {
            Log.say("keyboard backlight raised externally to \(keyboard); adopting it")
            restoreLevel = keyboard
        }

        guard Panel.highest() > Self.externalEpsilon else { return }
        Log.say("brightness raised externally; handing the panel back")
        stopWatching()
        isDark = false
        restoreBrightness = Panel.current()   // whatever they have dialled to
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

    /// Called if the screen comes back any other way, so our state cannot
    /// drift out of sync with the hardware. It must restore BOTH lights: the
    /// panel is held at zero brightness rather than asleep, so bringing back
    /// only the keyboard would leave a black screen with no way out.
    func noteDisplayWokeExternally() {
        guard isDark else { return }
        Log.say("display woke externally")
        stopWatching()
        wake()
    }

    /// Design QA only: pose the UI in its dark state without touching hardware.
    func setDarkForPreview(_ value: Bool) { isDark = value }

}
