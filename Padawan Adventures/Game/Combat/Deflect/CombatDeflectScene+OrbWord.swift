import SpriteKit
import UIKit

extension CombatDeflectScene {
    /// The word with its answer grapheme blanked out, laid out as one centered row of
    /// `OutlinedLetterFactory` stacks (white fill, black outline) and blank boxes.
    /// The returned node's origin is the row's visual center; `width` is the laid-out
    /// advance width, used to size the projectile art around it.
    func makeMaskedWordNode(
        word: String,
        grapheme: String,
        fontSize: CGFloat
    ) -> (node: SKNode, width: CGFloat) {
        let row = SKNode()
        row.isUserInteractionEnabled = false
        let units = CombatDeflectOrbWord.maskedUnits(
            word: word,
            grapheme: grapheme,
            position: engine.config.letterPosition
        )
        guard !units.isEmpty else { return (row, 0) }

        let font = AppFont.uiKit(size: max(1, fontSize))
        let widths = units.map { unit -> CGFloat in
            unit == "_"
                ? OutlinedLetterFactory.blankSize(fontSize: fontSize).width
                : ceil((unit as NSString).size(withAttributes: [.font: font]).width)
        }
        let blankLeads = engine.config.letterPosition == .starting
        let blankGap = OutlinedLetterFactory.blankSize(fontSize: fontSize).width
            * Self.orbBlankLetterGapFraction
        // One gap between the blank run and the visible letters (not between letters).
        var gapsBefore = [CGFloat](repeating: 0, count: units.count)
        if blankGap > 0 {
            for index in units.indices {
                if blankLeads {
                    if units[index] != "_",
                       index > 0,
                       units[index - 1] == "_",
                       units[..<index].allSatisfy({ $0 == "_" }) {
                        gapsBefore[index] = blankGap
                    }
                } else if units[index] == "_",
                          index > 0,
                          units[index - 1] != "_",
                          units[index...].allSatisfy({ $0 == "_" }) {
                    gapsBefore[index] = blankGap
                }
            }
        }
        let totalWidth = zip(widths, gapsBefore).map(+).reduce(0, +)
        // Baseline-aligned units center on `capHeight / 2`; drop the row so the
        // node origin is the visual middle.
        let baselineDrop = -font.capHeight * 0.5
        var cursorX = -totalWidth * 0.5

        for (index, unit) in units.enumerated() {
            let node: SKNode
            if unit == "_" {
                node = OutlinedLetterFactory.makeBlank(fontSize: fontSize)
            } else {
                node = OutlinedLetterFactory.make(text: unit, fontSize: fontSize)
                for case let label as SKLabelNode in node.children {
                    label.verticalAlignmentMode = .baseline
                }
            }
            cursorX += gapsBefore[index]
            node.position = CGPoint(x: cursorX + widths[index] * 0.5, y: baselineDrop)
            row.addChild(node)
            cursorX += widths[index]
        }
        return (row, totalWidth)
    }
}
