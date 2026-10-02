// Uygulama ikonunu üretir: `swift tools/make-icon.swift <çıktı.png>`.
// İkon tamamen geometrik çizimdir; hiçbir hazır sembol, yazı tipi ya da görsel kullanılmaz.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Arka plan: yuvarlatılmış kare, pembe → turuncu degrade.
let inset = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let background = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
NSGradient(colors: [NSColor(red: 0.98, green: 0.32, blue: 0.55, alpha: 1), NSColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1)])!
    .draw(in: background, angle: -45)

// Köpük baloncukları: dolgu + iç parlama.
func bubble(x: Double, y: Double, r: Double) {
    let circle = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    NSColor.white.withAlphaComponent(0.92).setFill()
    circle.fill()
    let shine = NSBezierPath()
    shine.appendArc(withCenter: NSPoint(x: x, y: y), radius: r * 0.62, startAngle: 100, endAngle: 165)
    shine.lineWidth = r * 0.16
    shine.lineCapStyle = .round
    NSColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 0.9).setStroke()
    shine.stroke()
}

bubble(x: size * 0.44, y: size * 0.42, r: size * 0.2)
bubble(x: size * 0.68, y: size * 0.62, r: size * 0.12)
bubble(x: size * 0.42, y: size * 0.73, r: size * 0.07)

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
