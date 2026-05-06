import AppKit

let size: CGFloat = 1024
let symbolPointSize: CGFloat = 600

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// Background
ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1.0))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Render the same SF Symbol used in the menu bar
let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let symSize = symbol.size
    let x = (size - symSize.width) / 2
    let y = (size - symSize.height) / 2
    symbol.draw(in: CGRect(x: x, y: y, width: symSize.width, height: symSize.height))
}

image.unlockFocus()

let outputPath = "/Users/elicarter/Workspace/TypeLessBuddy/AppIcon-1024.png"
if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: outputPath))
    print("Saved to \(outputPath)")
} else {
    print("Failed to generate image")
}
