import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("BrainBattle/Resources/Assets.xcassets")
let manager = FileManager.default
func json(_ value: [String: Any], at url: URL) throws {
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try json(["info": info], at: assets.appendingPathComponent("Contents.json"))
for (name, rgba) in [("AccentColor", ["red":"0.150", "green":"0.140", "blue":"0.180", "alpha":"1.000"]), ("LaunchBackground", ["red":"0.980", "green":"0.970", "blue":"0.950", "alpha":"1.000"])] {
    try json(["info": info, "colors": [["idiom":"universal", "color":["color-space":"srgb", "components":rgba]]]], at: assets.appendingPathComponent("\(name).colorset/Contents.json"))
}
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(red: 0.95, green: 0.53, blue: 0.30, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
if let brain = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 580, weight: .medium)
        .applying(.init(paletteColors: [NSColor(red: 0.15, green: 0.14, blue: 0.18, alpha: 1)]))
    brain.withSymbolConfiguration(config)?.draw(in: NSRect(x: 232, y: 207, width: 560, height: 610))
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
let icon = assets.appendingPathComponent("AppIcon.appiconset")
try manager.createDirectory(at: icon, withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: icon.appendingPathComponent("AppIcon.png"))
try json(["info":info, "images":[["filename":"AppIcon.png", "idiom":"universal", "platform":"ios", "size":"1024x1024"]]], at: icon.appendingPathComponent("Contents.json"))
