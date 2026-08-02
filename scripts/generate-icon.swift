import AppKit
import Foundation

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create drawing context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

let context = graphicsContext.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.29, blue: 0.86, alpha: 1)
])!

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
background.draw(in: tile, angle: -48)
NSGraphicsContext.restoreGraphicsState()

let glow = NSBezierPath(ovalIn: NSRect(x: 174, y: 300, width: 676, height: 676))
NSColor.white.withAlphaComponent(0.055).setFill()
glow.fill()

let loop = NSBezierPath()
loop.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 258, startAngle: 41, endAngle: 351, clockwise: false)
loop.lineWidth = 82
loop.lineCapStyle = .round
NSColor.white.setStroke()

NSGraphicsContext.saveGraphicsState()
let loopShadow = NSShadow()
loopShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
loopShadow.shadowBlurRadius = 18
loopShadow.shadowOffset = NSSize(width: 0, height: -8)
loopShadow.set()
loop.stroke()
NSGraphicsContext.restoreGraphicsState()

let arrowTip = NSBezierPath()
arrowTip.move(to: NSPoint(x: 747, y: 632))
arrowTip.line(to: NSPoint(x: 838, y: 625))
arrowTip.line(to: NSPoint(x: 792, y: 544))
arrowTip.close()
NSColor.white.setFill()
arrowTip.fill()

let humanHalo = NSBezierPath(ovalIn: NSRect(x: 390, y: 390, width: 244, height: 244))
NSColor.white.withAlphaComponent(0.16).setFill()
humanHalo.fill()

let human = NSBezierPath(ovalIn: NSRect(x: 446, y: 446, width: 132, height: 132))
let humanGradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.47, blue: 0.35, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.26, blue: 0.28, alpha: 1)
])!
humanGradient.draw(in: human, angle: -90)

let highlight = NSBezierPath(ovalIn: NSRect(x: 474, y: 525, width: 58, height: 22))
NSColor.white.withAlphaComponent(0.30).setFill()
highlight.fill()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}

let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon-1024.png")
try png.write(to: destination)
