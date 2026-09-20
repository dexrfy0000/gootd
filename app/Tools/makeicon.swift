import Foundation
import AppKit

// Draws the Gootd icon: the lid gap, seen straight on. Same artifact as the
// app and the site, so the mark belongs to the brand rather than sitting beside it.
func draw(size: CGFloat) -> Data {
    let px = Int(size)
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    // macOS icons live on a squircle inset from the canvas.
    let m = size * 0.085
    let rect = CGRect(x: m, y: m, width: size - 2 * m, height: size - 2 * m)
    let body = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.223,
                      cornerHeight: rect.width * 0.223, transform: nil)
    ctx.addPath(body)
    ctx.clip()

    ctx.setFillColor(CGColor(red: 0.043, green: 0.039, blue: 0.035, alpha: 1))
    ctx.fill(rect)

    let slitY = rect.minY + rect.height * 0.545   // CG origin is bottom-left
    let sodium = (r: CGFloat(1.0), g: CGFloat(0.745), b: CGFloat(0.404))
    func sodiumColor(_ a: CGFloat) -> CGColor {
        CGColor(red: sodium.r, green: sodium.g, blue: sodium.b, alpha: a)
    }

    // Spill downwards onto the deck. Kept short and weak: this has to read as
    // light thrown from a gap, never as a brown wash filling the tile.
    let down = CGGradient(colorsSpace: space, colors: [
        sodiumColor(0.30), sodiumColor(0.055), sodiumColor(0.0)
    ] as CFArray, locations: [0, 0.34, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: slitY - rect.minY))
    ctx.drawLinearGradient(down, start: CGPoint(x: 0, y: slitY),
                           end: CGPoint(x: 0, y: slitY - rect.height * 0.46), options: [])
    ctx.restoreGState()

    // Shorter throw up the inside of the lid.
    let up = CGGradient(colorsSpace: space, colors: [
        sodiumColor(0.15), sodiumColor(0.0)
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: rect.minX, y: slitY, width: rect.width, height: rect.maxY - slitY))
    ctx.drawLinearGradient(up, start: CGPoint(x: 0, y: slitY),
                           end: CGPoint(x: 0, y: slitY + rect.height * 0.26), options: [])
    ctx.restoreGState()

    // The gap itself, drawn as a shallow lens: widest where the lid is lifted
    // at the front, closing to nothing at each hinge. Never a ruled hairline.
    let inset = rect.width * 0.085
    let x0 = rect.minX + inset, x1 = rect.maxX - inset
    let half = max(size * 0.0145, 0.75)
    let lens = CGMutablePath()
    lens.move(to: CGPoint(x: x0, y: slitY))
    lens.addCurve(to: CGPoint(x: x1, y: slitY),
                  control1: CGPoint(x: x0 + (x1 - x0) * 0.3, y: slitY + half),
                  control2: CGPoint(x: x0 + (x1 - x0) * 0.7, y: slitY + half))
    lens.addCurve(to: CGPoint(x: x0, y: slitY),
                  control1: CGPoint(x: x0 + (x1 - x0) * 0.7, y: slitY - half),
                  control2: CGPoint(x: x0 + (x1 - x0) * 0.3, y: slitY - half))
    lens.closeSubpath()

    let core = CGGradient(colorsSpace: space, colors: [
        sodiumColor(0.75),
        CGColor(red: 1, green: 0.90, blue: 0.76, alpha: 1),
        CGColor(red: 1, green: 0.99, blue: 0.96, alpha: 1),
        CGColor(red: 1, green: 0.90, blue: 0.76, alpha: 1),
        sodiumColor(0.75)
    ] as CFArray, locations: [0, 0.22, 0.5, 0.78, 1])!
    ctx.saveGState()
    ctx.addPath(lens)
    ctx.clip()
    ctx.drawLinearGradient(core, start: CGPoint(x: x0, y: 0), end: CGPoint(x: x1, y: 0), options: [])
    ctx.restoreGState()

    // The lip of light along the top edge of the body.
    ctx.resetClip()
    ctx.addPath(body)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(max(size * 0.006, 1))
    ctx.strokePath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
for s in [16, 32, 64, 128, 256, 512, 1024] {
    try! draw(size: CGFloat(s)).write(to: URL(fileURLWithPath: "\(out)/icon_\(s).png"))
}
print("icons written")
