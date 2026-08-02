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
}

// MARK: - Console plate

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
            let rim = max(2, m * 0.055)
            let bezel = max(3, m * 0.10)
            let outerRadius = max(4, m * 0.14)
            let innerRadius = max(3, m * 0.10)
            let fontSize = max(10, m * 0.42)

            ZStack {
                RoundedRectangle(cornerRadius: outerRadius + rim, style: .continuous)
                    .fill(DarkMetalBezel.rimFill)

                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(DarkMetalBezel.outerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                            .stroke(DarkMetalBezel.edgeStroke, lineWidth: max(1, m * 0.025))
                    )
                    .padding(rim)

                consoleScreen(innerRadius: innerRadius, fontSize: fontSize)
                    .padding(rim + bezel)
            }
        }
    }

    private func consoleScreen(innerRadius: CGFloat, fontSize: CGFloat) -> some View {
        ZStack {
            StarWarsConsolePalette.screenBackground

            Text(text)
                .font(AppFont.swiftUI(size: fontSize, weight: .heavy))
                .foregroundStyle(accent)
                .shadow(color: glow, radius: max(2, fontSize * 0.12))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.horizontal, fontSize * 0.25)

            ScanlineOverlay(spacing: max(2, fontSize * 0.12), lineOpacity: 0.32)

            RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
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
                    lineWidth: max(2, fontSize * 0.12)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
    }
}

// MARK: - SpriteKit rendering

extension StarWarsConsoleView {
    /// Renders the console plate into an `SKTexture` sized for SpriteKit scene points.
    @MainActor
    static func makeTexture(
        text: String,
        size: CGSize,
        isSolved: Bool = false,
        scale: CGFloat = 2
    ) -> SKTexture {
        let pixelSize = CGSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )
        let view = StarWarsConsoleView(text: text, isSolved: isSolved)
            .frame(width: pixelSize.width, height: pixelSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: pixelSize.width, height: pixelSize.height)

        let image = renderer.uiImage ?? placeholderImage(size: pixelSize, isSolved: isSolved)
        let texture = SKTexture(image: image)
        SpriteSheetLoader.prepareTextureForScaledDisplay(texture)
        return texture
    }

    @MainActor
    private static func placeholderImage(size: CGSize, isSolved: Bool) -> UIImage {
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
