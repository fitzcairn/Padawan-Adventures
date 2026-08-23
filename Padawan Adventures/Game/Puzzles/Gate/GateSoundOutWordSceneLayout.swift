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

    /// Center-to-center spacing of the bottom choice row, as a multiple of diameter.
    var choiceRowSpacingFactor: CGFloat { 1.35 }

    /// Capacitor size for this round: shrunk so the assembled word fits the play area
    /// and the widest choice row (`choiceCountMax`) fits the chrome-inset width.
    var capacitorDiameter: CGFloat {
        let wordCount = max(engine.targetGraphemes.count, 1)
        let playAvailable = playAreaRect.width - capacitorGap * CGFloat(wordCount + 1)
        let playCap = playAvailable / CGFloat(wordCount)

        let choiceCount = max(engine.config.choiceCountMax, 1)
        let choiceAvailable = max(size.width - chromeInsets.left - chromeInsets.right, 1)
        let choiceCap = choiceAvailable
            / (CGFloat(choiceCount - 1) * choiceRowSpacingFactor + 1)

        return max(min(preferredCapacitorDiameter, playCap, choiceCap), 16)
    }

    /// Minimum center-to-center spacing so neighbouring capacitors don't overlap.
    var minCenterDistance: CGFloat { laidOutDiameter + capacitorGap }

    /// Prompt typography before the CRT plate is fitted to the available room.
    private var basePromptFontSize: CGFloat {
        min(44, size.height * 0.115)
    }

    private var basePromptPictureSide: CGFloat { basePromptFontSize * 1.6 }

    /// Vertical room for the prompt between the safe-area top and the play area.
    private var promptAvailableHeight: CGFloat {
        max(size.height - promptTopInset - playAreaRect.maxY - capacitorGap, 40)
    }

    /// Illustration for this round, or nil when the entry has none / the file is missing.
    var promptImage: UIImage? {
        GateWordPlugImageSprites.image(named: engine.targetEntry.image)
    }

    /// Word row content box (measured word plus side padding) at `fontSize`.
    private func promptWordContent(fontSize: CGFloat) -> CGSize {
        let width = engine.targetGraphemes
            .map { promptLetterWidth($0, fontSize: fontSize) }
            .reduce(0, +) + fontSize * 0.5
        return CGSize(width: width, height: AppFont.uiKit(size: fontSize).lineHeight)
    }

    /// Merged plate height at the unscaled font size — the input to `promptScale`.
    private var naturalPromptPlateHeight: CGFloat {
        MinigameCRTPromptPlate.plateSize(
            pictureSide: promptImage == nil ? 0 : basePromptPictureSide,
            wordContent: promptWordContent(fontSize: basePromptFontSize)
        ).height
    }

    /// Uniform shrink so the CRT plate never reaches the play area. Plate height and
    /// line height are all linear in the font size, so one factor scales the whole plate.
    private var promptScale: CGFloat {
        guard naturalPromptPlateHeight > 0 else { return 1 }
        return min(1, promptAvailableHeight / naturalPromptPlateHeight)
    }

    var promptFontSize: CGFloat {
        max(basePromptFontSize * promptScale, 12)
    }

    var promptTopInset: CGFloat { chromeInsets.top }

    /// Illustration side inside the CRT screen.
    var promptPictureSide: CGFloat { basePromptPictureSide * promptScale }

    var promptPlateSize: CGSize {
        MinigameCRTPromptPlate.plateSize(
            pictureSide: promptImage == nil ? 0 : promptPictureSide,
            wordContent: promptWordContent(fontSize: promptFontSize)
        )
    }

    /// Highest Y a dragged capacitor center may reach without covering the prompt plate.
    func maxPlayableCenterY(for radius: CGFloat) -> CGFloat {
        max(size.height - promptTopInset - promptPlateSize.height - radius, radius)
    }

    /// Midpoint between the left screen edge and the left side of the play area.
    var leftEndpointPosition: CGPoint {
        CGPoint(x: playAreaRect.minX * 0.5, y: playAreaRect.midY)
    }

    /// Midpoint between the right side of the play area and the right screen edge.
    var rightEndpointPosition: CGPoint {
        CGPoint(x: (playAreaRect.maxX + size.width) * 0.5, y: playAreaRect.midY)
    }

    /// Center Y of the bottom-middle choice row: anchored to the bottom of the screen, and
    /// pushed up only far enough to stay clear of the play area.
    var choiceRowCenterY: CGFloat {
        bottomRowCenterY(
            rowHeight: laidOutDiameter,
            ceiling: playAreaRect.minY - capacitorGap - laidOutDiameter * 0.5
        )
    }

    /// Evenly spaced slots for a set of `count` capacitors, centered in the chrome-inset band.
    func choiceRowPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let spacing = laidOutDiameter * choiceRowSpacingFactor
        let span = CGFloat(count - 1) * spacing
        let insetWidth = size.width - chromeInsets.left - chromeInsets.right
        let midX = chromeInsets.left + insetWidth * 0.5
        let startX = midX - span * 0.5
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

    /// Rightmost center X allowed for a drop: the play-area edge. Later letters are
    /// made room for by sliding already-placed capacitors left after a greedy drop.
    func maxDropX(forIndex _: Int) -> CGFloat {
        playAreaRect.maxX - laidOutDiameter * 0.5
    }

    /// Vertical center limits inside the play area. Tall capacitors in a short play
    /// area still only need their center inside.
    var playAreaVerticalCenterLimits: (minY: CGFloat, maxY: CGFloat) {
        let rect = playAreaRect
        let radius = laidOutDiameter * 0.5
        let verticalInset = min(radius, rect.height * 0.5)
        return (rect.minY + verticalInset, rect.maxY - verticalInset)
    }

    /// A drop counts as the right place when it sits inside the play area, clear of
    /// and to the right of the previous capacitor.
    func isValidDrop(_ center: CGPoint) -> Bool {
        guard let index = engine.currentIndex else { return false }
        let vertical = playAreaVerticalCenterLimits
        guard center.y >= vertical.minY, center.y <= vertical.maxY else { return false }
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
        let minX = minDropX(forIndex: index)
        let maxX = maxDropX(forIndex: index)
        let vertical = playAreaVerticalCenterLimits
        guard minX <= maxX, vertical.minY <= vertical.maxY else { return nil }
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, vertical.minY), vertical.maxY)
        )
    }

    /// Unplaced graphemes after the engine has accepted the latest drop.
    var remainingUnplacedCount: Int {
        max(engine.targetGraphemes.count - engine.placedCount, 0)
    }

    /// Later letters fit at current size when the last placed center leaves
    /// `remaining * minCenterDistance` before the play-area's right radius.
    func lastPlacedCenterFitsRemaining(_ x: CGFloat) -> Bool {
        let remaining = remainingUnplacedCount
        guard remaining > 0 else { return true }
        let radius = laidOutDiameter * 0.5
        return x + CGFloat(remaining) * minCenterDistance <= playAreaRect.maxX - radius
    }

    /// Packed centers for already-placed capacitors so unplaced letters still fit.
    /// Y is unchanged. Empty when there are no placed nodes.
    func targetPlacedPositionsFittingRemaining() -> [CGPoint] {
        let current = placedNodes.map(\.position)
        guard let last = current.last else { return current }
        guard remainingUnplacedCount > 0, !lastPlacedCenterFitsRemaining(last.x) else {
            return current
        }

        let radius = laidOutDiameter * 0.5
        let maxLastX = playAreaRect.maxX - radius
            - CGFloat(remainingUnplacedCount) * minCenterDistance
        let deficit = last.x - maxLastX
        let minFirstX = playAreaRect.minX + radius
        if let first = current.first, first.x - deficit >= minFirstX - 0.5 {
            return current.map { CGPoint(x: $0.x - deficit, y: $0.y) }
        }

        return current.enumerated().map { index, point in
            CGPoint(x: minFirstX + CGFloat(index) * minCenterDistance, y: point.y)
        }
    }

    /// Travel from home required before a near-miss drop is assisted into the play area.
    func assistTravelThreshold(fromHome home: CGPoint) -> CGFloat {
        max(tapMoveThreshold * 4, distanceToPlayArea(home) * 0.5)
    }

    /// Near-miss assist: closer to the play area than home, and far enough from home.
    func shouldAssistPlacement(fromHome home: CGPoint, at position: CGPoint) -> Bool {
        let travel = hypot(position.x - home.x, position.y - home.y)
        guard travel >= assistTravelThreshold(fromHome: home) else { return false }
        guard nearestValidDropPoint(to: position) != nil else { return false }
        return distanceToPlayArea(position) < distanceToPlayArea(home)
    }

    /// Play-area center clamp for a placed capacitor, keeping spelling order.
    func clampedPlacedPosition(_ point: CGPoint, forIndex index: Int) -> CGPoint {
        let radius = laidOutDiameter * 0.5
        let vertical = playAreaVerticalCenterLimits
        let minY = vertical.minY
        let maxY = min(vertical.maxY, maxPlayableCenterY(for: radius))
        var minX = playAreaRect.minX + radius
        var maxX = playAreaRect.maxX - radius
        if index > 0, placedNodes.indices.contains(index - 1) {
            minX = max(minX, placedNodes[index - 1].position.x + minCenterDistance)
        }
        if placedNodes.indices.contains(index + 1) {
            maxX = min(maxX, placedNodes[index + 1].position.x - minCenterDistance)
        }
        let x: CGFloat
        if minX > maxX {
            x = (minX + maxX) * 0.5
        } else {
            x = min(max(point.x, minX), maxX)
        }
        return CGPoint(x: x, y: min(max(point.y, minY), maxY))
    }

    // MARK: - Build

    func buildPuzzle() {
        removeAllChildren()
        removeAllActions()
        prompt = nil
        promptLetterNodes = []
        placedNodes = []
        choiceNodes = [:]
        choiceHome = [:]
        connectorSegments = []
        electricityRefreshAccumulator = 0
        dragPlacedIndex = nil
        dragMoved = false
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

    /// One CRT plate at the top of the scene: illustration above, live word letters in the
    /// reserved band below.
    private func buildPromptRow() {
        let fontSize = promptFontSize
        let font = AppFont.uiKit(size: fontSize)
        let letters = engine.targetGraphemes
        let widths = letters.map { promptLetterWidth($0, fontSize: fontSize) }
        let wordWidth = widths.reduce(0, +)

        let prompt = MinigameCRTPromptPlate.makePrompt(
            image: promptImage,
            pictureSide: promptPictureSide,
            wordContent: promptWordContent(fontSize: fontSize),
            name: Self.promptPlateName
        )
        prompt.plate.position = CGPoint(
            x: size.width * 0.5,
            y: size.height - promptTopInset - prompt.plate.size.height * 0.5
        )
        prompt.plate.zPosition = 29
        addChild(prompt.plate)
        self.prompt = prompt

        // Letters are baseline-aligned, so centre their cap-height band on the word band.
        let baselineY = prompt.wordAnchor.y - font.capHeight * 0.5
        var cursorX = -wordWidth * 0.5
        for (index, letter) in letters.enumerated() {
            let node = makePromptLetterNode(letter, fontSize: fontSize, index: index)
            node.position = CGPoint(x: cursorX + widths[index] * 0.5, y: baselineY)
            prompt.plate.addChild(node)
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
        applyPlacedPositionsFittingRemaining(animated: false)
        layoutCurrentChoiceSet(fadeIn: false)
        updateConnectors()
        updatePromptColors()
        if let index = engine.currentIndex {
            setPromptColor(at: index, color: promptActiveColor)
        }
    }
}
