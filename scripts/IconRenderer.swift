// Renders the Candela app icon (original artwork, no third-party assets) to a 1024 x 1024 PNG.
// Usage: swift scripts/IconRenderer.swift <output.png>
// Layout follows the macOS icon grid: an 824 pt rounded body centered on a 1024 pt canvas.
//
// The mark is deliberately abstract: a warm orb built from stepped discs, glowing on deep moss.
// Each disc is one level of light, brightest where the light comes from (upper left), so the
// icon hints at what the app does (stepping a display's brightness) without drawing a monitor.

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("no context") }
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// Palette.
let mossTop: UInt32 = 0x2F3D31
let mossBottom: UInt32 = 0x1B251F
let glow: UInt32 = 0xF2B24C
// Outermost (dimmest) to innermost (brightest).
let levels: [UInt32] = [0xC9532F, 0xE6823A, 0xF3B653, 0xFCE9B6]

// Body with soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 36, color: color(0x000000, 0.30))
ctx.addPath(bodyPath)
ctx.setFillColor(color(mossBottom))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
linear([color(mossTop), color(mossBottom)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
// Warm light spilling onto the background.
radial([color(glow, 0.20), color(glow, 0)], center: CGPoint(x: 512, y: 512), radius: 420)
ctx.restoreGState()

// Faint rim along the top edge so the body separates from a dark Dock or desktop.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.addPath(bodyPath)
ctx.setLineWidth(6)
ctx.replacePathWithStrokedPath()
ctx.clip()
linear([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 420))
ctx.restoreGState()

// The orb: stepped discs, each smaller one shifted toward the light.
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 272
let lightAngle = -CGFloat.pi * 0.62 // upper left
let toLight = CGPoint(x: cos(lightAngle), y: sin(lightAngle))
for (i, fill) in levels.enumerated() {
    let r = radius * (1 - 0.235 * CGFloat(i))
    let shift = (radius - r) * 0.80
    let c = CGPoint(x: center.x + toLight.x * shift, y: center.y + toLight.y * shift)
    ctx.setFillColor(color(fill))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// Fine grain for a matte, printed feel. Seeded, so every render is identical.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
func random() -> CGFloat {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return CGFloat(seed >> 33) / CGFloat(1 << 31)
}
for _ in 0 ..< 60000 {
    let x = body.minX + random() * body.width
    let y = body.minY + random() * body.height
    ctx.setFillColor(random() > 0.5 ? color(0xFFFFFF, 0.035) : color(0x000000, 0.05))
    ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
}
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("render failed") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
