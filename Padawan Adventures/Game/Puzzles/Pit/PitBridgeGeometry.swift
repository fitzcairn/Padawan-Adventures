import CoreGraphics
import Foundation

/// Layout math for the pit-bridge arena (pads, slots, tray). Pure and unit-testable.
nonisolated struct PitBridgeGeometry: Equatable, Sendable {
    /// The prompt block hangs from the shared top chrome inset so the CRT plate grows downward.
    /// Expressed as a fraction because this geometry is pure; it matches `ScreenLayout` because
    /// landscape has no top safe-area inset to take the max against.
    static let wordPromptTopFraction: CGFloat = 1 - ScreenLayout.edgeInsetFraction
    /// Side pads sit this fraction below scene mid-height.
    static let bridgeLineDownShift: CGFloat = 0.20
    /// Placed tiles, dashed slot, and player sit this fraction below the pad mid-line.
    static let bridgeContentDownShift: CGFloat = 0.10
    /// Tray tile centers as fractions of scene width.
    static let trayXFractions: [CGFloat] = [0.25, 0.5, 0.75]
    /// Drop hit radius as a fraction of the tile side. Larger than the dashed box
    /// half-diagonal (~0.71) so near-misses still count.
    static let dropRadiusScale: CGFloat = 1.25

    var sceneSize: CGSize
    /// AABB of the 2x2 isometric floor block used for each side pad.
    var padSize: CGSize
    /// Number of bridge slots (== words this session).
    var slotCount: Int

    /// Target max dimension for the word illustration.
    var wordPromptMaxSide: CGFloat {
        min(sceneSize.width * 0.28, sceneSize.height * 0.16, tileSide * 1.8)
    }

    /// Height of the merged CRT prompt plate: illustration over the word band.
    /// Word line height is approximated at 1.3x the font size because `AppFont` is
    /// MainActor-isolated; word width is approximated with `wordPromptMaxSide`.
    var wordPromptBlockHeight: CGFloat {
        let fontSize = max(wordPromptMaxSide * 0.28, 18)
        return MinigameCRTPromptPlate.plateSize(
            pictureSide: wordPromptMaxSide,
            wordContent: CGSize(width: wordPromptMaxSide, height: fontSize * 1.3)
        ).height
    }

    /// Centre of the top-anchored prompt block.
    var wordPromptCenter: CGPoint {
        CGPoint(
            x: sceneSize.width * 0.5,
            y: sceneSize.height * Self.wordPromptTopFraction - wordPromptBlockHeight * 0.5
        )
    }

    /// Bottom edge of a vertically centred pad, before the bridge down-shift.
    private var unshiftedPadMinY: CGFloat {
        (sceneSize.height - padSize.height) * 0.5
    }

    /// Shared vertical origin for both side pads after the bridge down-shift.
    private var padMinY: CGFloat {
        let unshiftedMidY = unshiftedPadMinY + padSize.height * 0.5
        let shiftedMidY = unshiftedMidY * (1 - Self.bridgeLineDownShift)
        return shiftedMidY - padSize.height * 0.5
    }

    var leftPadRect: CGRect {
        CGRect(x: 0, y: padMinY, width: padSize.width, height: padSize.height)
    }

    var rightPadRect: CGRect {
        CGRect(
            x: sceneSize.width - padSize.width,
            y: padMinY,
            width: padSize.width,
            height: padSize.height
        )
    }

    /// One isometric tile wide — half the 2x2 pad footprint.
    var tileSide: CGFloat {
        padSize.width * 0.5
    }

    /// Vertical centre of placed tiles, the dashed slot, and the player.
    var bridgeLineY: CGFloat {
        leftPadRect.midY * (1 - Self.bridgeContentDownShift)
    }

    var slotSpacing: CGFloat {
        let count = max(slotCount, 1)
        return (rightPadRect.minX - leftPadRect.maxX) / CGFloat(count + 1)
    }

    func slotCenter(_ index: Int) -> CGPoint {
        CGPoint(
            x: leftPadRect.maxX + slotSpacing * CGFloat(index + 1),
            y: bridgeLineY
        )
    }

    func trayCenter(_ index: Int) -> CGPoint {
        let fractions = Self.trayXFractions
        let fraction = fractions[index % fractions.count]
        let x = sceneSize.width * fraction
        let maxY = leftPadRect.minY - tileSide * 0.6
        let y = ScreenLayout.bottomRowCenterY(
            rowHeight: tileSide,
            bottomInset: ScreenLayout.swipeRowBottomInset(
                sceneHeight: sceneSize.height,
                chromeBottom: sceneSize.height * ScreenLayout.edgeInsetFraction
            ),
            ceiling: maxY
        )
        return CGPoint(x: x, y: y)
    }

    func distance(from point: CGPoint, toSlot index: Int) -> CGFloat {
        let center = slotCenter(index)
        return hypot(point.x - center.x, point.y - center.y)
    }

    func isDrop(_ point: CGPoint, onSlot index: Int) -> Bool {
        distance(from: point, toSlot: index) <= tileSide * Self.dropRadiusScale
    }
}
