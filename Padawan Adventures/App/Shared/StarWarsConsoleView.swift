import SpriteKit
import SwiftUI
import UIKit

// MARK: - Palette

enum StarWarsConsolePalette {
    static let crtBlue = Color(red: 0.0, green: 0.78, blue: 1.0)
    static let crtGlow = Color(red: 0.0, green: 0.6, blue: 1.0).opacity(0.55)
    static let screenBackground = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let solvedGreen = Color(red: 0.20, green: 0.85, blue: 0.35)
    static let solvedGlow = Color(red: 0.15, green: 0.75, blue: 0.30).opacity(0.55)

    /// CRT blue → solved green as `progress` goes 0...1.
    static func fillColor(warmingWith progress: Double) -> Color {
        let t = min(1, max(0, progress))
        return Color(
            red: 0.0 + (0.20 - 0.0) * t,
            green: 0.78 + (0.85 - 0.78) * t,
            blue: 1.0 + (0.35 - 1.0) * t
        )
    }

    static func glowColor(warmingWith progress: Double) -> Color {
        fillColor(warmingWith: progress).opacity(0.55)
    }
}

// MARK: - Chrome metrics

struct StarWarsConsoleChrome {
    let rim: CGFloat
    let bezel: CGFloat
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    var contentInset: CGFloat { rim + bezel }

    static func metrics(for size: CGSize) -> StarWarsConsoleChrome {
        let m = min(size.width, size.height)
        return StarWarsConsoleChrome(
            rim: max(0.8, m * 0.022),
            bezel: max(1.2, m * 0.04),
            outerRadius: max(4, m * 0.14),
            innerRadius: max(3, m * 0.10)
        )
    }
}

extension StarWarsConsoleChrome {
    /// Fraction of the plate's min dimension the rim + bezel eat on each edge
    /// (`rim` 0.022 + `bezel` 0.04 in `metrics(for:)`).
    nonisolated static let insetRatio: CGFloat = 0.062

    /// Fraction of a plate's min dimension left for its screen.
    nonisolated static var contentScale: CGFloat { 1 - insetRatio * 2 }

    /// Smallest plate whose screen fits `content`. Assumes a landscape-or-square plate,
    /// i.e. the plate height is the min dimension — true for picture and word plates.
    nonisolated static func plateSize(forContent content: CGSize) -> CGSize {
        let height = max(content.height, 1) / contentScale
        let width = max(max(content.width, 1) + height * insetRatio * 2, height)
        return CGSize(width: width, height: height)
    }

    /// Smallest plate whose screen is exactly `content`, portrait allowed. The chrome inset
    /// is a fraction of the plate's min dimension, so solve against whichever dimension that
    /// is: the plate is landscape exactly when the content is.
    nonisolated static func plateSize(forPromptContent content: CGSize) -> CGSize {
        let width = max(content.width, 1)
        let height = max(content.height, 1)
        if width >= height {
            let plateHeight = height / contentScale
            return CGSize(width: width + plateHeight * insetRatio * 2, height: plateHeight)
        }
        let plateWidth = width / contentScale
        return CGSize(width: plateWidth, height: height + plateWidth * insetRatio * 2)
    }

    /// Usable screen area inside the bezel, in a centre-anchored sprite's local coordinates.
    nonisolated static func screenRect(for size: CGSize) -> CGRect {
        let inset = min(size.width, size.height) * insetRatio
        return CGRect(
            x: -size.width * 0.5 + inset,
            y: -size.height * 0.5 + inset,
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
    }
}

// MARK: - Shared console frame

enum StarWarsConsoleFrameShape {
    case roundedRectangle
    case circle
}

/// Metal bezel + CRT screen shell. `screen` is drawn inside the inset display area.
struct StarWarsConsoleFrame<Screen: View>: View {
    var shape: StarWarsConsoleFrameShape = .roundedRectangle
    var showsScanlines: Bool = true
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        GeometryReader { geo in
            let chrome = StarWarsConsoleChrome.metrics(for: geo.size)
            let m = min(geo.size.width, geo.size.height)

            ZStack {
                chromeShape(.rim, chrome: chrome)
                    .fill(DarkMetalBezel.rimFill)

                chromeShape(.bezel, chrome: chrome)
                    .fill(DarkMetalBezel.outerFill)
                    .overlay(
                        chromeShape(.bezel, chrome: chrome)
                            .stroke(DarkMetalBezel.edgeStroke, lineWidth: max(0.4, m * 0.01))
                    )
                    .padding(chrome.rim)

                consoleScreen(chrome: chrome, reference: m)
                    .padding(chrome.contentInset)
            }
        }
    }

    private func consoleScreen(chrome: StarWarsConsoleChrome, reference m: CGFloat) -> some View {
        ZStack {
            StarWarsConsolePalette.screenBackground

            screen()

            if showsScanlines {
                ScanlineOverlay(spacing: max(2, m * 0.06), lineOpacity: 0.32)
            }

            chromeShape(.screen, chrome: chrome)
                .stroke(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.95),
                            .black.opacity(0.25),
                            .white.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.8, m * 0.02)
                )
        }
        .clipShape(chromeShape(.screen, chrome: chrome))
    }

    private func chromeShape(_ layer: ChromeLayer, chrome: StarWarsConsoleChrome) -> AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            let radius: CGFloat = switch layer {
            case .rim: chrome.outerRadius + chrome.rim
            case .bezel: chrome.outerRadius
            case .screen: chrome.innerRadius
            }
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    private enum ChromeLayer {
        case rim, bezel, screen
    }
}

// MARK: - Masked spelling (underscore → blank rectangle)

/// Renders masked spelling with each `_` as an empty outlined rectangle (underscore width × 1.2 × cap height).
struct MaskedSpellingText: View {
    let text: String
    let fontSize: CGFloat
    var foreground: Color
    var glow: Color

    private var uiFont: UIFont {
        AppFont.uiKit(size: max(1, fontSize))
    }

    private var blankWidth: CGFloat {
        ceil(("_" as NSString).size(withAttributes: [.font: uiFont]).width)
    }

    /// Cap height of surrounding letters — used to vertically center the taller blank.
    private var stringHeight: CGFloat {
        max(1, uiFont.capHeight)
    }

    private var blankHeight: CGFloat {
        stringHeight * 1.2
    }

    private var blankLineWidth: CGFloat {
        max(1.5, fontSize * 0.08)
    }

    /// Gap between a blank run and the adjacent letter (5% of box width).
    private var blankLetterGap: CGFloat {
        blankWidth * 0.05
    }

    /// Last `_` in a leading blank run (`_og` / `__op`) — pad after toward the letter.
    private func isLastLeadingBlank(at offset: Int) -> Bool {
        let chars = Array(text)
        guard offset < chars.count, chars[offset] == "_" else { return false }
        let nextIsLetter = offset + 1 < chars.count && chars[offset + 1] != "_"
        let onlyBlanksBefore = chars[..<offset].allSatisfy { $0 == "_" }
        return nextIsLetter && onlyBlanksBefore
    }

    /// First `_` in a trailing blank run (`do_` / `h___`) — pad before toward the letter.
    private func isFirstTrailingBlank(at offset: Int) -> Bool {
        let chars = Array(text)
        guard offset < chars.count, chars[offset] == "_" else { return false }
        let trailingBlanks = chars[offset...].allSatisfy { $0 == "_" }
        let hasLetterBefore = offset > 0 && chars[offset - 1] != "_"
        return trailingBlanks && hasLetterBefore
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { offset, character in
                if character == "_" {
                    Rectangle()
                        .strokeBorder(foreground, lineWidth: blankLineWidth)
                        .frame(width: blankWidth, height: blankHeight)
                        .shadow(color: glow, radius: max(2, fontSize * 0.12))
                        // Center of box aligns with mid of cap height (stringHeight/2 above baseline).
                        .alignmentGuide(.firstTextBaseline) {
                            $0[VerticalAlignment.center] + stringHeight * 0.5
                        }
                        .padding(.trailing, isLastLeadingBlank(at: offset) ? blankLetterGap : 0)
                        .padding(.leading, isFirstTrailingBlank(at: offset) ? blankLetterGap : 0)
                } else {
                    Text(String(character))
                        .font(AppFont.swiftUI(size: fontSize, weight: .heavy))
                        .foregroundStyle(foreground)
                        .shadow(color: glow, radius: max(2, fontSize * 0.12))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.35)
    }
}

// MARK: - Console plate (text)

/// Compact CRT console frame used for word-plug plates (and previews).
struct StarWarsConsoleView: View {
    let text: String
    var isSolved: Bool = false

    private var accent: Color {
        isSolved ? StarWarsConsolePalette.solvedGreen : StarWarsConsolePalette.crtBlue
    }

    private var glow: Color {
        isSolved ? StarWarsConsolePalette.solvedGlow : StarWarsConsolePalette.crtGlow
    }

    var body: some View {
        GeometryReader { geo in
            let m = min(geo.size.width, geo.size.height)
            let fontSize = max(10, m * 0.42)
            StarWarsConsoleFrame {
                MaskedSpellingText(
                    text: text,
                    fontSize: fontSize,
                    foreground: accent,
                    glow: glow
                )
                .padding(.horizontal, fontSize * 0.25)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Console progress bar

/// CRT console progress fill — shared by loading, combat HUD, and in-scene HP bars.
struct StarWarsConsoleProgressBar: View {
    var progress: Double
    /// When nil, warms from CRT blue → solved green with progress.
    var fillColor: Color? = nil

    private var clamped: Double {
        min(1, max(0, progress))
    }

    private var resolvedFill: Color {
        fillColor ?? StarWarsConsolePalette.fillColor(warmingWith: clamped)
    }

    private var resolvedGlow: Color {
        if fillColor != nil {
            return resolvedFill.opacity(0.55)
        }
        return StarWarsConsolePalette.glowColor(warmingWith: clamped)
    }

    var body: some View {
        StarWarsConsoleFrame {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let height = max(geo.size.height, 1)
                let fillWidth = max(width * clamped, clamped > 0 ? height * 0.35 : 0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: max(2, height * 0.2), style: .continuous)
                        .fill(resolvedFill)
                        .shadow(color: resolvedGlow, radius: max(2, height * 0.25))
                        .frame(width: fillWidth, height: height * 0.72)
                        .padding(.vertical, height * 0.14)
                }
                .frame(width: width, height: height, alignment: .leading)
            }
        }
    }
}

// MARK: - SpriteKit / UIKit rendering

extension StarWarsConsoleView {
    /// Renders the console plate into an `SKTexture` sized for SpriteKit scene points.
    @MainActor
    static func makeTexture(
        text: String,
        size: CGSize,
        isSolved: Bool = false,
        scale: CGFloat = 2
    ) -> SKTexture {
        renderTexture(
            StarWarsConsoleView(text: text, isSolved: isSolved),
            size: size,
            scale: scale,
            placeholderSolved: isSolved
        )
    }
}

// MARK: - Console plate (image + masked word)

/// CRT console plate: word illustration + masked spelling (e.g. `_og` / `do_`).
/// Image is square, sized to the plate's content height. The illustration is the
/// real word art (not a template silhouette) with only a soft CRT glow — the frame
/// scanlines supply the rest of the console look so the picture stays legible.
struct StarWarsConsoleImageView: View {
    let image: UIImage
    /// Lowercase masked spelling shown beside the image (`_og` for dog).
    var maskedText: String = ""
    /// Leading for starting-sound plates; trailing hugs the socket on ending-sound.
    var contentAlignment: Alignment = .leading

    var body: some View {
        GeometryReader { geo in
            let chrome = StarWarsConsoleChrome.metrics(for: geo.size)
            let contentH = max(1, geo.size.height - chrome.contentInset * 2)
            let contentW = max(1, geo.size.width - chrome.contentInset * 2)
            let imageSide = contentH
            let fontSize = max(10, contentH * 0.42)
            StarWarsConsoleFrame {
                HStack(spacing: contentH * 0.12) {
                    Image(uiImage: image)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .shadow(
                            color: StarWarsConsolePalette.crtGlow.opacity(0.45),
                            radius: max(1.5, contentH * 0.05)
                        )
                        .frame(width: imageSide, height: imageSide)

                    if !maskedText.isEmpty {
                        MaskedSpellingText(
                            text: maskedText,
                            fontSize: fontSize,
                            foreground: StarWarsConsolePalette.crtBlue,
                            glow: StarWarsConsolePalette.crtGlow
                        )
                        // Keep letters off the CRT’s trailing edge (esp. ending-sound plates).
                        .padding(.trailing, contentW * 0.05)
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
            }
        }
    }
}

extension StarWarsConsoleImageView {
    /// Renders the illustrated plate into an `SKTexture` sized for SpriteKit scene points.
    @MainActor
    static func makeTexture(
        image: UIImage,
        maskedText: String = "",
        size: CGSize,
        contentAlignment: Alignment = .leading,
        scale: CGFloat = 2
    ) -> SKTexture {
        renderTexture(
            StarWarsConsoleImageView(
                image: image,
                maskedText: maskedText,
                contentAlignment: contentAlignment
            ),
            size: size,
            scale: scale,
            placeholderSolved: false
        )
    }
}

// MARK: - Console plate (merged prompt)

/// CRT prompt screen: illustration centred above a transparent band that live SpriteKit
/// word letters are drawn into. The illustration is the real word art with only a soft
/// CRT glow — same treatment as `StarWarsConsoleImageView` — so pit/gate prompts stay
/// legible; frame scanlines supply the rest of the console look.
struct StarWarsConsolePromptView: View {
    let image: UIImage?
    /// Reserved bottom band height, as a fraction of the plate height.
    var wordBandFraction: CGFloat
    /// Gap between illustration and band, as a fraction of the plate height.
    var gapFraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let band = max(geo.size.height * wordBandFraction, 1)
            let pictureHeight = max(geo.size.height - band - geo.size.height * gapFraction, 1)
            StarWarsConsoleFrame {
                VStack(spacing: geo.size.height * gapFraction) {
                    if let image {
                        Image(uiImage: image)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .shadow(
                                color: StarWarsConsolePalette.crtGlow.opacity(0.45),
                                radius: max(1.5, pictureHeight * 0.05)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Color.clear.frame(height: band)
                }
            }
        }
    }
}

extension StarWarsConsolePromptView {
    @MainActor
    static func makeTexture(
        image: UIImage?,
        wordBandFraction: CGFloat,
        gapFraction: CGFloat,
        size: CGSize,
        scale: CGFloat = 2
    ) -> SKTexture {
        renderTexture(
            StarWarsConsolePromptView(
                image: image,
                wordBandFraction: wordBandFraction,
                gapFraction: gapFraction
            ),
            size: size,
            scale: scale,
            placeholderSolved: false
        )
    }
}

extension StarWarsConsoleProgressBar {
    /// Renders a console progress bar into an `SKTexture` sized for SpriteKit scene points.
    @MainActor
    static func makeTexture(
        progress: Double,
        size: CGSize,
        fillColor: Color? = nil,
        scale: CGFloat = 2
    ) -> SKTexture {
        renderTexture(
            StarWarsConsoleProgressBar(progress: progress, fillColor: fillColor),
            size: size,
            scale: scale,
            placeholderSolved: progress >= 1
        )
    }

    /// Renders a console progress bar into a `UIImage` for UIKit hosts.
    @MainActor
    static func makeUIImage(
        progress: Double,
        size: CGSize,
        fillColor: Color? = nil,
        scale: CGFloat = 2
    ) -> UIImage {
        renderUIImage(
            StarWarsConsoleProgressBar(progress: progress, fillColor: fillColor),
            size: size,
            scale: scale,
            placeholderSolved: progress >= 1
        )
    }
}

@MainActor
private func renderTexture<V: View>(
    _ view: V,
    size: CGSize,
    scale: CGFloat,
    placeholderSolved: Bool
) -> SKTexture {
    let image = renderUIImage(view, size: size, scale: scale, placeholderSolved: placeholderSolved)
    let texture = SKTexture(image: image)
    SpriteSheetLoader.prepareTextureForScaledDisplay(texture)
    return texture
}

@MainActor
private func renderUIImage<V: View>(
    _ view: V,
    size: CGSize,
    scale: CGFloat,
    placeholderSolved: Bool
) -> UIImage {
    let pixelSize = CGSize(
        width: max(1, size.width * scale),
        height: max(1, size.height * scale)
    )
    let framed = view.frame(width: pixelSize.width, height: pixelSize.height)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: pixelSize.width, height: pixelSize.height)
    return renderer.uiImage ?? placeholderImage(size: pixelSize, isSolved: placeholderSolved)
}

@MainActor
private func placeholderImage(size: CGSize, isSolved: Bool) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        let color = isSolved
            ? UIColor(red: 0.20, green: 0.72, blue: 0.30, alpha: 1)
            : UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1)
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - Scanlines

struct ScanlineOverlay: View {
    var spacing: CGFloat = 3
    var lineOpacity: Double = 0.3

    var body: some View {
        Canvas { context, size in
            guard spacing > 0 else { return }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.black.opacity(lineOpacity)), lineWidth: 1)
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Metal bezel fills

private enum DarkMetalBezel {
    static let outerFill = LinearGradient(
        colors: [
            Color(white: 0.14),
            Color(white: 0.06),
            Color(white: 0.16),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let rimFill = LinearGradient(
        colors: [
            Color(white: 0.34),
            Color(white: 0.16),
            Color(white: 0.07),
            Color(white: 0.24),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let edgeStroke = LinearGradient(
        colors: [.white.opacity(0.28), .clear, .black.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Preview

#Preview("Word plate") {
    StarWarsConsoleView(text: "_antha")
        .frame(width: 280, height: 96)
        .padding()
        .background(Color.black)
}

#Preview("Solved") {
    StarWarsConsoleView(text: "bantha", isSolved: true)
        .frame(width: 280, height: 96)
        .padding()
        .background(Color.black)
}

#Preview("Progress") {
    StarWarsConsoleProgressBar(progress: 0.62)
        .frame(width: 280, height: 36)
        .padding()
        .background(Color.black)
}

#Preview("Progress full") {
    StarWarsConsoleProgressBar(progress: 1)
        .frame(width: 280, height: 36)
        .padding()
        .background(Color.black)
}

#Preview("Prompt plate") {
    StarWarsConsolePromptView(
        image: UIImage(systemName: "dog.fill"),
        wordBandFraction: 0.28,
        gapFraction: 0.04
    )
    .frame(width: 180, height: 220)
    .padding()
    .background(Color.black)
}

#Preview("Circular icon") {
    AppCircularIconPlate(systemName: "figure.run", size: 52)
        .padding()
        .background(Color.black)
}
