import SwiftUI

/// Placeholder shop art until merchant items have sprite sheets.
struct MerchantItemShapeView: View {
    let shape: MerchantItemShape
    var fill: Color = StarWarsConsolePalette.crtBlue
    var glow: Color = StarWarsConsolePalette.crtGlow

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            shapePath(side: side)
                .fill(fill)
                .shadow(color: glow, radius: max(2, side * 0.08))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func shapePath(side: CGFloat) -> Path {
        let inset = side * 0.12
        let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        var path = Path()
        switch shape {
        case .square:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: side * 0.08, height: side * 0.08))
        case .circle:
            path.addEllipse(in: rect)
        case .triangle:
            path.move(to: CGPoint(x: side / 2, y: inset))
            path.addLine(to: CGPoint(x: side - inset, y: side - inset))
            path.addLine(to: CGPoint(x: inset, y: side - inset))
            path.closeSubpath()
        }
        return path
    }
}
