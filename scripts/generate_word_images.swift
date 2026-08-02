import AppKit

/// Generate 100×100 white SF Symbol PNGs with transparent backgrounds into
/// Resources/Sprites/Words/.
/// Usage: swift scripts/generate_word_images.swift [word:symbol ...]
/// With no args, regenerates the catalog set below.

let defaultSymbols: [(word: String, symbol: String)] = [
    ("apple", "apple.logo"),
    ("bath", "bathtub.fill"),
    ("boat", "sailboat.fill"),  // boat.fill unavailable on current SF Symbols
    ("book", "book.closed.fill"),
    ("car", "car.fill"),
    ("cat", "cat.fill"),
    ("cloud", "cloud.fill"),
    ("dance", "figure.socialdance"),
    ("dog", "dog.fill"),
    ("house", "house.fill"),
    ("lightbulb", "lightbulb.fill"),
    ("pencil", "pencil"),
    ("star", "star.fill"),
    ("sun", "sun.max.fill"),
    ("trash", "trash.fill"),
    ("wand", "wand.and.sparkles"),
]

let symbols: [(word: String, symbol: String)]
if CommandLine.arguments.count > 1 {
    symbols = CommandLine.arguments.dropFirst().compactMap { arg in
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0].lowercased(), parts[1])
    }
} else {
    symbols = defaultSymbols
}

let side: CGFloat = 100
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outDir = repoRoot.appendingPathComponent(
    "Padawan Adventures/Resources/Sprites/Words"
)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (word, symbolName) in symbols {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        FileHandle.standardError.write(Data("missing symbol \(symbolName)\n".utf8))
        exit(1)
    }
    let configured = base.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 512, weight: .regular)
    ) ?? base
    configured.isTemplate = true

    let source = configured.size
    let scale = min(side / source.width, side / source.height) * 0.72
    let draw = CGSize(width: source.width * scale, height: source.height * scale)
    let dest = NSRect(
        x: (side - draw.width) / 2,
        y: (side - draw.height) / 2,
        width: draw.width,
        height: draw.height
    )

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = NSSize(width: side, height: side)

    let canvas = NSRect(x: 0, y: 0, width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)
    configured.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1)
    // Force pure white glyph; leave clear pixels untouched.
    NSColor.white.setFill()
    canvas.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try data.write(to: outDir.appendingPathComponent("\(word).png"))
    print("wrote \(word).png (\(symbolName))")
}
