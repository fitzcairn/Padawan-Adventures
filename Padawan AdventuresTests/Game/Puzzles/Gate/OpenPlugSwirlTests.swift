import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct OpenPlugSwirlTests {
    @Test func attachAddsOppositeGoldEmittersOnALoopingOrbit() throws {
        let parent = SKNode()
        OpenPlugSwirl.attach(to: parent, radius: 24, referenceHeight: 48)

        let node = try #require(parent.childNode(withName: OpenPlugSwirl.nodeName))
        #expect(node.action(forKey: OpenPlugSwirl.motionKey) != nil)
        #expect(node.isUserInteractionEnabled == false)

        let gold = try #require(node.childNode(withName: OpenPlugSwirl.goldEmitterName) as? SKEmitterNode)
        let hot = try #require(node.childNode(withName: OpenPlugSwirl.goldHotEmitterName) as? SKEmitterNode)
        #expect(gold.particleBlendMode == .add)
        #expect(hot.particleBlendMode == .add)
        #expect(gold.particleColorBlendFactor == 1)
        #expect(hot.particleColorBlendFactor == 1)
        #expect(gold.particleBirthRate == OpenPlugSwirl.birthRate)
        #expect(hot.particleBirthRate == OpenPlugSwirl.birthRate)
        #expect(colorsMatch(gold.particleColor, OpenPlugSwirl.gold))
        #expect(colorsMatch(hot.particleColor, OpenPlugSwirl.goldHot))
        #expect(gold.position == CGPoint(x: 24, y: 0))
        #expect(hot.position == CGPoint(x: -24, y: 0))
        #expect(gold.targetNode === node)
        #expect(hot.targetNode === node)
    }

    @Test func attachReplacesAnExistingSwirl() {
        let parent = SKNode()
        OpenPlugSwirl.attach(to: parent, radius: 10, referenceHeight: 20)
        OpenPlugSwirl.attach(to: parent, radius: 16, referenceHeight: 32)
        let swirls = parent.children.filter { $0.name == OpenPlugSwirl.nodeName }
        #expect(swirls.count == 1)
        let gold = swirls[0].childNode(withName: OpenPlugSwirl.goldEmitterName)
        #expect(gold?.position == CGPoint(x: 16, y: 0))
    }

    @Test func detachStopsSpawningAndSchedulesRemoval() throws {
        let parent = SKNode()
        OpenPlugSwirl.attach(to: parent, radius: 12, referenceHeight: 24)
        OpenPlugSwirl.detach(from: parent)

        let node = try #require(parent.childNode(withName: OpenPlugSwirl.nodeName))
        #expect(node.action(forKey: OpenPlugSwirl.motionKey) == nil)
        #expect(parent.action(forKey: OpenPlugSwirl.cleanupKey) != nil)
        for case let emitter as SKEmitterNode in node.children {
            #expect(emitter.particleBirthRate == 0)
        }
    }
}

@MainActor
struct GateWordPlugOpenSwirlTests {
    @Test func tapDoesNotShowSwirls() throws {
        let scene = makeScene()
        let tokenID = try #require(scene.engine.tray.first?.id)
        scene.beginTokenDragForTesting(id: tokenID)
        #expect(!scene.openPlugSwirlsActive)
        #expect(swirlCount(in: scene) == 0)
        scene.endDrag()
        #expect(!scene.openPlugSwirlsActive)
    }

    @Test func draggingHighlightsEveryEmptySocket() throws {
        let scene = makeScene()
        let tokenID = try #require(scene.engine.tray.first?.id)
        let home = try #require(scene.tokenHome[tokenID])
        scene.beginTokenDragForTesting(id: tokenID)
        scene.updateTokenDrag(to: CGPoint(x: home.x + scene.tapMoveThreshold + 4, y: home.y))

        #expect(scene.dragMoved)
        #expect(scene.openPlugSwirlsActive)
        #expect(swirlCount(in: scene) == scene.socketNodes.count)
        for socket in scene.socketNodes.values {
            #expect(socket.childNode(withName: OpenPlugSwirl.nodeName) != nil)
        }

        scene.endDrag()
        #expect(!scene.openPlugSwirlsActive)
        for socket in scene.socketNodes.values {
            let swirl = socket.childNode(withName: OpenPlugSwirl.nodeName)
            #expect(swirl != nil)
            for case let emitter as SKEmitterNode in swirl?.children ?? [] {
                #expect(emitter.particleBirthRate == 0)
            }
        }
    }

    @Test func filledSocketsAreSkipped() throws {
        let scene = makeScene()
        let slot = try #require(scene.engine.slots.first)
        let token = try #require(scene.engine.tray.first { $0.letter == slot.letter })
        _ = scene.engine.plug(letterID: token.id, intoSlotID: slot.id)

        scene.startOpenPlugSwirls()
        #expect(scene.socketNodes[slot.id]?.childNode(withName: OpenPlugSwirl.nodeName) == nil)
        let emptyCount = scene.socketNodes.keys.filter { !scene.engine.isSlotFilled($0) }.count
        #expect(swirlCount(in: scene) == emptyCount)
        #expect(emptyCount >= 1)
    }

    @Test func endingSoundGateUsesTheSameOpenSocketSwirls() throws {
        let scene = makeScene(letterPosition: .ending)
        #expect(scene.puzzleConfig.letterPosition == .ending)
        let tokenID = try #require(scene.engine.tray.first?.id)
        let home = try #require(scene.tokenHome[tokenID])
        scene.beginTokenDragForTesting(id: tokenID)
        scene.updateTokenDrag(to: CGPoint(x: home.x, y: home.y + scene.tapMoveThreshold + 4))
        #expect(scene.openPlugSwirlsActive)
        #expect(swirlCount(in: scene) == scene.socketNodes.count)
        scene.endDrag()
        #expect(!scene.openPlugSwirlsActive)
    }

    private func makeScene(
        letterPosition: GateWordPlugLetterPosition = .starting
    ) -> GateWordPlugScene {
        let scene = GateWordPlugScene(
            size: CGSize(width: 800, height: 600),
            puzzleConfig: GateWordPlugConfig(
                wordCountMin: 2,
                wordCountMax: 3,
                letterPosition: letterPosition,
                words: WordCatalog.fallback.words,
                graphemes: GraphemeCatalog.fallback.graphemes
            ),
            playerFx: .empty
        )
        scene.buildContentForTesting()
        return scene
    }

    private func swirlCount(in scene: GateWordPlugScene) -> Int {
        scene.socketNodes.values.filter { $0.childNode(withName: OpenPlugSwirl.nodeName) != nil }.count
    }
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
