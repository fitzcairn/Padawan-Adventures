import SpriteKit
import UIKit

extension GateLetterMatchScene {
    // MARK: - Layout

    /// Fit bounds for the letter row — background image frame when available.
    var letterRowBounds: CGRect {
        if let bg = GateMinigameBackground.letterMatchFrame(sceneSize: size), bg.width > 1 {
            return bg
        }
        // Aspect 3:1 landscape fallback, ~40% of screen area.
        let area = size.width * size.height * 0.40
        var width = sqrt(area * 3)
        var height = width / 3
        if width > size.width * 0.9 {
            width = size.width * 0.9
            height = width / 3
        }
        if height > size.height * 0.7 {
            height = size.height * 0.7
            width = height * 3
        }
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    /// Aesthetic target size before fitting into the background width.
    var preferredTileSize: CGFloat {
        let bounds = letterRowBounds
        let maxByHeight = bounds.height * 0.55
        return min(maxByHeight, min(size.width, size.height) * 0.18) * 1.344
    }

    /// Compresses horizontal padding first; shrinks sprite size only after padding hits the floor.
    func letterRowLayout(letterCount: Int) -> LetterRowLayout {
        let count = max(letterCount, 1)
        let n = CGFloat(count)
        let bounds = letterRowBounds
        let availableWidth = bounds.width * (1 - 2 * backgroundEdgeInsetRatio)

        var side = preferredTileSize
        var gap = side * preferredGapRatio

        func rowWidth(side: CGFloat, gap: CGFloat) -> CGFloat {
            n * side + max(n - 1, 0) * gap
        }

        if rowWidth(side: side, gap: gap) > availableWidth {
            let minGap = side * minGapRatio
            if count > 1, rowWidth(side: side, gap: minGap) <= availableWidth {
                gap = max(minGap, (availableWidth - n * side) / (n - 1))
            } else {
                // Out of padding room — shrink tiles, keeping min gap ratio.
                let denom = n + max(n - 1, 0) * minGapRatio
                side = max(1, availableWidth / max(denom, 1))
                gap = count > 1 ? side * minGapRatio : 0
            }
        }

        let totalWidth = rowWidth(side: side, gap: gap)
        let firstCenterX = bounds.midX - totalWidth * 0.5 + side * 0.5
        return LetterRowLayout(
            side: side,
            gap: gap,
            firstCenterX: firstCenterX,
            centerY: bounds.midY
        )
    }

    func buildPuzzle() {
        removeAllChildren()
        letterNodes = [:]
        switchNodes = [:]
        switchTextures = GateLetterMatchSwitchSprites.load()

        if let background = GateMinigameBackground.letterMatch(sceneSize: size) {
            background.alpha = 0.8
            addChild(background)
        }

        layoutLetterRow()
    }

    func layoutLetterRow() {
        let tokens = engine.letters
        guard !tokens.isEmpty else { return }

        let layout = letterRowLayout(letterCount: tokens.count)
        laidOutTileSide = layout.side
        var x = layout.firstCenterX

        for token in tokens {
            let node = makeLetterNode(token: token, side: layout.side)
            node.position = CGPoint(x: x, y: layout.centerY)
            addChild(node)
            letterNodes[token.id] = node
            x += layout.side + layout.gap
        }
    }

    func makeLetterNode(token: GateLetterMatchMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        let matched = engine.matchedIDs.contains(token.id)
        if let textures = switchTextures {
            let texture = matched ? textures.on : textures.off
            if let switchNode = GateLetterMatchSwitchSprites.sprite(texture: texture, side: side) {
                switchNode.zPosition = 0
                switchNode.name = "switch"
                root.addChild(switchNode)
                switchNodes[token.id] = switchNode
            }
        } else {
            let square = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: side * 0.12)
            square.fillColor = matched ? squareMatchedFill : squareFill
            square.strokeColor = UIColor(white: 0.25, alpha: 1)
            square.lineWidth = 2
            square.zPosition = 0
            square.name = "switchFallback"
            root.addChild(square)
        }

        let letter = OutlinedLetterFactory.make(text: token.letter, fontSize: side * 0.378)
        letter.zPosition = 1
        letter.isUserInteractionEnabled = false
        root.addChild(letter)

        return root
    }
}
