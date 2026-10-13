import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Renders the PingViewScan app icon (a latency "pulse" on a dark grid) to PNG.
// Usage: make_icon <output.png> [size]

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 1024) : 1024
let side = CGFloat(size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Unable to create CGContext")
}

ctx.setAllowsAntialiasing(true)

let inset = side * 0.028
let radius = side * 0.218
let clip = CGPath(roundedRect: CGRect(x: inset, y: inset,
                                      width: side - inset * 2, height: side - inset * 2),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(clip)
ctx.clip()

let top = CGColor(red: 0.14, green: 0.23, blue: 0.47, alpha: 1)
let bottom = CGColor(red: 0.03, green: 0.06, blue: 0.15, alpha: 1)
let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: side),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
ctx.setLineWidth(side * 0.002)
for i in 1..<8 {
    let p = CGFloat(i) * side / 8
    ctx.move(to: CGPoint(x: p, y: 0)); ctx.addLine(to: CGPoint(x: p, y: side))
    ctx.move(to: CGPoint(x: 0, y: p)); ctx.addLine(to: CGPoint(x: side, y: p))
}
ctx.strokePath()

let points: [(CGFloat, CGFloat)] = [
    (0.10, 0.52), (0.28, 0.52), (0.36, 0.43), (0.45, 0.69),
    (0.55, 0.30), (0.64, 0.72), (0.72, 0.52), (0.90, 0.52)
]
func pixel(_ point: (CGFloat, CGFloat)) -> CGPoint {
    CGPoint(x: point.0 * side, y: point.1 * side)
}

let green = CGColor(red: 0.16, green: 0.80, blue: 0.42, alpha: 1)
ctx.setStrokeColor(green)
ctx.setLineWidth(side * 0.030)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: pixel(points[0]))
for point in points.dropFirst() { ctx.addLine(to: pixel(point)) }
ctx.strokePath()

let end = pixel(points[points.count - 1])
ctx.setFillColor(green)
ctx.fillEllipse(in: CGRect(x: end.x - side * 0.033, y: end.y - side * 0.033,
                           width: side * 0.066, height: side * 0.066))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: end.x - side * 0.014, y: end.y - side * 0.014,
                           width: side * 0.028, height: side * 0.028))

ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("Unable to render image") }
let url = URL(fileURLWithPath: outPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to create image destination")
}
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(outPath) (\(size)x\(size))")
