// Draws the disk-image backdrop: the same four layers the app's window sits on
// (black, a fixed starfield, the light from the top edge, grain), plus the one
// piece of guidance an installer window owes you - a line running from the app
// to the folder it belongs in.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 620, height = 400
let scale = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1
let w = width * scale, h = height * scale
let s = CGFloat(scale)

let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

// The starfield, from the same fixed seed the app uses, so the two skies are
// literally the same sky.
var seed: UInt64 = 0x243F6A8885A308D3
func next() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double((seed >> 11) & 0x1F_FFFF) / Double(0x20_0000)
}
for _ in 0..<(width * height / 900) {
    let x = next() * CGFloat(w), y = next() * CGFloat(h)
    let r = (0.35 + next() * 0.55) * s
    let brightness = 0.14 + pow(next(), 1.7) * 0.46
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(brightness)))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// radial-gradient(circle closest-corner at 50% 0, rgba(255,255,255,.08), transparent)
// CoreGraphics' origin is bottom-left, so "the top edge" is y = h.
let radial = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.08),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(radial,
                       startCenter: CGPoint(x: w / 2, y: h), startRadius: 0,
                       endCenter: CGPoint(x: w / 2, y: h), endRadius: CGFloat(w) / 2,
                       options: [])

// The run between the two icons: a hairline that fades in from the app and
// fades out at the folder, so it reads as a direction rather than a rule.
let trackY = CGFloat(h) - 180 * s
let from = 245 * s, to = 400 * s
let run = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
] as CFArray, locations: [0, 0.5, 1])!
ctx.saveGState()
ctx.clip(to: CGRect(x: from, y: trackY - 0.5 * s, width: to - from, height: 1 * s))
ctx.drawLinearGradient(run, start: CGPoint(x: from, y: 0), end: CGPoint(x: to, y: 0), options: [])
ctx.restoreGState()

// A small open chevron at the folder end. Stroked, not filled, so it stays a
// mark of direction and not an arrowhead sitting in a box.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.34))
ctx.setLineWidth(1.4 * s)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let tip = to, arm = 5.5 * s
ctx.move(to: CGPoint(x: tip - arm, y: trackY + arm))
ctx.addLine(to: CGPoint(x: tip, y: trackY))
ctx.addLine(to: CGPoint(x: tip - arm, y: trackY - arm))
ctx.strokePath()

// Grain, screened over the top, tiled at the same 128pt cell as the app.
var grainSeed: UInt64 = 0x9E3779B97F4A7C15
let side = 128
var pixels = [UInt8](repeating: 0, count: side * side * 4)
for i in stride(from: 0, to: pixels.count, by: 4) {
    grainSeed = grainSeed &* 6364136223846793005 &+ 1442695040888963407
    let v = UInt8((grainSeed >> 33) & 0xFF)
    pixels[i] = v; pixels[i+1] = v; pixels[i+2] = v; pixels[i+3] = 255
}
let provider = CGDataProvider(data: Data(pixels) as CFData)!
let grain = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: side * 4, space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
ctx.saveGState()
ctx.setBlendMode(.screen)
ctx.setAlpha(0.05)
ctx.draw(grain, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
ctx.restoreGState()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
