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
                node.name = Self.orbBlankNodeName
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

    private static let orbBlankNodeName = "orbBlank"
    /// Revealed answer is 10% larger than the surrounding white letters.
    private static let orbRevealLetterScale: CGFloat = 1.1

    /// Swaps the blank square(s) for the answer grapheme in orange, larger than the
    /// white letters but sharing their baseline so the word still reads as one line.
    func revealOrbAnswerLetter(on orb: OrbVisual) {
        let row = orb.wordNode
        let blanks = row.children.filter { $0.name == Self.orbBlankNodeName }
        guard !blanks.isEmpty else { return }

        let fontSize = blanks.compactMap { OutlinedLetterFactory.fontSize(from: $0) }.first
            ?? orbWordFontSize
        let blankWidth = OutlinedLetterFactory.blankSize(fontSize: fontSize).width
        let left = blanks.map { $0.position.x - blankWidth * 0.5 }.min() ?? 0
        let right = blanks.map { $0.position.x + blankWidth * 0.5 }.max() ?? 0
        let centerX = (left + right) * 0.5
        // Blank stacks are already placed on the white letters' baseline.
        let baselineY = blanks[0].position.y

        for blank in blanks {
            blank.removeFromParent()
        }

        let reveal = OutlinedLetterFactory.make(
            text: orb.letter,
            fontSize: fontSize * Self.orbRevealLetterScale
        )
        for case let label as SKLabelNode in reveal.children {
            label.verticalAlignmentMode = .baseline
        }
        OutlinedLetterFactory.fillLabel(in: reveal)?.fontColor = .systemOrange
        reveal.position = CGPoint(x: centerX, y: baselineY)
        reveal.zPosition = 1
        row.addChild(reveal)
    }
}
