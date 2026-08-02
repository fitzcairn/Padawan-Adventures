import SpriteKit
import UIKit

extension GateWordPlugScene {
    // MARK: - Layout

    func buildPuzzle() {
        tearDownAllCables()
        removeAllChildren()
        plateNodes = [:]
        socketNodes = [:]
        tokenNodes = [:]
        tokenPlugs = [:]
        tokenHome = [:]

        if let background = GateMinigameBackground.wordPlug(sceneSize: size) {
            addChild(background)
        }

        let slots = engine.slots
        guard !slots.isEmpty else { return }

        let rows = max(1, Int((Double(slots.count) / 2.0).rounded(.up)))
        let playArea = CGRect(
            x: 0,
            y: size.height * trayHeightRatio,
            width: size.width,
            height: size.height * (1 - trayHeightRatio)
        )
        let gridArea = playArea.insetBy(
            dx: size.width * gridInsetXRatio,
            dy: playArea.height * gridInsetYRatio
        )
        let rowSlotHeight = gridArea.height / CGFloat(rows)
        let columnGap = size.width * columnGapRatio
        let cellWidth = (gridArea.width - columnGap) / CGFloat(columnCount)
        // Reference sizes as if filling the play grid; draw at uiScale and pack tightly.
        let layoutHeight = min(rowSlotHeight * (1 - rowGapRatio), cellWidth * socketWidthShareMax)
        let layoutDiameter = layoutHeight
        let layoutRectWidth = max(1, cellWidth - layoutDiameter)
        let diameter = layoutDiameter * uiScale
        let rectHeight = layoutHeight * uiScale
        let rectWidth = layoutRectWidth * uiScale
        laidOutDiameter = diameter
        laidOutRectSize = CGSize(width: rectWidth, height: rectHeight)

        let socketRectGap = diameter * 0.20
        let pairWidth = diameter + socketRectGap + rectWidth
        let hGap = columnGap * uiScale
        let vGap = rectHeight * (rowGapRatio / max(1 - rowGapRatio, 0.01))
        let gridWidth = CGFloat(columnCount) * pairWidth + CGFloat(max(columnCount - 1, 0)) * hGap
        let gridHeight = CGFloat(rows) * rectHeight + CGFloat(max(rows - 1, 0)) * vGap
        // Center the board group in the middle of the screen.
        let gridMinX = size.width * 0.5 - gridWidth * 0.5
        let gridMinY = size.height * 0.5 - gridHeight * 0.5

        for (index, slot) in slots.enumerated() {
            let row = index / columnCount
            let column = index % columnCount
            let cellMinX = gridMinX + CGFloat(column) * (pairWidth + hGap)
            let rowCenterY = gridMinY + gridHeight - rectHeight * 0.5 - CGFloat(row) * (rectHeight + vGap)

            let socketCenter = CGPoint(x: cellMinX + diameter * 0.5, y: rowCenterY)
            let rectCenter = CGPoint(x: cellMinX + diameter + socketRectGap + rectWidth * 0.5, y: rowCenterY)

            let plateSize = CGSize(width: rectWidth, height: rectHeight)
            let plate = SKSpriteNode(
                texture: StarWarsConsoleView.makeTexture(
                    text: slot.maskedText,
                    size: plateSize
                ),
                size: plateSize
            )
            plate.position = rectCenter
            plate.name = "rect:\(slot.id.uuidString)"
            plate.zPosition = 10
            addChild(plate)
            plateNodes[slot.id] = plate

            let socket = makeSocketSprite(side: diameter) ?? makeSocketFallback(side: diameter)
            socket.position = socketCenter
            socket.name = "socket:\(slot.id.uuidString)"
            socket.zPosition = 10
            addChild(socket)
            socketNodes[slot.id] = socket
        }

        layoutTrayTokens(diameter: diameter)
    }

    func layoutTrayTokens(diameter: CGFloat) {
        let tokens = engine.tray
        guard !tokens.isEmpty else { return }

        let spacing = diameter * 1.2
        let span = CGFloat(tokens.count - 1) * spacing
        let startX = size.width * 0.5 - span * 0.5
        // Center the letter row in the bottom tray band.
        let y = size.height * trayHeightRatio * 0.5

        for (index, token) in tokens.enumerated() {
            let position = CGPoint(x: startX + CGFloat(index) * spacing, y: y)
            // Home socket stays put under the letter so the empty outlet is visible while dragging.
            let homeSocket = makeSocketSprite(side: diameter) ?? makeSocketFallback(side: diameter)
            homeSocket.position = position
            homeSocket.name = "homeSocket:\(token.id.uuidString)"
            homeSocket.zPosition = 14
            addChild(homeSocket)

            let node = makeTokenNode(token: token, diameter: diameter)
            node.position = position
            addChild(node)
            tokenNodes[token.id] = node
            tokenHome[token.id] = position
        }
    }

    func makeTokenNode(token: GateWordPlugMinigameEngine.LetterToken, diameter: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "token:\(token.id.uuidString)"
        root.zPosition = 20
        root.isUserInteractionEnabled = false

        let plug = makePlugSprite(side: diameter) ?? makePlugFallback(side: diameter)
        plug.name = "tokenPlug"
        plug.zPosition = 0
        plug.isUserInteractionEnabled = false
        root.addChild(plug)
        tokenPlugs[token.id] = plug

        let letter = OutlinedLetterFactory.make(
            text: token.letter,
            fontSize: diameter * 0.42,
            disablesInteraction: true
        )
        // Nudge into the plug face (art is biased left/up by the 3/4 perspective rim).
        letter.position = CGPoint(x: plug.size.width * 0.08, y: -plug.size.height * 0.02)
        letter.zPosition = 1
        root.addChild(letter)

        return root
    }

    func makePlugSprite(side: CGFloat) -> SKSpriteNode? {
        guard let texture = GateWordPlugPlugSprites.randomTexture(using: &socketSpriteRNG) else {
            return nil
        }
        return GateWordPlugPlugSprites.sprite(texture: texture, side: side)
    }

    func makePlugFallback(side: CGFloat) -> SKSpriteNode {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor(white: 0.28, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            UIColor(white: 0.80, alpha: 1).setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: side - 2, height: side - 2))
            ring.lineWidth = max(2, side * 0.05)
            ring.stroke()
        }
        let node = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: side, height: side))
        node.isUserInteractionEnabled = false
        return node
    }

    func makeSocketSprite(side: CGFloat) -> SKSpriteNode? {
        guard let texture = GateWordPlugSocketSprites.randomTexture(using: &socketSpriteRNG) else {
            return nil
        }
        return GateWordPlugSocketSprites.sprite(texture: texture, side: side)
    }

    func makeSocketFallback(side: CGFloat) -> SKSpriteNode {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let inset = side * 0.08
            let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            UIColor(white: 0.35, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: side * 0.12).fill()
            UIColor.white.setStroke()
            let circle = UIBezierPath(
                ovalIn: CGRect(
                    x: side * 0.22,
                    y: side * 0.22,
                    width: side * 0.56,
                    height: side * 0.56
                )
            )
            circle.lineWidth = max(2, side * 0.05)
            circle.stroke()
        }
        let node = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: side, height: side))
        node.isUserInteractionEnabled = false
        return node
    }

    // MARK: - Hit testing

    func draggableToken(at point: CGPoint) -> UUID? {
        // Hit the full plug + letter bounds (not just a circle around the plug center).
        for (id, node) in tokenNodes {
            guard !engine.isTokenPlugged(id) else { continue }
            if node.calculateAccumulatedFrame().contains(point) {
                return id
            }
        }
        return nil
    }

    func plateSlot(at point: CGPoint) -> UUID? {
        let halfW = laidOutRectSize.width * 0.5
        let halfH = laidOutRectSize.height * 0.5
        guard halfW > 0, halfH > 0 else { return nil }
        for (id, node) in plateNodes {
            let bounds = CGRect(
                x: node.position.x - halfW,
                y: node.position.y - halfH,
                width: laidOutRectSize.width,
                height: laidOutRectSize.height
            )
            if bounds.contains(point) {
                return id
            }
        }
        return nil
    }

    func emptySocket(containing point: CGPoint) -> UUID? {
        let hitRadius = laidOutDiameter * 0.75
        guard hitRadius > 0 else { return nil }
        for (id, node) in socketNodes {
            guard !engine.isSlotFilled(id) else { continue }
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            if hypot(dx, dy) <= hitRadius {
                return id
            }
        }
        return nil
    }
}
