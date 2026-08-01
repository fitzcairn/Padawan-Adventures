import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct PitBridgeGeometryTests {
    private func makeGeometry(
        width: CGFloat = 400,
        height: CGFloat = 300,
        padWidth: CGFloat = 80,
        padHeight: CGFloat = 60,
        slotCount: Int = 3
    ) -> PitBridgeGeometry {
        PitBridgeGeometry(
            sceneSize: CGSize(width: width, height: height),
            padSize: CGSize(width: padWidth, height: padHeight),
            slotCount: slotCount
        )
    }

    @Test func slotsAreEquallySpacedBetweenPads() {
        let geo = makeGeometry(slotCount: 3)
        #expect(geo.leftPadRect.maxX < geo.rightPadRect.minX)
        let centers = (0..<3).map { geo.slotCenter($0) }
        for center in centers {
            #expect(center.x > geo.leftPadRect.maxX)
            #expect(center.x < geo.rightPadRect.minX)
            #expect(abs(center.y - geo.leftPadRect.midY) < 0.001)
        }
        let gapBefore = centers[0].x - geo.leftPadRect.maxX
        let gapBetween = centers[1].x - centers[0].x
        let gapAfter = geo.rightPadRect.minX - centers[2].x
        #expect(abs(gapBefore - geo.slotSpacing) < 0.001)
        #expect(abs(gapBetween - geo.slotSpacing) < 0.001)
        #expect(abs(gapAfter - geo.slotSpacing) < 0.001)
    }

    @Test func trayCentersSitInBottomThirtyPercentBelowPads() {
        let geo = makeGeometry()
        for index in 0..<3 {
            let tray = geo.trayCenter(index)
            #expect(tray.y <= geo.sceneSize.height * 0.30 + 0.001)
            #expect(tray.y < geo.leftPadRect.minY)
        }
    }

    @Test func isDropAcceptsSlotCenterAndRejectsDistantPoint() {
        let geo = makeGeometry(slotCount: 2)
        let center = geo.slotCenter(0)
        #expect(geo.isDrop(center, onSlot: 0))
        let far = CGPoint(x: center.x + geo.tileSide * 2, y: center.y)
        #expect(!geo.isDrop(far, onSlot: 0))
    }
}
