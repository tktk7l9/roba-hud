// Generates AppIcon.iconset PNGs (run: swift scripts/generate-icon.swift <outdir>)
// Design: the real 43-key roBa layout + trackball on a dark squircle.
import AppKit

struct K { let x, y, r, rx, ry: Double }
// Key positions from zmk-config-roBa/config/roBa.json (key units).
let keys: [K] = [
    K(x: 0, y: 0.616, r: 0, rx: 0, ry: 0), K(x: 1.003, y: 0.247, r: 0, rx: 0, ry: 0),
    K(x: 2.005, y: 0, r: 0, rx: 0, ry: 0), K(x: 3.008, y: 0.132, r: 0, rx: 0, ry: 0),
    K(x: 4.011, y: 0.263, r: 0, rx: 0, ry: 0), K(x: 8.504, y: 0.264, r: 0, rx: 0, ry: 0),
    K(x: 9.506, y: 0.133, r: 0, rx: 0, ry: 0), K(x: 10.509, y: 0.001, r: 0, rx: 0, ry: 0),
    K(x: 11.512, y: 0.248, r: 0, rx: 0, ry: 0), K(x: 12.514, y: 0.617, r: 0, rx: 0, ry: 0),
    K(x: 0, y: 1.618, r: 0, rx: 0, ry: 0), K(x: 1.003, y: 1.25, r: 0, rx: 0, ry: 0),
    K(x: 2.005, y: 1.003, r: 0, rx: 0, ry: 0), K(x: 3.008, y: 1.134, r: 0, rx: 0, ry: 0),
    K(x: 4.011, y: 1.266, r: 0, rx: 0, ry: 0), K(x: 5.015, y: 1.504, r: 0, rx: 0, ry: 0),
    K(x: 7.501, y: 1.505, r: 0, rx: 0, ry: 0), K(x: 8.504, y: 1.267, r: 0, rx: 0, ry: 0),
    K(x: 9.506, y: 1.135, r: 0, rx: 0, ry: 0), K(x: 10.509, y: 1.004, r: 0, rx: 0, ry: 0),
    K(x: 11.512, y: 1.251, r: 0, rx: 0, ry: 0), K(x: 12.514, y: 1.619, r: 0, rx: 0, ry: 0),
    K(x: 0, y: 2.621, r: 0, rx: 0, ry: 0), K(x: 1.003, y: 2.253, r: 0, rx: 0, ry: 0),
    K(x: 2.005, y: 2.005, r: 0, rx: 0, ry: 0), K(x: 3.008, y: 2.137, r: 0, rx: 0, ry: 0),
    K(x: 4.011, y: 2.268, r: 0, rx: 0, ry: 0), K(x: 5.013, y: 2.507, r: 0, rx: 0, ry: 0),
    K(x: 7.501, y: 2.508, r: 0, rx: 0, ry: 0), K(x: 8.504, y: 2.269, r: 0, rx: 0, ry: 0),
    K(x: 9.506, y: 2.138, r: 0, rx: 0, ry: 0), K(x: 10.509, y: 2.006, r: 0, rx: 0, ry: 0),
    K(x: 11.512, y: 2.254, r: 0, rx: 0, ry: 0), K(x: 12.514, y: 2.622, r: 0, rx: 0, ry: 0),
    K(x: 0, y: 3.624, r: 0, rx: 0, ry: 0), K(x: 1.003, y: 3.255, r: 0, rx: 0, ry: 0),
    K(x: 2.004, y: 3.007, r: 0, rx: 0, ry: 0), K(x: 3.219, y: 3.525, r: 0, rx: 0, ry: 0),
    K(x: 4.342, y: 3.617, r: 9, rx: 4.842, ry: 4.117), K(x: 5.451, y: 3.909, r: 20, rx: 5.951, ry: 4.409),
    K(x: 7.059, y: 3.91, r: -20, rx: 7.559, ry: 4.41), K(x: 8.158, y: 3.616, r: -10, rx: 8.658, ry: 4.116),
    K(x: 12.514, y: 3.625, r: 0, rx: 0, ry: 0),
]
// A few "live highlight" keys (cyan): home-ish keys + one thumb.
let accentKeys: Set<Int> = [13, 18, 39]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let S = CGFloat(pixels)

    // Flip to top-left origin so the layout math reads like screen coords.
    cg.translateBy(x: 0, y: S)
    cg.scaleBy(x: 1, y: -1)

    // Apple-style squircle plate: 824/1024 of canvas, r ≈ 185/1024.
    let plateSize = S * 824 / 1024
    let plateOrigin = (S - plateSize) / 2
    let plate = CGRect(x: plateOrigin, y: plateOrigin, width: plateSize, height: plateSize)
    let platePath = CGPath(roundedRect: plate, cornerWidth: S * 185 / 1024,
                           cornerHeight: S * 185 / 1024, transform: nil)
    cg.addPath(platePath)
    cg.clip()

    // Background gradient (dark slate, subtly lighter at top).
    let colors = [NSColor(calibratedRed: 0.165, green: 0.196, blue: 0.290, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.055, green: 0.070, blue: 0.130, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plateOrigin),
                          end: CGPoint(x: 0, y: plateOrigin + plateSize), options: [])

    // Fit the layout (13.5u × ~5.0u incl. trackball) into the plate.
    let layoutW = 13.514, layoutH = 5.05
    let unit = plateSize * 0.86 / layoutW
    let originX = plateOrigin + (plateSize - unit * layoutW) / 2
    let originY = plateOrigin + (plateSize - unit * layoutH) / 2 + unit * 0.1

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: originX + CGFloat(x) * unit, y: originY + CGFloat(y) * unit)
    }

    // Keycaps.
    for (index, key) in keys.enumerated() {
        cg.saveGState()
        if key.r != 0 {
            let pivot = point(key.rx, key.ry)
            cg.translateBy(x: pivot.x, y: pivot.y)
            cg.rotate(by: CGFloat(key.r) * .pi / 180)
            cg.translateBy(x: -pivot.x, y: -pivot.y)
        }
        let top = point(key.x + 0.05, key.y + 0.05)
        let rect = CGRect(x: top.x, y: top.y, width: unit * 0.9, height: unit * 0.9)
        let path = CGPath(roundedRect: rect, cornerWidth: unit * 0.16,
                          cornerHeight: unit * 0.16, transform: nil)
        if accentKeys.contains(index) {
            cg.setFillColor(NSColor(calibratedRed: 0.31, green: 0.76, blue: 0.97, alpha: 1).cgColor)
        } else {
            cg.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 0.92).cgColor)
        }
        cg.addPath(path)
        cg.fillPath()
        cg.restoreGState()
    }

    // Trackball (orange) nested in the right thumb cluster.
    let ball = point(8.35, 4.30)
    let radius = unit * 0.62
    cg.setFillColor(NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.26, alpha: 1).cgColor)
    cg.fillEllipse(in: CGRect(x: ball.x - radius, y: ball.y - radius,
                              width: radius * 2, height: radius * 2))
    // Specular dot for a bit of depth.
    cg.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.35).cgColor)
    cg.fillEllipse(in: CGRect(x: ball.x - radius * 0.45, y: ball.y - radius * 0.55,
                              width: radius * 0.5, height: radius * 0.5))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32),
                   ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let rep = drawIcon(pixels: px)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(outDir)/\(name).png")
}
