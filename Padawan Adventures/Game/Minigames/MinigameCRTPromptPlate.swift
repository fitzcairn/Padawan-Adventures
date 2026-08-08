import SpriteKit
import UIKit

/// CRT console plates for the word prompt at the top of a minigame: one for the
/// illustration, one as a backdrop for the live word letters. Each carries a small
/// play icon in its upper right, because tapping the plate plays a sound.
@MainActor
enum MinigameCRTPromptPlate {
    static let iconName = "crtPlatePlayIcon"
    /// Icon side as a fraction of the CRT screen height — deliberately smaller than the
    /// capacitor / floor-tile play icons, which are the primary affordance.
    static let iconSideScale: CGFloat = 0.22
    static let iconMarginScale: CGFloat = 0.08
    /// How far the play icon sits to the right of the content, as a fraction of the CRT
    /// screen’s shorter side. Plate width grows by twice this (centre-anchored) so the
    /// upper-right slot moves by a full nudge while the icon stays inside the screen.
    static let iconXNudgeScale: CGFloat = 0.25

    /// Plate size for content, widened for the play-icon X nudge.
    static func plateSize(forContent content: CGSize) -> CGSize {
        var size = StarWarsConsoleChrome.plateSize(forContent: content)
        size.width += iconExtraWidth(for: size) * 2
        return size
    }

    static func makePicturePlate(
        image: UIImage,
        contentSide: CGFloat,
        name: String
    ) -> SKSpriteNode {
        let size = plateSize(
            forContent: CGSize(width: contentSide, height: contentSide)
        )
        let plate = SKSpriteNode(
            texture: StarWarsConsolePictureView.makeTexture(image: image, size: size),
            size: size
        )
        plate.name = name
        plate.isUserInteractionEnabled = false
        addIcon(to: plate)
        return plate
    }

    static func makeWordPlate(size: CGSize, name: String) -> SKSpriteNode {
        var size = size
        size.width += iconExtraWidth(for: size) * 2
        let plate = SKSpriteNode(
            texture: StarWarsConsoleScreenView.makeTexture(size: size),
            size: size
        )
        plate.name = name
        plate.isUserInteractionEnabled = false
        addIcon(to: plate)
        return plate
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

    private static func iconExtraWidth(for plateSize: CGSize) -> CGFloat {
        let screen = StarWarsConsoleChrome.screenRect(for: plateSize)
        return min(screen.width, screen.height) * iconXNudgeScale
    }

    private static func addIcon(to plate: SKSpriteNode) {
        let screen = StarWarsConsoleChrome.screenRect(for: plate.size)
        let side = max(screen.height * iconSideScale, 9)
        let margin = min(screen.width, screen.height) * iconMarginScale
        let icon = MinigamePlaySoundIcon.makeNode(side: side, name: iconName)
        // Upper-right of the widened plate; width growth is what shifts the icon right
        // relative to the centred word/picture content.
        icon.position = CGPoint(
            x: screen.maxX - margin - side * 0.5
                + side * MinigamePlaySoundIcon.opticalXNudgeRatio,
            y: screen.maxY - margin - side * 0.5
        )
        icon.zPosition = 5
        plate.addChild(icon)
    }
}
