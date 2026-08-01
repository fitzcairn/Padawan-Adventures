import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct GateElectricityVariantsTests {
    @Test func connectorsBakeMultiplePathVariants() throws {
        let scene = GateScene(
            size: CGSize(width: 800, height: 600),
            puzzleConfig: .fallback
        )
        scene.addConnectorLineForTesting(
            from: CGPoint(x: 100, y: 200),
            to: CGPoint(x: 400, y: 200)
        )

        let before = scene.electricityVariantCounts
        #expect(before.count == 1)
        #expect(before[0].bolt > 1)
        #expect(before[0].branch > 1)

        scene.refreshElectricityConnectorsForTesting()
        #expect(scene.electricityVariantCounts.map(\.bolt) == before.map(\.bolt))
        #expect(scene.electricityVariantCounts.map(\.branch) == before.map(\.branch))
    }
}
