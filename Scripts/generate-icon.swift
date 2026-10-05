import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.082, green: 0.098, blue: 0.122, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let frames: [(NSRect, NSColor)] = [
 (NSRect(x: 160, y: 260, width: 190, height: 430), NSColor(red: 0.92, green: 0.65, blue: 0.35, alpha: 1)),
 (NSRect(x: 395, y: 260, width: 250, height: 250), NSColor(red: 0.63, green: 0.79, blue: 0.74, alpha: 1)),
 (NSRect(x: 690, y: 260, width: 174, height: 98), NSColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1))]
for (rect, color) in frames { color.setStroke(); let path = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28); path.lineWidth = 20; path.stroke() }
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
