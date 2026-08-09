import SpriteKit
import UIKit

/// Single CRT console plate for the word prompt at the top of a minigame: illustration
/// top-middle, a transparent band for the live word letters bottom-middle, and a small
/// play icon in the upper right (tapping the plate plays a sound).
@MainActor
enum MinigameCRTPromptPlate {
    static let iconName = "crtPlatePlayIcon"
    /// Icon side as a fraction of the picture-area height — deliberately smaller than the
    /// capacitor / floor-tile play icons, which are the primary affordance.
    nonisolated static let iconSideScale: CGFloat = 0.22
    nonisolated static let iconMarginScale: CGFloat = 0.08
    /// Gap between illustration and word band, as a fraction of the illustration side.
    nonisolated static let pictureWordGapScale: CGFloat = 0.06

    enum Region: Equatable {
        case picture
        case word
    }

    /// Plate-local geometry of a merged prompt plate. Plate-local coordinates are
    /// centre-anchored, matching `StarWarsConsoleChrome.screenRect(for:)`.
    nonisolated struct Regions: Equatable {
        let plateSize: CGSize
        let wordBandRect: CGRect
        /// Everything above the band, including the play icon.
        let pictureRect: CGRect
        /// Where a baseline-aligned word row hangs from: centred on the band.
        var wordAnchor: CGPoint { CGPoint(x: 0, y: wordBandRect.midY) }
    }

    struct Prompt {
        let plate: SKSpriteNode
        let regions: Regions
        var wordAnchor: CGPoint { regions.wordAnchor }

        /// Which area of the plate `scenePoint` (scene coordinates) hits, if any.
        func region(at scenePoint: CGPoint) -> Region? {
            guard let scene = plate.scene else { return nil }
            let local = plate.convert(scenePoint, from: scene)
            if regions.wordBandRect.contains(local) { return .word }
            if regions.pictureRect.contains(local) { return .picture }
            return nil
        }
    }

    /// Icon side, from the height of the area it sits in — not the whole screen, which on a
    /// merged plate is much taller than the old picture plate.
    nonisolated static func iconSide(pictureAreaHeight: CGFloat) -> CGFloat {
        max(pictureAreaHeight * iconSideScale, 9)
    }

    /// Illustration over the word band, plus an icon-wide gutter on each side so the
    /// upper-right icon clears the centred content. `pictureSide == 0` means word only.
    nonisolated static func promptRegions(pictureSide: CGFloat, wordContent: CGSize) -> Regions {
        let picture = max(pictureSide, 0)
        let band = max(wordContent.height, 1)
        let gap = picture > 0 ? picture * pictureWordGapScale : 0
        let gutter = iconSide(pictureAreaHeight: picture > 0 ? picture : band)
        let content = CGSize(
            width: max(picture, max(wordContent.width, 1)) + gutter * 2,
            height: picture + gap + band
        )
        let plateSize = StarWarsConsoleChrome.plateSize(forPromptContent: content)
        let screen = StarWarsConsoleChrome.screenRect(for: plateSize)
        let bandRect = CGRect(
            x: screen.minX, y: screen.minY, width: screen.width, height: band
        )
        return Regions(
            plateSize: plateSize,
            wordBandRect: bandRect,
            pictureRect: CGRect(
                x: screen.minX,
                y: bandRect.maxY,
                width: screen.width,
                height: max(screen.height - band, 0)
            )
        )
    }

    nonisolated static func plateSize(pictureSide: CGFloat, wordContent: CGSize) -> CGSize {
        promptRegions(pictureSide: pictureSide, wordContent: wordContent).plateSize
    }

    /// One CRT plate: illustration top-middle, transparent band for the live word
    /// bottom-middle, play icon upper right.
    static func makePrompt(
        image: UIImage?,
        pictureSide: CGFloat,
        wordContent: CGSize,
        name: String
    ) -> Prompt {
        let side = image == nil ? 0 : max(pictureSide, 0)
        let regions = promptRegions(pictureSide: side, wordContent: wordContent)
        let plateSize = regions.plateSize
        let gap = side > 0 ? side * pictureWordGapScale : 0
        let plate = SKSpriteNode(
            texture: StarWarsConsolePromptView.makeTexture(
                image: image,
                wordBandFraction: regions.wordBandRect.height / plateSize.height,
                gapFraction: gap / plateSize.height,
                size: plateSize
            ),
            size: plateSize
        )
        plate.name = name
        plate.isUserInteractionEnabled = false
        attachPlayIcon(
            to: plate,
            areaHeight: side > 0 ? side : regions.wordBandRect.height
        )
        return Prompt(plate: plate, regions: regions)
    }

    /// Upper-right play affordance for any CRT plate sprite (prompt or word-plug).
    /// `areaHeight` is the region the icon is sized against — typically the picture
    /// band, or the full screen height when the plate is a single image + word row.
    static func attachPlayIcon(to plate: SKSpriteNode, areaHeight: CGFloat) {
        let side = iconSide(pictureAreaHeight: areaHeight)
        let screen = StarWarsConsoleChrome.screenRect(for: plate.size)
        let margin = min(screen.width, screen.height) * iconMarginScale
        let icon = MinigamePlaySoundIcon.makeNode(side: side, name: iconName)
        icon.position = CGPoint(
            x: screen.maxX - margin - side * 0.5
                + side * MinigamePlaySoundIcon.opticalXNudgeRatio,
            y: screen.maxY - margin - side * 0.5
        )
        icon.zPosition = 5
        plate.addChild(icon)
    }

    /// Pulses every icon at or under `node`, so a caller can hand over a whole prompt.
    static func pulseIcons(in node: SKNode, forTrackID trackID: String) {
        if let icon = node as? SKSpriteNode, icon.name == iconName {
            MinigamePlaySoundIcon.pulse(icon, forTrackID: trackID)
        }
        for child in node.children {
            pulseIcons(in: child, forTrackID: trackID)
        }
    }
}
