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

    static func makePicturePlate(
        image: UIImage,
        contentSide: CGFloat,
        name: String
    ) -> SKSpriteNode {
        let size = StarWarsConsoleChrome.plateSize(
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

    private static func addIcon(to plate: SKSpriteNode) {
        let screen = StarWarsConsoleChrome.screenRect(for: plate.size)
        let side = max(screen.height * iconSideScale, 9)
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
}
