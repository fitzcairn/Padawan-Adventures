import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - Rings

    func rebuildRings() {
        ringLayer.removeAllChildren()
        let geo = geometry

        for ring in geo.rings {
            let color = ringColor(for: ring)
            let ellipse = makeDashedEllipse(rect: geo.ringRect(ring), color: color)
            ringLayer.addChild(ellipse)

            guard let letter = letter(for: ring) else { continue }
            let label = makeOutlinedLetter(
                letter,
                fontSize: max(geo.ringRadii.height * 1.6, 18),
                outline: color
            )
            label.position = geo.ringLabelPosition(ring)
            label.zPosition = Layer.ringLetters
            ringLayer.addChild(label)
        }
    }

    func ringColor(for ring: CombatDeflectRing) -> UIColor {
        let count = max(engine.config.ringCount, 1)
        // Spread the 6-color palette across whatever ring count is configured so
        // the default 3-letter set still lands on red / yellow / blue.
        let paletteIndex = min(
            ring.index * ringColors.count / count,
            ringColors.count - 1
        )
        return ringColors[paletteIndex]
    }

    func letter(for ring: CombatDeflectRing) -> String? {
        let letters = engine.config.letters
        guard ring.index >= 0, ring.index < letters.count else { return nil }
        return letters[ring.index].letter
    }

    /// `SKShapeNode` has no dash property, so the dashes are baked into the path.
    func makeDashedEllipse(rect: CGRect, color: UIColor) -> SKShapeNode {
        let base = CGPath(ellipseIn: rect, transform: nil)
        let dashed = base.copy(dashingWithPhase: 0, lengths: ringDashLengths)
        let node = SKShapeNode(path: dashed)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = ringLineWidth
        node.isAntialiased = true
        node.zPosition = Layer.rings
        return node
    }

    /// `SKLabelNode` cannot stroke text, so outlined letters need `attributedText`.
    /// A negative `strokeWidth` fills *and* strokes; positive would give hollow text.
    func makeOutlinedLetter(
        _ text: String,
        fontSize: CGFloat,
        outline: UIColor
    ) -> SKLabelNode {
        let font = UIFont(name: AppFont.name, size: fontSize)
            ?? UIFont.boldSystemFont(ofSize: fontSize)
        let label = SKLabelNode(attributedText: NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .strokeColor: outline,
                .strokeWidth: -6.0,
            ]
        ))
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}
