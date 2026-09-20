import SwiftUI
import AppKit

/// One thing: the key that does the work.
///
/// The name is gone too now - the window is a binding and nothing else, and a
/// wordmark sitting over a single control was decoration, not information.
struct AppView: View {

    @ObservedObject var hotkeys = HotKeyCenter.shared

    var body: some View {
        ShortcutField(hotkeys: hotkeys)
            // 46 at the top clears the traffic lights, which sit in the content
            // area once the titlebar goes transparent, and leaves a clear band
            // of backdrop between them and the field. 18 on the sides, 20 at
            // the bottom, so the field sits optically centred in what is left.
            .padding(.top, 46)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Backdrop())
    }
}

/// The binding, as one shadcn field: key caps on the left, the state of the
/// control on the right. Click it, press a combination, it takes.
private struct ShortcutField: View {

    @ObservedObject var hotkeys: HotKeyCenter
    @State private var monitor: Any?
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
    }

    /// Registration failing is the one thing this window must still be able to
    /// say: the caps would otherwise show a combination that never fires.
    private var failed: Bool { !hotkeys.isRecording && hotkeys.lastRegistration != 0 }

    private var hint: String {
        if hotkeys.isRecording { return "Listening" }
        if hotkeys.lastRegistration == -9868 { return "Taken, pick another" }
        if failed { return "Not registered" }
        return "Click to rebind"
    }

    var body: some View {
        HStack(spacing: 6) {
            if hotkeys.isRecording {
                Text("Press a combination")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.mutedForeground)
            } else {
                ForEach(Array(hotkeys.shortcut.tokens.enumerated()), id: \.offset) { _, token in
                    KeyCap(token)
                }
            }

            Spacer(minLength: 10)

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(failed ? UI.foreground : UI.mutedForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(shape.fill(hovering && !hotkeys.isRecording ? UI.cardHover : UI.card))
        .overlay(
            shape.strokeBorder(
                hotkeys.isRecording || failed ? UI.borderStrong : UI.border,
                lineWidth: 1
            )
        )
        // shadcn's focus ring: a 3px band at half opacity sitting outside the
        // border, not a glow. It is drawn only while recording, so nothing on
        // this window carries a resting halo.
        .overlay(
            shape
                .inset(by: -2.5)
                .strokeBorder(UI.ring.opacity(hotkeys.isRecording ? 0.5 : 0), lineWidth: 3)
        )
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { hotkeys.isRecording ? stop() : start() }
        .animation(Motion.ease(0.18), value: hovering)
        .animation(Motion.ease(0.18), value: hotkeys.isRecording)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Shortcut")
        .accessibilityValue(hotkeys.isRecording
                            ? "Recording. Press a combination."
                            : hotkeys.shortcut.display)
        .onDisappear(perform: stop)
    }

    private func start() {
        guard monitor == nil else { return }
        hotkeys.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }
            if event.keyCode == 53 { stop(); return nil }          // escape cancels
            if let shortcut = Shortcut(event: event) {
                hotkeys.shortcut = shortcut
                stop()
            }
            return nil                                              // never let it type
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotkeys.isRecording = false
    }
}

/// One physical key. A square-ish cap for a modifier glyph, widening only as
/// far as a longer legend ("esc", "F12") actually needs.
private struct KeyCap: View {

    private let legend: String
    init(_ legend: String) { self.legend = legend }

    var body: some View {
        Text(legend)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(UI.foreground)
            .lineLimit(1)
            .padding(.horizontal, 5)
            // A fixed height with the text centred on both axes, and a minimum
            // width so a single glyph still reads as a square cap rather than a
            // sliver. Verified by measuring the rendered pixels, not by eye.
            .frame(minWidth: 26, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: UI.radiusInner, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UI.radiusInner, style: .continuous)
                    .strokeBorder(UI.border, lineWidth: 1)
            )
    }
}
