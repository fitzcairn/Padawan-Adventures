import SpriteKit
import SwiftUI
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
        homeSocketNodes = [:]
        openPlugSwirlsActive = false

        if let background = GateMinigameBackground.wordPlug(sceneSize: size) {
            addChild(background)
        }

        let slots = engine.slots
        guard !slots.isEmpty else { return }

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

        // Prefer 2 columns; use 3 when the 2-column board is too wide. Last row may be short.
        boardColumnCount = preferredColumnCount
        var rows = max(1, Int((Double(slots.count) / Double(boardColumnCount)).rounded(.up)))
        let columnGap = size.width * columnGapRatio
        let hGapBase = columnGap * uiScale

        func metrics(columns: Int, rows: Int) -> (diameter: CGFloat, rectHeight: CGFloat, rectWidth: CGFloat, pairWidth: CGFloat, hGap: CGFloat, vGap: CGFloat, gridWidth: CGFloat, gridHeight: CGFloat) {
            // Size against at least `minLayoutRows` so sparse boards keep a sane element size.
            let sizingRows = max(rows, minLayoutRows)
            let rowSlotHeight = gridArea.height / CGFloat(sizingRows)
            let cellWidth = (gridArea.width - columnGap * CGFloat(max(columns - 1, 0))) / CGFloat(columns)
            let layoutHeight = min(rowSlotHeight * (1 - rowGapRatio), cellWidth * socketWidthShareMax) * sizeCapScale
            let diameter = layoutHeight * uiScale
            let rectHeight = layoutHeight * uiScale
            let fontSize = rectHeight * 0.42
            let longest = slots.map(\.word).max(by: { $0.count < $1.count }) ?? ""
            let textWidth = plateTextWidth(longest, fontSize: fontSize)
            // Square image (side = plate height) + masked text + chrome/gap +
            // 5% trailing word padding (see StarWarsConsoleImageView).
            let contentWidth = rectHeight + textWidth + fontSize * 1.35 + rectHeight * 0.35
            let rectWidth = max(diameter * 1.15, contentWidth * 1.05)
            let socketRectGap = diameter * 0.20
            let pairWidth = diameter + socketRectGap + rectWidth
            let hGap = hGapBase
            let vGap = rectHeight * (rowGapRatio / max(1 - rowGapRatio, 0.01))
            let gridWidth = CGFloat(columns) * pairWidth + CGFloat(max(columns - 1, 0)) * hGap
            let gridHeight = CGFloat(rows) * rectHeight + CGFloat(max(rows - 1, 0)) * vGap
            return (diameter, rectHeight, rectWidth, pairWidth, hGap, vGap, gridWidth, gridHeight)
        }

        func fit(
            _ layout: (diameter: CGFloat, rectHeight: CGFloat, rectWidth: CGFloat, pairWidth: CGFloat, hGap: CGFloat, vGap: CGFloat, gridWidth: CGFloat, gridHeight: CGFloat)
        ) -> (diameter: CGFloat, rectHeight: CGFloat, rectWidth: CGFloat, pairWidth: CGFloat, hGap: CGFloat, vGap: CGFloat, gridWidth: CGFloat, gridHeight: CGFloat) {
            guard layout.gridWidth > 0, layout.gridHeight > 0 else { return layout }
            let scale = min(
                1,
                gridArea.width / layout.gridWidth,
                gridArea.height / layout.gridHeight
            )
            guard scale < 1 else { return layout }
            return (
                layout.diameter * scale,
                layout.rectHeight * scale,
                layout.rectWidth * scale,
                layout.pairWidth * scale,
                layout.hGap * scale,
                layout.vGap * scale,
                layout.gridWidth * scale,
                layout.gridHeight * scale
            )
        }

        var layout = metrics(columns: boardColumnCount, rows: rows)
        let twoColumnBoardTooWide = layout.gridWidth > gridArea.width + 0.5
        if twoColumnBoardTooWide {
            boardColumnCount = expandedColumnCount
            rows = max(1, Int((Double(slots.count) / Double(boardColumnCount)).rounded(.up)))
            layout = metrics(columns: boardColumnCount, rows: rows)
        }
        layout = fit(layout)

        let diameter = layout.diameter
        let rectHeight = layout.rectHeight
        let rectWidth = layout.rectWidth
        let pairWidth = layout.pairWidth
        let hGap = layout.hGap
        let vGap = layout.vGap
        let socketRectGap = diameter * 0.20
        laidOutDiameter = diameter
        laidOutRectSize = CGSize(width: rectWidth, height: rectHeight)

        let gridWidth = layout.gridWidth
        let gridHeight = layout.gridHeight
        // Center the board in the play area so it stays above the tray.
        let gridMinX = size.width * 0.5 - gridWidth * 0.5
        let gridMinY = playArea.minY + (playArea.height - gridHeight) * 0.5

        for (index, slot) in slots.enumerated() {
            let row = index / boardColumnCount
            let column = index % boardColumnCount
            let cellMinX = gridMinX + CGFloat(column) * (pairWidth + hGap)
            let rowCenterY = gridMinY + gridHeight - rectHeight * 0.5 - CGFloat(row) * (rectHeight + vGap)

            // Ending-sound rows put the socket beside the trailing blank: [plate] gap [socket].
            let socketLeads = puzzleConfig.letterPosition == .starting
            let socketCenter = CGPoint(
                x: cellMinX + (socketLeads ? diameter * 0.5 : rectWidth + socketRectGap + diameter * 0.5),
                y: rowCenterY
            )
            let rectCenter = CGPoint(
                x: cellMinX + (socketLeads ? diameter + socketRectGap : 0) + rectWidth * 0.5,
                y: rowCenterY
            )

            let plateSize = CGSize(width: rectWidth, height: rectHeight)
            // Ending-sound: hug the trailing socket so image + blank sit on the right.
            let plateAlignment: Alignment =
                puzzleConfig.letterPosition == .ending ? .trailing : .leading
            let plateTexture = GateWordPlugImageSprites.image(named: slot.imageName).map {
                StarWarsConsoleImageView.makeTexture(
                    image: $0,
                    maskedText: slot.maskedText,
                    size: plateSize,
                    contentAlignment: plateAlignment
                )
            } ?? StarWarsConsoleView.makeTexture(text: slot.maskedText, size: plateSize)
            let plate = SKSpriteNode(texture: plateTexture, size: plateSize)
            plate.position = rectCenter
            plate.name = "rect:\(slot.id.uuidString)"
            plate.zPosition = 10
            let screen = StarWarsConsoleChrome.screenRect(for: plateSize)
            // Ending-sound plates hug the right; put the play icon on the left and mirror it.
            let playEdge: MinigameCRTPromptPlate.PlayIconEdge =
                puzzleConfig.letterPosition == .ending ? .leading : .trailing
            MinigameCRTPromptPlate.attachPlayIcon(
                to: plate,
                areaHeight: screen.height,
                edge: playEdge,
                scale: 1.3
            )
            addChild(plate)
            plateNodes[slot.id] = plate

            let socket = makeSocketSprite(side: diameter) ?? makeSocketFallback(side: diameter)
            socket.position = socketCenter
            socket.name = "socket:\(slot.id.uuidString)"
            socket.zPosition = 10
            addChild(socket)
            socketNodes[slot.id] = socket
        }

        layoutTrayTokens(boardDiameter: diameter, boardBottomY: gridMinY)
    }

    func plateTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = AppFont.uiKit(size: max(1, fontSize))
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: font.lineHeight * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.width)
    }

    func layoutTrayTokens(boardDiameter: CGFloat, boardBottomY: CGFloat) {
        let tokens = engine.tray
        guard !tokens.isEmpty else { return }

        let insets = chromeInsets
        let bottomInset = ScreenLayout.swipeRowBottomInset(
            sceneHeight: size.height,
            chromeBottom: insets.bottom
        )
        let fitted = GateWordPlugTrayGeometry.layout(
            count: tokens.count,
            boardDiameter: boardDiameter,
            sceneSize: size,
            leftInset: insets.left,
            rightInset: insets.right,
            bottomInset: bottomInset,
            boardBottomY: boardBottomY
        )
        let trayDiameter = fitted.diameter
        let homes = fitted.homes
        guard homes.count == tokens.count else { return }

        for (token, position) in zip(tokens, homes) {
            // Home socket stays put under the letter so the empty outlet is visible while dragging.
            let homeSocket = makeSocketSprite(side: trayDiameter) ?? makeSocketFallback(side: trayDiameter)
            homeSocket.position = position
            homeSocket.name = "homeSocket:\(token.id.uuidString)"
            homeSocket.zPosition = 14
            addChild(homeSocket)
            homeSocketNodes[token.id] = homeSocket

            let node = makeTokenNode(token: token, diameter: trayDiameter)
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
