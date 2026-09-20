import SwiftUI
import AppKit

/// The design system, rebuilt on shadcn's dark neutral scale.
///
/// shadcn stores these as oklch; the hex below is the straight conversion of
/// the `.dark` block, with one deliberate change: the background is pure black
/// rather than oklch(0.145 0 0), because the backdrop this app sits on is the
/// one from the reference site and that page's body is #000.
///
/// The alpha values are not approximations either - shadcn's dark `--border` is
/// literally `oklch(1 0 0 / 10%)` and `--input` is `oklch(1 0 0 / 15%)`, which
/// is the same white-over-black scale the reference site builds its surfaces
/// from. The two systems agree, so there is one set of tokens, not two.
enum UI {

    // Surfaces
    static let background = Color.black
    /// shadcn `--card` over a black base, matching the reference's 3% fills.
    static let card       = Color.white.opacity(0.03)
    static let cardHover  = Color.white.opacity(0.05)

    // Ink. Measured against the background further down this file.
    static let foreground      = Color(red: 0.980, green: 0.980, blue: 0.980)  // #FAFAFA
    static let mutedForeground = Color(red: 0.710, green: 0.710, blue: 0.710)  // #B5B5B5

    // Lines
    static let border      = Color.white.opacity(0.10)   // --border
    static let borderStrong = Color.white.opacity(0.15)  // --input
    static let ring        = Color(red: 0.541, green: 0.541, blue: 0.541)  // #8A8A8A

    /// shadcn v4's `--radius` is 0.625rem. The inner radius for a nested
    /// element is `--radius - 4px`, which is where the key caps get theirs.
    static let radius: CGFloat = 10
    static let radiusInner: CGFloat = 6
}

/// System-wide reduced-motion, honoured by every animation in the app.
enum Motion {
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static func ease(_ duration: Double) -> Animation? {
        reduced ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
}
