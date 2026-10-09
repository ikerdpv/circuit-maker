// Genera Resources/AppIcon.icns. Uso: ./tools/make_icon.sh
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Fondo redondeado
let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.32, alpha: 1),
                    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1)])!.draw(in: bg, angle: -90)

bg.addClip()

// Rejilla de puntos
NSColor(white: 1, alpha: 0.12).setFill()
for x in stride(from: 180.0, through: 850, by: 56) {
    for y in stride(from: 180.0, through: 850, by: 56) {
        NSBezierPath(ovalIn: NSRect(x: x - 4, y: y - 4, width: 8, height: 8)).fill()
    }
}

// Circuito: rectángulo con pila a la izquierda y bombilla a la derecha
ctx.setLineCap(.round)
ctx.setLineWidth(26)
let wire = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 1)
ctx.setStrokeColor(wire.cgColor)
ctx.stroke(CGRect(x: 250, y: 290, width: 524, height: 444))

// Pila (corta el cable izquierdo)
ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.25, alpha: 1).cgColor)
ctx.fill(CGRect(x: 200, y: 470, width: 100, height: 84))
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(22); ctx.strokeLineSegments(between: [CGPoint(x: 180, y: 540), CGPoint(x: 320, y: 540)])
ctx.setLineWidth(40); ctx.strokeLineSegments(between: [CGPoint(x: 215, y: 484), CGPoint(x: 285, y: 484)])

// Bombilla encendida
let c = CGPoint(x: 774, y: 512)
let glow = CGGradient(colorsSpace: nil, colors: [NSColor(calibratedRed: 1, green: 0.9, blue: 0.3, alpha: 0.95).cgColor,
                                                  NSColor(calibratedRed: 1, green: 0.8, blue: 0.1, alpha: 0).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: c, startRadius: 40, endCenter: c, endRadius: 230, options: [])
ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.88, blue: 0.3, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: c.x - 82, y: c.y - 82, width: 164, height: 164))
ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.15, blue: 0.05, alpha: 1).cgColor)
ctx.setLineWidth(20)
ctx.strokeEllipse(in: CGRect(x: c.x - 82, y: c.y - 82, width: 164, height: 164))
let d: CGFloat = 58
ctx.strokeLineSegments(between: [CGPoint(x: c.x - d, y: c.y - d), CGPoint(x: c.x + d, y: c.y + d),
                                 CGPoint(x: c.x - d, y: c.y + d), CGPoint(x: c.x + d, y: c.y - d)])

// Puntos de corriente
ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.62, blue: 0.05, alpha: 1).cgColor)
for x in stride(from: 350.0, through: 690, by: 85) {
    ctx.fillEllipse(in: CGRect(x: x - 16, y: 734 - 16, width: 32, height: 32))
    ctx.fillEllipse(in: CGRect(x: x - 16, y: 290 - 16, width: 32, height: 32))
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
