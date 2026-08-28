// Generates Resources/Nimbus.icns. Run from the repo root:
//   swift tools/makeicon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS-style rounded-rect canvas with a small transparent margin, like system icons.
let inset: CGFloat = size * 0.098
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.185, yRadius: size * 0.185)
path.addClip()

let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.11, alpha: 1),
    ]
)!
gradient.draw(in: rect, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.withAlphaComponent(0.96).set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let symbolRect = NSRect(
        x: (size - tinted.size.width) / 2,
        y: (size - tinted.size.height) / 2,
        width: tinted.size.width,
        height: tinted.size.height
    )
    tinted.draw(in: symbolRect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    fatalError("could not rasterize icon")
}

let iconsetURL = URL(fileURLWithPath: "Resources/Nimbus.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let scaled = NSImage(size: NSSize(width: pixels, height: pixels))
    scaled.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(x: 0, y: 0, width: size, height: size),
        operation: .copy,
        fraction: 1
    )
    scaled.unlockFocus()
    guard let t = scaled.tiffRepresentation,
          let r = NSBitmapImageRep(data: t),
          let png = r.representation(using: .png, properties: [:]) else { continue }

    let names: [String]
    switch pixels {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    case 1024: names = ["icon_512x512@2x.png"]
    default: names = []
    }
    for name in names {
        try! png.write(to: iconsetURL.appendingPathComponent(name))
    }
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", "Resources/Nimbus.iconset", "-o", "Resources/Nimbus.icns"]
task.launch()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetURL)
print(task.terminationStatus == 0 ? "wrote Resources/Nimbus.icns" : "iconutil failed")
