import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct CombatWrongSlashMotionTests {
    @Test func discardWrongShotHalvesRemainingInboundFlight() throws {
        let scene = try makeCombatScene()
        let decoyID = UUID()
        let targetID = UUID()
        let start = CGPoint(x: 200, y: 280)
        let end = CGPoint(x: 200, y: 40)
        let control1 = CGPoint(x: 80, y: 200)
        let control2 = CGPoint(x: 320, y: 120)
        scene.sceneElapsed = 4
        scene.shotVisuals[decoyID] = makeInboundVisual(
            letter: "b",
            isTarget: false,
            start: start,
            control1: control1,
            control2: control2,
            end: end,
            startedAt: 0,
            duration: 8
        )
        scene.shotVisuals[targetID] = makeInboundVisual(
            letter: "s",
            isTarget: true,
            start: start,
            control1: control1,
            control2: control2,
            end: end,
            startedAt: 0,
            duration: 8
        )
        for visual in scene.shotVisuals.values {
            scene.addChild(visual.node)
        }

        let progressBefore = scene.pathProgress(for: scene.shotVisuals[targetID]!)
        #expect(abs(progressBefore - 0.5) < 0.0001)
        let arcBefore = CombatShotMotion.inboundArcFraction(progress: Double(progressBefore), arcStart: 0)

        scene.discardWrongShot(shotID: decoyID)

        #expect(scene.shotVisuals[decoyID] == nil)
        let survivor = try #require(scene.shotVisuals[targetID])
        #expect(survivor.role == .inbound)
        #expect(survivor.pathStart == start)
        #expect(survivor.pathControl1 == control1)
        #expect(survivor.pathControl2 == control2)
        #expect(survivor.pathEnd == end)
        let remainingBefore = 8 * (1 - Double(progressBefore))
        #expect(
            abs(
                survivor.pathDurationSeconds
                    - remainingBefore / CombatScene.wrongSlashSpeedMultiplier
            ) < 0.0001
        )
        #expect(abs(survivor.pathArcStart - arcBefore) < 0.0001)
        #expect(scene.pathProgress(for: survivor) == 0)
        #expect(
            abs(
                CombatShotMotion.inboundArcFraction(
                    progress: 0, arcStart: survivor.pathArcStart
                ) - arcBefore
            ) < 0.0001
        )
    }

    private func makeCombatScene() throws -> CombatScene {
        let enemies = try EnemyConfig.loadFromBundle()
        let enemyType = try #require(enemies.enemies.values.first)
        let spriteID = try #require(enemyType.sprite)
        let enemySpriteConfig = try #require(enemies.sprites[spriteID])
        return CombatScene(
            size: CGSize(width: 400, height: 300),
            enemyType: enemyType,
            playerFx: .empty,
            startingHealth: 3,
            spriteLibrary: SpriteLibrary(),
            letterSpriteSetLibrary: LetterSpriteSetLibrary(),
            combatSprite: nil,
            enemySprite: (spriteID, enemySpriteConfig),
            wallHeight: 80
        )
    }

    private func makeInboundVisual(
        letter: String,
        isTarget: Bool,
        start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        end: CGPoint,
        startedAt: Double,
        duration: Double
    ) -> CombatScene.ShotVisual {
        CombatScene.ShotVisual(
            pathStart: start,
            pathControl1: control1,
            pathControl2: control2,
            pathEnd: end,
            pathStartedAt: startedAt,
            pathDurationSeconds: duration,
            scaleStartedAt: startedAt,
            scaleDurationSeconds: duration,
            pathLength: CombatShotMotion.cubicBezierArcLength(
                start: start, c1: control1, c2: control2, end: end
            ),
            letter: letter,
            isTarget: isTarget,
            role: .inbound,
            node: SKNode()
        )
    }
}
