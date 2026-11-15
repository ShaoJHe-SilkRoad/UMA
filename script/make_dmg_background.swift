// Draws the AUV installer window background: UMA.app sits on the left, the
// Applications link on the right, an arrow between them and a two-line hint.
// Usage: swift script/make_dmg_background.swift <output folder>
// Writes background.png (660x400) and background@2x.png; the release script
// combines them into one HiDPI TIFF.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let size = CGSize(width: 660, height: 400)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Finder draws icon labels in black on a background picture, so stay light.
    NSGradient(starting: NSColor(calibratedWhite: 0.985, alpha: 1),
               ending: NSColor(calibratedWhite: 0.93, alpha: 1))!
        .draw(in: CGRect(origin: .zero, size: size), angle: -90)

    // Arrow from the app (centre x 165) to Applications (centre x 495), at the
    // icons' height. AppKit's origin is bottom-left; icons sit at y 185 from the top.
    let y = size.height - 185
    let accent = NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1)
    accent.setStroke(); accent.setFill()
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: 262, y: y)); shaft.line(to: CGPoint(x: 382, y: y))
    shaft.lineWidth = 7; shaft.lineCapStyle = .round
    let dash: [CGFloat] = [1, 15]
    shaft.setLineDash(dash, count: 2, phase: 0)
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 400, y: y))
    head.line(to: CGPoint(x: 380, y: y + 14))
    head.line(to: CGPoint(x: 380, y: y - 14))
    head.close(); head.fill()

    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    func line(_ text: String, _ font: NSFont, _ color: NSColor, top: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let h = font.boundingRectForFont.height
        (text as NSString).draw(in: CGRect(x: 0, y: size.height - top - h, width: size.width, height: h),
                                withAttributes: attrs)
    }
    line("将左边的应用拖到 Applications 完成安装", .systemFont(ofSize: 17, weight: .semibold),
         NSColor(calibratedWhite: 0.15, alpha: 1), top: 300)
    line("Drag the app on the left onto Applications to install", .systemFont(ofSize: 13, weight: .regular),
         NSColor(calibratedWhite: 0.42, alpha: 1), top: 328)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
