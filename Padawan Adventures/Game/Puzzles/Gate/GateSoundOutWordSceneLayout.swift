import SpriteKit
import UIKit

extension GateSoundOutWordScene {
    // MARK: - Geometry

    /// Centered play area the graphemes get assembled in (aspect 3:1 landscape).
    var playAreaRect: CGRect {
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
        width *= 0.75
        height *= 0.75
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    /// Base capacitor radius before grapheme/endpoint size adjustments.
    var baseRadius: CGFloat {
        min(size.width, size.height) * 0.07
    }

    /// Grapheme capacitors are 40% larger than the base radius.
    var preferredCapacitorDiameter: CGFloat {
        baseRadius * 1.4 * 2
    }

    /// Empty side capacitors are 40% smaller than the base radius.
    var endpointCapacitorRadius: CGFloat {
        baseRadius * 0.6
    }

    var capacitorGap: CGFloat { 6 }

    /// Capacitor size for this round: shrunk when the word needs more room than the
    /// play area gives at the preferred size, so a full word always fits side by side.
    var capacitorDiameter: CGFloat {
        let count = max(engine.targetGraphemes.count, 1)
        let available = playAreaRect.width - capacitorGap * CGFloat(count + 1)
        let widthCap = available / CGFloat(count)
        return max(min(preferredCapacitorDiameter, widthCap), 16)
    }

    /// Minimum center-to-center spacing so neighbouring capacitors don't overlap.
    var minCenterDistance: CGFloat { laidOutDiameter + capacitorGap }

    /// Prompt typography before the CRT stack is fitted to the available room.
    private var basePromptFontSize: CGFloat {
        min(44, size.height * 0.115)
    }

    private var basePromptPictureSide: CGFloat { basePromptFontSize * 1.6 }

    /// Vertical room for the prompt between the safe-area top and the play area.
    private var promptAvailableHeight: CGFloat {
        max(size.height - promptTopInset - playAreaRect.maxY - capacitorGap, 40)
    }

    /// Height of the CRT stack at the unscaled font size.
    private var naturalPromptStackHeight: CGFloat {
        let font = AppFont.uiKit(size: basePromptFontSize)
        let word = StarWarsConsoleChrome.plateSize(
            forContent: CGSize(width: 1, height: font.lineHeight)
        ).height
        guard engine.targetEntry.image?.isEmpty == false else { return word }
        let picture = StarWarsConsoleChrome.plateSize(
            forContent: CGSize(width: basePromptPictureSide, height: basePromptPictureSide)
        ).height
        return picture + basePromptFontSize * 0.12 + word
    }

    /// Uniform shrink so the CRT stack never reaches the play area. Plate heights and
    /// line height are all linear in the font size, so one factor scales the whole stack.
    private var promptScale: CGFloat {
        guard naturalPromptStackHeight > 0 else { return 1 }
        return min(1, promptAvailableHeight / naturalPromptStackHeight)
    }

    var promptFontSize: CGFloat {
        max(basePromptFontSize * promptScale, 12)
    }

    var promptTopInset: CGFloat {
        let host = view
        let hostSize = host?.bounds.size ?? size
        let safeArea = host?.safeAreaInsets ?? .zero
        return ScreenLayout.uiInsets(size: hostSize, safeArea: safeArea).top
    }

    /// Illustration side inside the CRT screen.
    var promptPictureSide: CGFloat { basePromptPictureSide * promptScale }

    /// CRT plate wrapped around the illustration.
    var promptPicturePlateSize: CGSize {
        StarWarsConsoleChrome.plateSize(
            forContent: CGSize(width: promptPictureSide, height: promptPictureSide)
        )
    }

    /// CRT plate behind the word row; width follows the measured word.
    var promptWordPlateSize: CGSize {
        let fontSize = promptFontSize
        let wordWidth = engine.targetGraphemes
            .map { promptLetterWidth($0, fontSize: fontSize) }
            .reduce(0, +)
        return StarWarsConsoleChrome.plateSize(
            forContent: CGSize(
                width: wordWidth + fontSize * 0.5,
                height: AppFont.uiKit(size: fontSize).lineHeight
            )
        )
    }

    /// Vertical gap between the two plates.
    var promptPictureWordGap: CGFloat { promptFontSize * 0.12 }

    /// Total height of the stacked picture + word plates.
    var promptStackHeight: CGFloat {
        let word = promptWordPlateSize.height
        if engine.targetEntry.image?.isEmpty == false {
            return promptPicturePlateSize.height + promptPictureWordGap + word
        }
        return word
    }

    /// Highest Y a dragged capacitor center may reach without covering the prompt stack.
    func maxPlayableCenterY(for radius: CGFloat) -> CGFloat {
        max(size.height - promptTopInset - promptStackHeight - radius, radius)
    }

    /// Midpoint between the left screen edge and the left side of the play area.
    var leftEndpointPosition: CGPoint {
        CGPoint(x: playAreaRect.minX * 0.5, y: playAreaRect.midY)
    }

    /// Midpoint between the right side of the play area and the right screen edge.
    var rightEndpointPosition: CGPoint {
        CGPoint(x: (playAreaRect.maxX + size.width) * 0.5, y: playAreaRect.midY)
    }

    /// Center Y of the bottom-middle choice row, tucked under the play area.
    var choiceRowCenterY: CGFloat {
        let radius = laidOutDiameter * 0.5
        let band = playAreaRect.minY
        let preferred = band * 0.5
        let ceiling = band - capacitorGap - radius
        return max(min(preferred, ceiling), radius + capacitorGap)
    }

    /// Evenly spaced, horizontally centered slots for a set of `count` capacitors.
    func choiceRowPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let spacing = laidOutDiameter * 1.35
        let span = CGFloat(count - 1) * spacing
        let startX = size.width * 0.5 - span * 0.5
        let y = choiceRowCenterY
        return (0..<count).map { CGPoint(x: startX + CGFloat($0) * spacing, y: y) }
    }

    // MARK: - Drop rules

    /// Leftmost center X allowed for the grapheme at `index`: clear of the previous capacitor.
    func minDropX(forIndex index: Int) -> CGFloat {
        let radius = laidOutDiameter * 0.5
        guard index > 0, let previous = placedNodes.indices.contains(index - 1)
            ? placedNodes[index - 1] : nil else {
            return playAreaRect.minX + radius
        }
        return previous.position.x + minCenterDistance
    }

    /// Rightmost center X allowed for the grapheme at `index`, reserving room for the rest
    /// of the word so a greedy drop can never strand the player.
    func maxDropX(forIndex index: Int) -> CGFloat {
        let radius = laidOutDiameter * 0.5
        let remaining = max(engine.targetGraphemes.count - 1 - index, 0)
        return playAreaRect.maxX - radius - CGFloat(remaining) * minCenterDistance
    }

    /// A drop counts as the right place when it sits inside the play area, clear of and to
    /// the right of the previous capacitor, with room left for the remaining graphemes.
    func isValidDrop(_ center: CGPoint) -> Bool {
        guard let index = engine.currentIndex else { return false }
        let rect = playAreaRect
        let radius = laidOutDiameter * 0.5
        // Tall capacitors in a short play area still only need their center inside.
        let verticalInset = min(radius, rect.height * 0.5)
        guard center.y >= rect.minY + verticalInset,
              center.y <= rect.maxY - verticalInset else {
            return false
        }
        return center.x >= minDropX(forIndex: index) && center.x <= maxDropX(forIndex: index)
    }

    /// Distance from `point` to the play-area rectangle (0 when inside).
    func distanceToPlayArea(_ point: CGPoint) -> CGFloat {
        let rect = playAreaRect
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Closest center that would count as a valid drop for the current grapheme.
    func nearestValidDropPoint(to point: CGPoint) -> CGPoint? {
        guard let index = engine.currentIndex else { return nil }
        let rect = playAreaRect
        let radius = laidOutDiameter * 0.5
        let verticalInset = min(radius, rect.height * 0.5)
        let minX = minDropX(forIndex: index)
        let maxX = maxDropX(forIndex: index)
        let minY = rect.minY + verticalInset
        let maxY = rect.maxY - verticalInset
        guard minX <= maxX, minY <= maxY else { return nil }
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    // MARK: - Build

    func buildPuzzle() {
        removeAllChildren()
        removeAllActions()
        pictureNode = nil
        wordPlateNode = nil
        promptLetterNodes = []
        placedNodes = []
        choiceNodes = [:]
        choiceHome = [:]
        connectorSegments = []
        electricityRefreshAccumulator = 0
        laidOutDiameter = capacitorDiameter

        if let background = GateMinigameBackground.spelling(sceneSize: size) {
            addChild(background)
        }

        buildPromptRow()

        let left = makeEndpointNode(radius: endpointCapacitorRadius, name: "endpoint:left")
        left.position = leftEndpointPosition
        addChild(left)
        leftEndpointNode = left

        let right = makeEndpointNode(radius: endpointCapacitorRadius, name: "endpoint:right")
        right.position = rightEndpointPosition
        addChild(right)
        rightEndpointNode = right
    }

    /// Picture plate on top, word plate underneath — both centered at the top of the scene.
    private func buildPromptRow() {
        let fontSize = promptFontSize
        let font = AppFont.uiKit(size: fontSize)
        let letters = engine.targetGraphemes
        let widths = letters.map { promptLetterWidth($0, fontSize: fontSize) }
        let wordWidth = widths.reduce(0, +)
        let centerX = size.width * 0.5
        let stackTop = size.height - promptTopInset

        var wordPlateTop = stackTop
        if let picture = makePictureNode(side: promptPictureSide) {
            picture.position = CGPoint(x: centerX, y: stackTop - picture.size.height * 0.5)
            addChild(picture)
            pictureNode = picture
            wordPlateTop = stackTop - picture.size.height - promptPictureWordGap
        }

        let plateSize = promptWordPlateSize
        let plateCenterY = wordPlateTop - plateSize.height * 0.5
        let plate = MinigameCRTPromptPlate.makeWordPlate(
            size: plateSize,
            name: Self.wordPlateName
        )
        plate.position = CGPoint(x: centerX, y: plateCenterY)
        plate.zPosition = 29
        addChild(plate)
        wordPlateNode = plate

        // Letters are baseline-aligned, so centre their cap-height band on the plate.
        let letterBaselineY = plateCenterY - font.capHeight * 0.5
        var cursorX = centerX - wordWidth * 0.5
        for (index, letter) in letters.enumerated() {
            let node = makePromptLetterNode(letter, fontSize: fontSize, index: index)
            node.position = CGPoint(x: cursorX + widths[index] * 0.5, y: letterBaselineY)
            addChild(node)
            promptLetterNodes.append(node)
            cursorX += widths[index]
        }
    }

    func promptLetterWidth(_ letter: String, fontSize: CGFloat) -> CGFloat {
        let font = AppFont.uiKit(size: max(1, fontSize))
        let bounds = (letter as NSString).size(withAttributes: [.font: font])
        return ceil(bounds.width)
    }

    // MARK: - Resize

    /// Re-places already-solved graphemes (by stored play-area fraction) and the live set.
    func restoreProgress() {
        let rect = playAreaRect
        for (index, fraction) in placedFractions.enumerated() {
            guard let grapheme = engine.grapheme(at: index) else { continue }
            let node = makeCapacitorNode(
                name: "placed:\(index)",
                diameter: laidOutDiameter,
                grapheme: grapheme
            )
            node.position = CGPoint(
                x: rect.minX + rect.width * fraction.x,
                y: rect.minY + rect.height * fraction.y
            )
            node.zPosition = 20
            addChild(node)
            placedNodes.append(node)
        }
        layoutCurrentChoiceSet(fadeIn: false)
        updateConnectors()
        updatePromptColors()
        if let index = engine.currentIndex {
            setPromptColor(at: index, color: promptActiveColor)
        }
    }
}
