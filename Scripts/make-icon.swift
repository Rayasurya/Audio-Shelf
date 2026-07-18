// Draws the Audio Shelf app icon (flat book spine with a sound wave) and
// writes a 1024px master PNG. Run: swift Scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputPath = CommandLine.arguments[1]

// Audio Shelf identity: electric violet plate, frost book, aqua spine,
// deep-ink waveform. No orange, no beige, anywhere.
let ink = NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.12, alpha: 1)
let frost = NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.95, alpha: 1)
let violet = NSColor(calibratedRed: 0.36, green: 0.24, blue: 0.96, alpha: 1)
let aqua = NSColor(calibratedRed: 0.18, green: 0.75, blue: 0.71, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon plate: rounded rect with the standard ~10% margin — a full,
// confident field of violet.
let plateInset: CGFloat = 88
let plateRect = NSRect(x: plateInset, y: plateInset, width: size - plateInset * 2, height: size - plateInset * 2)
let plate = NSBezierPath(roundedRect: plateRect, xRadius: 200, yRadius: 200)
violet.setFill()
plate.fill()

// Book: a closed cover seen straight on, generous on the plate.
let bookRect = NSRect(x: 302, y: 242, width: 420, height: 540)
let book = NSBezierPath(roundedRect: bookRect, xRadius: 36, yRadius: 36)
frost.setFill()
book.fill()

// Spine strip: the book path clipped to its left edge, so the strip keeps
// the cover's rounded corners.
NSGraphicsContext.saveGraphicsState()
NSBezierPath(rect: NSRect(x: bookRect.minX, y: bookRect.minY, width: 80, height: bookRect.height)).addClip()
aqua.setFill()
book.fill()
NSGraphicsContext.restoreGraphicsState()

// Sound wave: five deep-ink bars centered on the cover — the book speaks.
let barWidth: CGFloat = 48
let barGap: CGFloat = 32
let barHeights: [CGFloat] = [130, 240, 350, 240, 130]
let waveWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barGap
let waveOriginX = bookRect.minX + 80 + ((bookRect.width - 80) - waveWidth) / 2
let centerY = bookRect.midY
ink.setFill()
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
