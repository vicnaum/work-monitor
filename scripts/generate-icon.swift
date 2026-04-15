import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius = CGFloat(size) * 0.22

// Background gradient (warm red/orange to match the app's red clock theme)
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 20, dy: 20),
                        xRadius: cornerRadius, yRadius: cornerRadius)

let gradient = NSGradient(colors: [
    NSColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1.0),  // coral red
    NSColor(red: 0.85, green: 0.15, blue: 0.3, alpha: 1.0),  // deep rose
])!
gradient.draw(in: path, angle: -45)

// Draw a subtle inner shadow/border
let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 21, dy: 21),
                               xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
NSColor.white.withAlphaComponent(0.15).setStroke()
borderPath.lineWidth = 2
borderPath.stroke()

// Draw clock face (white circle)
let center = NSPoint(x: size / 2, y: size / 2)
let clockRadius = CGFloat(size) * 0.28
let clockRect = NSRect(
    x: center.x - clockRadius, y: center.y - clockRadius,
    width: clockRadius * 2, height: clockRadius * 2
)
let clockPath = NSBezierPath(ovalIn: clockRect)
NSColor.white.setFill()
clockPath.fill()

// Clock hands
let handColor = NSColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1.0)
handColor.setStroke()

// Hour hand (pointing to ~10 o'clock)
let hourPath = NSBezierPath()
hourPath.move(to: center)
let hourAngle = CGFloat.pi * 2 * (10.0 / 12.0) - CGFloat.pi / 2
let hourLen = clockRadius * 0.55
hourPath.line(to: NSPoint(
    x: center.x + cos(hourAngle) * hourLen,
    y: center.y - sin(hourAngle) * hourLen
))
hourPath.lineWidth = CGFloat(size) * 0.035
hourPath.lineCapStyle = .round
hourPath.stroke()

// Minute hand (pointing to ~2)
let minutePath = NSBezierPath()
minutePath.move(to: center)
let minuteAngle = CGFloat.pi * 2 * (10.0 / 60.0) - CGFloat.pi / 2
let minuteLen = clockRadius * 0.75
minutePath.line(to: NSPoint(
    x: center.x + cos(minuteAngle) * minuteLen,
    y: center.y - sin(minuteAngle) * minuteLen
))
minutePath.lineWidth = CGFloat(size) * 0.025
minutePath.lineCapStyle = .round
minutePath.stroke()

// Center dot
let dotSize = CGFloat(size) * 0.04
let dotRect = NSRect(x: center.x - dotSize/2, y: center.y - dotSize/2,
                     width: dotSize, height: dotSize)
handColor.setFill()
NSBezierPath(ovalIn: dotRect).fill()

// Small checkmark badge (bottom-right)
let badgeRadius = CGFloat(size) * 0.14
let badgeCenter = NSPoint(x: center.x + clockRadius * 0.7,
                          y: center.y - clockRadius * 0.7)
let badgeRect = NSRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                       width: badgeRadius * 2, height: badgeRadius * 2)
NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0).setFill()
NSBezierPath(ovalIn: badgeRect).fill()

// Checkmark in badge
let check = NSBezierPath()
let cs = badgeRadius * 0.45
check.move(to: NSPoint(x: badgeCenter.x - cs * 0.6, y: badgeCenter.y))
check.line(to: NSPoint(x: badgeCenter.x - cs * 0.1, y: badgeCenter.y - cs * 0.5))
check.line(to: NSPoint(x: badgeCenter.x + cs * 0.7, y: badgeCenter.y + cs * 0.5))
NSColor.white.setStroke()
check.lineWidth = CGFloat(size) * 0.03
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.stroke()

image.unlockFocus()

// Save as PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Generated \(outputPath)")
