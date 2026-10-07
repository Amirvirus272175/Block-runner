import Foundation
import CoreGraphics
import ImageIO

// Draws the Block Runner app icon (1024x1024, no transparency) and saves it as a PNG.
// Usage: swift tools/make_icon.swift output.png

let size = 1024
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create drawing context")
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fill(CGRect(x: x, y: y, width: w, height: h))
}
func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
}

// Sky and clouds
box(0, 0, 1024, 1024, rgb(0.36, 0.62, 0.98))
let cloud = rgb(1, 1, 1, 0.9)
oval(80, 790, 300, 110, cloud)
oval(160, 850, 200, 100, cloud)
oval(580, 870, 300, 100, cloud)

// Ground
box(0, 0, 1024, 250, rgb(0.55, 0.35, 0.18))
box(0, 210, 1024, 60, rgb(0.25, 0.70, 0.25))

// Coin
oval(710, 600, 180, 180, rgb(0.90, 0.60, 0.0))
oval(730, 620, 140, 140, rgb(1.0, 0.85, 0.10))

// Player: red block with cap and eye
box(300, 270, 330, 420, rgb(0.85, 0.10, 0.10))
box(280, 640, 370, 90, rgb(0.60, 0.05, 0.05))
box(480, 500, 100, 130, rgb(1, 1, 1))
box(535, 520, 40, 80, rgb(0, 0, 0))

// Enemy: grumpy brown block
box(700, 270, 230, 200, rgb(0.55, 0.30, 0.15))
box(735, 380, 65, 70, rgb(1, 1, 1))
box(830, 380, 65, 70, rgb(1, 1, 1))
box(750, 390, 28, 45, rgb(0, 0, 0))
box(845, 390, 28, 45, rgb(0, 0, 0))

guard let image = ctx.makeImage() else { fatalError("Could not make image") }
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) { fatalError("Could not write PNG") }
