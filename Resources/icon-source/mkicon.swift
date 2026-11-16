import AppKit
let out = CommandLine.arguments[1]
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Apple's icon grid: an 824/1024 rounded tile centred in the canvas, corner radius about 22.5% of the tile.
    let f = CGFloat(px) / 1024
    let tile = NSRect(x: 100 * f, y: 100 * f, width: 824 * f, height: 824 * f)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 186 * f, yRadius: 186 * f)
    let pink = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "pink"
    let blue = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "blue"
    let top = blue ? NSColor(srgbRed: 0.20, green: 0.76, blue: 1.00, alpha: 1) : pink ? NSColor(srgbRed: 1.00, green: 0.78, blue: 0.86, alpha: 1) : NSColor(srgbRed: 1.00, green: 0.86, blue: 0.30, alpha: 1)
    let bottom = blue ? NSColor(srgbRed: 0.08, green: 0.44, blue: 0.96, alpha: 1) : pink ? NSColor(srgbRed: 1.00, green: 0.55, blue: 0.72, alpha: 1) : NSColor(srgbRed: 1.00, green: 0.76, blue: 0.10, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)
    let size = CGFloat(px) * 0.70
    let font = NSFont(name: "Apple Color Emoji", size: size) ?? NSFont.systemFont(ofSize: size)
    let s = NSAttributedString(string: "🍰", attributes: [.font: font])
    let b = s.size()
    s.draw(at: NSPoint(x: (CGFloat(px) - b.width) / 2, y: (CGFloat(px) - b.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let sizes: [(String, Int)] = [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in sizes { try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png")) }
print("rendered \(sizes.count)")
