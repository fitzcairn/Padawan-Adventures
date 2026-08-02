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
            rim: max(2, m * 0.055),
            bezel: max(3, m * 0.10),
            outerRadius: max(4, m * 0.14),
            innerRadius: max(3, m * 0.10)
        )
    }
}

// MARK: - Shared console frame

/// Metal bezel + CRT screen shell. `screen` is drawn inside the inset display area.
struct StarWarsConsoleFrame<Screen: View>: View {
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        GeometryReader { geo in
            let chrome = StarWarsConsoleChrome.metrics(for: geo.size)
            let m = min(geo.size.width, geo.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: chrome.outerRadius + chrome.rim, style: .continuous)
                    .fill(DarkMetalBezel.rimFill)

                RoundedRectangle(cornerRadius: chrome.outerRadius, style: .continuous)
                    .fill(DarkMetalBezel.outerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: chrome.outerRadius, style: .continuous)
                            .stroke(DarkMetalBezel.edgeStroke, lineWidth: max(1, m * 0.025))
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

            ScanlineOverlay(spacing: max(2, m * 0.06), lineOpacity: 0.32)

            RoundedRectangle(cornerRadius: chrome.innerRadius, style: .continuous)
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
                    lineWidth: max(2, m * 0.05)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: chrome.innerRadius, style: .continuous))
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
                Text(text)
                    .font(AppFont.swiftUI(size: fontSize, weight: .heavy))
                    .foregroundStyle(accent)
                    .shadow(color: glow, radius: max(2, fontSize * 0.12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
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

// MARK: - Console plate (image)

/// CRT console plate showing a word illustration instead of text.
struct StarWarsConsoleImageView: View {
    let image: UIImage

    var body: some View {
        GeometryReader { geo in
            let m = min(geo.size.width, geo.size.height)
            StarWarsConsoleFrame {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(StarWarsConsolePalette.crtBlue)
                    .shadow(color: StarWarsConsolePalette.crtGlow, radius: max(2, m * 0.08))
                    .padding(m * 0.12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

extension StarWarsConsoleImageView {
    /// Renders the illustrated plate into an `SKTexture` sized for SpriteKit scene points.
    @MainActor
    static func makeTexture(image: UIImage, size: CGSize, scale: CGFloat = 2) -> SKTexture {
        renderTexture(
            StarWarsConsoleImageView(image: image),
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
