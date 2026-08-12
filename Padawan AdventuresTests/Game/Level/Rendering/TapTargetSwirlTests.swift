import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct TapTargetSwirlTests {
    @Test func durationAndRiseMatchSpec() {
        #expect(TapTargetSwirl.duration == 1.0)
        #expect(TapTargetSwirl.riseHeightFraction == 0.2)
        #expect(TapTargetSwirl.zProgressFraction == 0.2)
        #expect(TapTargetSwirl.riseDistance(playerSpriteHeight: 100) == 20)
        #expect(TapTargetSwirl.startRadiusScale == 0.5)
        #expect(TapTargetSwirl.endRadiusScale == 0.9)
        #expect(TapTargetSwirl.orbitScale(progress: 0) == 0.5)
        #expect(abs(TapTargetSwirl.orbitScale(progress: 1) - 0.9) < 0.000_1)
    }

    @Test func zPositionStartsOnFloorAndRisesTwentyPercentTowardPlayer() {
        let coord = GridCoord(x: 3, y: 4, story: 0)
        let config = IsometricConfig()
        let floorZ = IsometricMath.effectiveFloorZ(for: coord, config: config)
        let playerZ = IsometricMath.effectiveEntityZ(for: coord, config: config)
        let startZ = floorZ + TapTargetSwirl.floorOverlayZ

        #expect(startZ > floorZ)
        #expect(startZ < playerZ)

        let endZ = TapTargetSwirl.zPosition(
            startZ: startZ,
            playerZ: playerZ,
            progress: TapTargetSwirl.zProgressFraction
        )
        let expected = startZ + 0.2 * (playerZ - startZ)
        #expect(abs(endZ - expected) < 0.001)
        #expect(endZ > startZ)
        #expect(endZ < playerZ)
    }

    @Test func playAddsGreenAndBlueEmittersOnTopOfFloor() throws {
        let parent = SKNode()
        let startZ: CGFloat = 12
        let playerZ: CGFloat = 1_000_000_012
        TapTargetSwirl.play(
            in: parent,
            at: CGPoint(x: 8, y: -4),
            startZ: startZ,
            playerZ: playerZ,
            tileWidth: 40,
            tileHeight: 40,
            playerSpriteHeight: 80
        )

        let node = try #require(parent.childNode(withName: TapTargetSwirl.nodeName))
        #expect(node.position == CGPoint(x: 8, y: -4))
        #expect(node.zPosition == startZ)
        #expect(node.action(forKey: TapTargetSwirl.nodeName) != nil)

        let green = try #require(node.childNode(withName: "tapTargetGreen") as? SKEmitterNode)
        let blue = try #require(node.childNode(withName: "tapTargetBlue") as? SKEmitterNode)
        #expect(green.particleBlendMode == .add)
        #expect(blue.particleBlendMode == .add)
        #expect(green.particleColorBlendFactor == 1)
        #expect(blue.particleColorBlendFactor == 1)
        #expect(green.particleBirthRate == TapTargetSwirl.birthRate)
        #expect(blue.particleBirthRate == TapTargetSwirl.birthRate)
        #expect(colorsMatch(green.particleColor, TapTargetSwirl.green))
        #expect(colorsMatch(blue.particleColor, TapTargetSwirl.blue))
    }

    @Test func rendererPlaysSwirlAtTileCenterAboveFloorArt() throws {
        let world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let renderer = IsometricRenderer()
        let scene = SKScene(size: CGSize(width: 320, height: 480))
        renderer.attach(to: scene)
        renderer.render(world: world, focus: .zero)

        let coord = GridCoord(x: 2, y: 3, story: 0)
        renderer.playTapTarget(at: coord)

        let swirl = try #require(renderer.worldRoot.childNode(withName: TapTargetSwirl.nodeName))
        let expected = IsometricMath.entityScreenPosition(coord, config: renderer.config)
        #expect(abs(swirl.position.x - expected.x) < 0.001)
        #expect(abs(swirl.position.y - expected.y) < 0.001)

        let floorZ = IsometricMath.effectiveFloorZ(for: coord, config: renderer.config)
        let expectedZ = floorZ + TapTargetSwirl.floorOverlayZ
        #expect(abs(swirl.zPosition - expectedZ) < 0.01)
        #expect(swirl.zPosition > floorZ)
    }

    @Test func playerDisplayHeightUsesSpriteConfigThenPlaceholder() {
        let iso = IsometricConfig(tileWidth: 40, tileHeight: 40, wallHeight: 80)
        let sprite = SpriteConfig(root: "Sprites/Player", scale: 1.2)
        let fromSprite = PlaceholderFactory.playerDisplayHeight(isoConfig: iso, spriteConfig: sprite)
        #expect(abs(fromSprite - 115.2) < 0.001)

        let placeholder = PlaceholderFactory.playerDisplayHeight(isoConfig: iso, spriteConfig: nil)
        #expect(abs(placeholder - 88) < 0.001) // 40 * 2.2
    }

    private func colorsMatch(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return abs(lr - rr) < 0.01
            && abs(lg - rg) < 0.01
            && abs(lb - rb) < 0.01
            && abs(la - ra) < 0.01
    }
}
