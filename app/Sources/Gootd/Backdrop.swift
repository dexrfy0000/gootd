import SwiftUI

/// Fine monochrome grain, generated once at launch and reused.
/// It sits on the backdrop, underneath every piece of content.
enum Grain {
    static let image: Image = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8((seed >> 33) & 0xFF)
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value
            pixels[i + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false,
                         intent: .defaultIntent)!
        return Image(decorative: cg, scale: 2)
    }()
}

/// The backdrop, rebuilt from the reference site's four layers:
///
///   1. body               `rgb(0, 0, 0)`
///   2. a starfield canvas pinned behind the page
///   3. `.page-wrapper`    `radial-gradient(circle closest-corner at 50% 0px,
///                          rgba(255,255,255,.08), rgba(255,255,255,0))`
///   4. `.grain`           a noise tile over the whole surface
///
/// Two deliberate departures from the original.
///
/// The site animates the starfield. This does not: a drifting canvas means a
/// repainting timer for as long as the window is open, and this app is supposed
/// to cost nothing while it sits there waiting for a keypress. The field is
/// generated once from a fixed seed and never touched again, so the window
/// renders and then stops doing any work at all.
///
/// And the density is raised. The site's field is tuned for a 1440-wide page;
/// carried over unchanged, a window this small would hold about five stars and
/// read as dirt on the screen rather than as a sky.
struct Backdrop: View {

    /// One star per ~900pt^2 of window. Positions and sizes come from a fixed
    /// seed, so the sky is identical on every launch and on every render.
    private static func stars(in size: CGSize) -> [(CGPoint, CGFloat, Double)] {
        var seed: UInt64 = 0x243F6A8885A308D3
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 11) & 0x1F_FFFF) / Double(0x20_0000)
        }
        let count = max(18, Int(size.width * size.height / 900))
        return (0..<count).map { _ in
            let point = CGPoint(x: next() * size.width, y: next() * size.height)
            let radius = 0.35 + next() * 0.55
            // Bias dim: a field of equally bright points reads as a pattern.
            let brightness = 0.14 + pow(next(), 1.7) * 0.46
            return (point, radius, brightness)
        }
    }

    var body: some View {
        // The whole stack is decorative. It must never intercept a click meant
        // for the control sitting on top of it.
        ZStack {
            UI.background

            Canvas { context, size in
                for (point, radius, brightness) in Self.stars(in: size) {
                    let dot = CGRect(x: point.x - radius, y: point.y - radius,
                                     width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dot),
                                 with: .color(.white.opacity(brightness)))
                }
            }

            // The light from the top edge. `closest-corner at 50% 0` measures to
            // the two top corners, so the radius is exactly half the width.
            GeometryReader { geometry in
                RadialGradient(
                    gradient: Gradient(colors: [.white.opacity(0.08), .white.opacity(0)]),
                    center: .top,
                    startRadius: 0,
                    endRadius: geometry.size.width / 2
                )
            }

            // Screen, not overlay: over a black base an overlay blend resolves
            // back to black and the grain simply does not exist. Screen lifts it
            // just enough to give the surface a substrate and to keep the
            // radial above from banding as it falls off.
            //
            // Tiled, not stretched. Scaling one 64pt noise tile up to the window
            // turns fine grain into soft blotches, which is the opposite of the
            // effect - the point is a texture you feel and cannot resolve.
            Canvas { context, size in
                context.blendMode = .screen
                context.opacity = 0.05
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .tiledImage(Grain.image))
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
