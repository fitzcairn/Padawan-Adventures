import AppKit

/// Generate 100×100 white PNGs with transparent backgrounds into
/// Resources/Sprites/Words/.
/// Usage: swift scripts/generate_word_images.swift [word ...]
/// With no args, regenerates every word id in Catalogs/words.yaml.
/// Prefer SF Symbols when mapped; otherwise render the word as text art.

let defaultSymbols: [String: String] = [
    "boat": "sailboat.fill",
    "cat": "cat.fill",
    "dog": "dog.fill",
    "sun": "sun.max.fill",
    "flag": "flag.fill",
    "map": "map.fill",
    "night": "moon.stars.fill",
    "rain": "cloud.rain.fill",
    "snow": "snowflake",
    "tree": "tree.fill",
    "web": "globe",
    "star": "star.fill",
]

let side: CGFloat = 100
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outDir = repoRoot.appendingPathComponent(
    "Padawan Adventures/Resources/Sprites/Words"
)
let wordsYAML = repoRoot.appendingPathComponent(
    "Padawan Adventures/Resources/Config/Catalogs/words.yaml"
)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func wordIDsFromCatalog() throws -> [String] {
    let text = try String(contentsOf: wordsYAML, encoding: .utf8)
    let pattern = #"(?m)^  ([a-z]+):\s*$"#
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        Range(match.range(at: 1), in: text).map { String(text[$0]) }
    }
}

let words: [String]
if CommandLine.arguments.count > 1 {
    words = CommandLine.arguments.dropFirst().map { $0.lowercased() }
} else {
    words = try wordIDsFromCatalog()
}

func renderSymbol(_ symbolName: String) -> NSBitmapImageRep? {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        return nil
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
    ) else { return nil }
    rep.size = NSSize(width: side, height: side)

    let canvas = NSRect(x: 0, y: 0, width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)
    configured.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.setFill()
    canvas.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderText(_ word: String) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: side, height: side)

    let canvas = NSRect(x: 0, y: 0, width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)

    let fontSize: CGFloat = word.count <= 3 ? 36 : (word.count <= 5 ? 28 : 20)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: NSColor.white,
    ]
    let attributed = NSAttributedString(string: word.uppercased(), attributes: attrs)
    let textSize = attributed.size()
    let origin = NSPoint(
        x: (side - textSize.width) / 2,
        y: (side - textSize.height) / 2
    )
    attributed.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for word in words {
    let rep: NSBitmapImageRep
    let label: String
    if let symbol = defaultSymbols[word], let symbolRep = renderSymbol(symbol) {
        rep = symbolRep
        label = symbol
    } else if let textRep = renderText(word) {
        rep = textRep
        label = "text"
    } else {
        FileHandle.standardError.write(Data("failed to render \(word)\n".utf8))
        exit(1)
    }

    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try data.write(to: outDir.appendingPathComponent("\(word).png"))
    print("wrote \(word).png (\(label))")
}

// Prune sprites that are not in the current word list.
let keep = Set(words.map { "\($0).png" })
if let existing = try? FileManager.default.contentsOfDirectory(atPath: outDir.path) {
    for name in existing where name.hasSuffix(".png") && !keep.contains(name) {
        try FileManager.default.removeItem(at: outDir.appendingPathComponent(name))
        print("pruned \(name)")
    }
}
