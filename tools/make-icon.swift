// Renders the DeskDash app icon master (1024×1024 PNG).
// Usage: swift tools/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }

// macOS icon grid: 824×824 body centred on a 1024 canvas, continuous-corner radius ≈ 185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1B2A4A))
ctx.fillPath()
ctx.restoreGState()

// Background: deep indigo → teal, like dusk over a desktop wallpaper.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [color(0x2C3E91), color(0x2A7FB8), color(0x3CC2B0)] as CFArray,
                            locations: [0, 0.55, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
// Soft light bloom, top-left.
let bloom = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 300, y: 820), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 820), endRadius: 520, options: [])
ctx.restoreGState()

// The "desk" card: a frosted glass pane split into two panels.
let card = CGRect(x: 196, y: 258, width: 632, height: 508)
let cardPath = CGPath(roundedRect: card, cornerWidth: 64, cornerHeight: 64, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x0B1530, 0.35))
ctx.addPath(cardPath)
ctx.setFillColor(color(0xFFFFFF, 0.22))
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(cardPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.55))
ctx.setLineWidth(4)
ctx.strokePath()

// Divider between the two panels (≈ 40 / 60 split, like the app).
let splitX = card.minX + card.width * 0.42
ctx.setStrokeColor(color(0xFFFFFF, 0.45))
ctx.setLineWidth(4)
ctx.move(to: CGPoint(x: splitX, y: card.minY + 44))
ctx.addLine(to: CGPoint(x: splitX, y: card.maxY - 44))
ctx.strokePath()

// Left panel: three reminder rows, the first one done.
let rowX = card.minX + 52
let lineEnd = splitX - 40
for (index, y) in [card.maxY - 130, card.midY, card.minY + 130].enumerated() {
    let radius: CGFloat = 26
    let circle = CGRect(x: rowX, y: y - radius, width: radius * 2, height: radius * 2)
    if index == 0 {
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: circle)
        // Checkmark.
        ctx.setStrokeColor(color(0x2A7FB8))
        ctx.setLineWidth(9)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: circle.minX + 14, y: circle.midY + 1))
        ctx.addLine(to: CGPoint(x: circle.minX + 23, y: circle.midY - 10))
        ctx.addLine(to: CGPoint(x: circle.maxX - 12, y: circle.midY + 12))
        ctx.strokePath()
    } else {
        ctx.setStrokeColor(color(0xFFFFFF, 0.95))
        ctx.setLineWidth(7)
        ctx.strokeEllipse(in: circle.insetBy(dx: 3.5, dy: 3.5))
    }
    // Title bar for the row.
    let barStart = circle.maxX + 24
    let barWidth = (lineEnd - barStart) * (index == 1 ? 0.8 : 1)
    let bar = CGRect(x: barStart, y: y - 9, width: barWidth, height: 18)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.setFillColor(color(0xFFFFFF, index == 0 ? 0.55 : 0.92))
    ctx.fillPath()
}

// Right panel: a mini month grid with today highlighted.
let gridLeft = splitX + 50
let gridRight = card.maxX - 50
let headerY = card.maxY - 92
ctx.addPath(CGPath(roundedRect: CGRect(x: gridLeft, y: headerY - 12, width: (gridRight - gridLeft) * 0.55, height: 24),
                   cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.setFillColor(color(0xFFFFFF, 0.95))
ctx.fillPath()

let columns = 5
let rows = 4
let cellW = (gridRight - gridLeft) / CGFloat(columns)
let gridTop = headerY - 62
let cellH: CGFloat = 82
for row in 0..<rows {
    for column in 0..<columns {
        let center = CGPoint(x: gridLeft + cellW * (CGFloat(column) + 0.5), y: gridTop - cellH * CGFloat(row) - cellH / 2 + 20)
        let isToday = row == 1 && column == 2
        if isToday {
            let r: CGFloat = 30
            ctx.setFillColor(color(0xFF6B5B))
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        } else {
            let r: CGFloat = 11
            ctx.setFillColor(color(0xFFFFFF, (row + column) % 3 == 0 ? 0.95 : 0.6))
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
    }
}

// Subtle top highlight on the tile edge.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.18))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
