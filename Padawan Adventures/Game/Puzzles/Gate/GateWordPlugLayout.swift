import SpriteKit
import UIKit

extension GateWordPlugScene {
    // MARK: - Layout

    func buildPuzzle() {
        removeAllChildren()
        plateNodes = [:]
        socketNodes = [:]
        tokenNodes = [:]
        tokenCircles = [:]
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

            let socket = SKShapeNode(circleOfRadius: diameter * 0.5)
            socket.fillColor = socketFill
            socket.strokeColor = socketStroke
            socket.lineWidth = max(2, diameter * 0.05)
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

        let circle = SKShapeNode(circleOfRadius: diameter * 0.5)
        circle.fillColor = tokenFill
        circle.strokeColor = tokenStroke
        circle.lineWidth = max(2, diameter * 0.05)
        circle.name = "tokenCircle"
        root.addChild(circle)
        tokenCircles[token.id] = circle

        let letter = OutlinedLetterFactory.make(text: token.letter, fontSize: diameter * 0.42)
        letter.zPosition = 1
        letter.isUserInteractionEnabled = false
        root.addChild(letter)

        return root
    }

    // MARK: - Hit testing

    func draggableToken(at point: CGPoint) -> UUID? {
        let radius = laidOutDiameter * 0.5
        guard radius > 0 else { return nil }
        for (id, node) in tokenNodes {
            guard !engine.isTokenPlugged(id) else { continue }
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            if hypot(dx, dy) <= radius {
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
