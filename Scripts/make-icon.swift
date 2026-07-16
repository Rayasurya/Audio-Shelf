// Draws the Audio Shelf app icon (flat book spine with a sound wave) and
// writes a 1024px master PNG. Run: swift Scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputPath = CommandLine.arguments[1]

let ink = NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.17, alpha: 1)
let paper = NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.88, alpha: 1)
let copper = NSColor(calibratedRed: 0.91, green: 0.31, blue: 0.17, alpha: 1)
let sea = NSColor(calibratedRed: 0.10, green: 0.26, blue: 0.27, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon plate: rounded rect with the standard ~10% margin.
let plateInset: CGFloat = 88
let plateRect = NSRect(x: plateInset, y: plateInset, width: size - plateInset * 2, height: size - plateInset * 2)
let plate = NSBezierPath(roundedRect: plateRect, xRadius: 200, yRadius: 200)
ink.setFill()
plate.fill()

// Book: a closed cover seen straight on, slightly left of center,
// with a narrow spine strip.
let bookRect = NSRect(x: 320, y: 262, width: 384, height: 500)
let book = NSBezierPath(roundedRect: bookRect, xRadius: 34, yRadius: 34)
paper.setFill()
book.fill()

// Spine strip: the book path clipped to its left edge, so the strip keeps
// the cover's rounded corners.
NSGraphicsContext.saveGraphicsState()
NSBezierPath(rect: NSRect(x: bookRect.minX, y: bookRect.minY, width: 74, height: bookRect.height)).addClip()
sea.setFill()
book.fill()
NSGraphicsContext.restoreGraphicsState()

// Sound wave: five flat bars centered on the cover.
let barWidth: CGFloat = 44
let barGap: CGFloat = 34
let barHeights: [CGFloat] = [120, 220, 320, 220, 120]
let waveWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barGap
let waveOriginX = bookRect.minX + 74 + ((bookRect.width - 74) - waveWidth) / 2
let centerY = bookRect.midY
copper.setFill()
for (index, height) in barHeights.enumerated() {
    let x = waveOriginX + CGFloat(index) * (barWidth + barGap)
    let bar = NSBezierPath(
        roundedRect: NSRect(x: x, y: centerY - height / 2, width: barWidth, height: height),
        xRadius: barWidth / 2,
        yRadius: barWidth / 2
    )
    bar.fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
