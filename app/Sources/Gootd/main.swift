import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyCenter.shared.onFire = { DarkEngine.shared.toggle() }
        HotKeyCenter.shared.start()

        // If the screen comes back any other way - a keypress, the trackpad -
        // our state would otherwise lie, and the backlight would stay at zero.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { _ in DarkEngine.shared.noteDisplayWokeExternally() }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 112),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Gootd"
        // Closing the window must not free it: the app deliberately outlives its
        // window so the hotkey keeps working, and reopening from the Dock would
        // otherwise message a released object and take the whole app down.
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // Matches UI.background, so the window never flashes a different tone
        // behind the view while it is being sized or moved.
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        // Nothing may be added to the titlebar - not a toolbar, not an
        // accessory view. Both make it taller, but both also push the content
        // view down, which lays a flat strip across the top of the window and
        // breaks the one thing that matters here: the backdrop running
        // unbroken to every edge, including behind the buttons.
        //
        // And the traffic lights are left exactly where AppKit puts them.
        // Moving their frames by hand does move the drawing, but the titlebar
        // keeps hit-testing them at their original rects, so they light up and
        // respond in one place while appearing in another. The room they need
        // is made below them, by the window's top gutter, not by shifting them.

        // Only for windowWillClose. Nothing here touches the titlebar or its
        // buttons - that is what broke their hit-testing last time.
        window.delegate = self
        window.contentView = NSHostingView(rootView: AppView())
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window must not kill the hotkey - that is the whole app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Closing the window drops the app out of the Dock and the app switcher
    /// entirely, so it keeps listening for the hotkey with nothing on screen
    /// and nothing to tab through - it is a key binding, not something you
    /// leave open. `.accessory` is the policy for exactly that: a process with
    /// no Dock tile that can still own windows when it needs to.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// And launching the app again is the way back in: macOS routes a second
    /// open of a running app here rather than starting a new copy, so the
    /// window returns and the Dock tile comes back with it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave someone with a dead screen because they quit while dark.
        DarkEngine.shared.restoreImmediately()
    }
}

// Offscreen render of the window, for design QA and regression shots:
//   GOOTD_RENDER=/path/shot.png ./Gootd   (optionally GOOTD_RENDER_DARK=1)
@MainActor
func renderPreview(to path: String, dark: Bool) {
    if dark { DarkEngine.shared.setDarkForPreview(true) }
    let renderer = ImageRenderer(
        content: AppView().frame(width: 310, height: 112).environment(\.colorScheme, .dark)
    )
    renderer.scale = 2
    if let image = renderer.cgImage,
       let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

if let path = ProcessInfo.processInfo.environment["GOOTD_RENDER"] {
    MainActor.assumeIsolated {
        renderPreview(to: path, dark: ProcessInfo.processInfo.environment["GOOTD_RENDER_DARK"] != nil)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

/// Ctrl-C from a terminal, or a kill, never reaches applicationWillTerminate,
/// so without this the backlight stays at zero after the process is gone and
/// the next run finds nothing left to turn off. Trap both and restore first.
let signals: [Int32] = [SIGINT, SIGTERM]
let signalSources = signals.map { number -> DispatchSourceSignal in
    signal(number, SIG_IGN)          // the source only fires if the default dies
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        Log.say("caught signal \(number), restoring before exit")
        DarkEngine.shared.restoreImmediately()
        exit(0)
    }
    source.resume()
    return source
}
_ = signalSources

/// The same hazard one level worse: if the app CRASHES while dark, nothing
/// restores the panel and the screen stays black with no process left to fix
/// it. Calling into frameworks from a signal handler is not strictly
/// async-signal-safe, but this path is already dying, and a best-effort
/// restore beats leaving someone in the dark. The default handler is put back
/// and the signal re-raised, so the crash still reports normally.
for number in [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT] {
    signal(number) { number in
        DarkEngine.shared.restoreImmediately()
        signal(number, SIG_DFL)
        raise(number)
    }
}

/// A minimal menu, so Quit, Hide and Close have their standard keys.
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Hide Gootd", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "Quit Gootd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
let windowMenuItem = NSMenuItem()
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowMenuItem.submenu = windowMenu
mainMenu.addItem(windowMenuItem)
app.mainMenu = mainMenu

app.run()
