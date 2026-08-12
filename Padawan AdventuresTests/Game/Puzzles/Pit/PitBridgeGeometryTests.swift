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
        let padMidY = geo.sceneSize.height * 0.5 * (1 - PitBridgeGeometry.bridgeLineDownShift)
        let expectedBridgeY = padMidY * (1 - PitBridgeGeometry.bridgeContentDownShift)
        for center in centers {
            #expect(center.x > geo.leftPadRect.maxX)
            #expect(center.x < geo.rightPadRect.minX)
            #expect(abs(center.y - geo.bridgeLineY) < 0.001)
            #expect(abs(center.y - expectedBridgeY) < 0.001)
            #expect(center.y < geo.leftPadRect.midY)
        }
        #expect(abs(geo.leftPadRect.midY - padMidY) < 0.001)
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

    @Test func trayRestsOnSwipeRowInsetBelowPads() {
        let geo = makeGeometry()
        let expectedY = ScreenLayout.bottomRowCenterY(
            rowHeight: geo.tileSide,
            bottomInset: ScreenLayout.swipeRowBottomInset(
                sceneHeight: geo.sceneSize.height,
                chromeBottom: geo.sceneSize.height * ScreenLayout.edgeInsetFraction
            ),
            ceiling: geo.leftPadRect.minY - geo.tileSide * 0.6
        )
        for index in 0..<3 {
            #expect(abs(geo.trayCenter(index).y - expectedY) < 0.001)
        }
        #expect(expectedY - geo.tileSide * 0.5 > geo.sceneSize.height * ScreenLayout.edgeInsetFraction)
    }

    @Test func isDropAcceptsSlotCenterAndRejectsDistantPoint() {
        let geo = makeGeometry(slotCount: 2)
        let center = geo.slotCenter(0)
        #expect(geo.isDrop(center, onSlot: 0))
        let far = CGPoint(x: center.x + geo.tileSide * 2, y: center.y)
        #expect(!geo.isDrop(far, onSlot: 0))
    }

    @Test func isDropAcceptsNearMissOutsideDashedBox() {
        let geo = makeGeometry(slotCount: 2)
        let center = geo.slotCenter(0)
        // Dashed box half-diagonal is ~0.71 * tileSide; a point just past a box
        // edge should still count with the assisted radius.
        let nearMiss = CGPoint(x: center.x + geo.tileSide * 0.95, y: center.y)
        #expect(geo.isDrop(nearMiss, onSlot: 0))
        #expect(geo.distance(from: nearMiss, toSlot: 0) > geo.tileSide * 0.5)
    }

    @Test func assistedDropRequiresApproachingTheSlot() {
        let geo = makeGeometry(slotCount: 3)
        let slot = geo.slotCenter(0)
        let tray = geo.trayCenter(0)

        // Resting on the tray — even if that happens to sit inside the generous
        // radius — is a tap, not an assisted drop.
        #expect(!geo.isDrop(tray, onSlot: 0, fromHome: tray))

        // A near-miss that got closer than home does assist.
        let nearMiss = CGPoint(x: slot.x + geo.tileSide * 0.95, y: slot.y)
        #expect(geo.isDrop(nearMiss, onSlot: 0, fromHome: tray))

        // Dragging away from the slot, still inside the radius, does not assist.
        let homeInRadius = CGPoint(x: slot.x + geo.tileSide * 0.4, y: slot.y)
        let fartherInRadius = CGPoint(x: slot.x + geo.tileSide * 0.9, y: slot.y)
        #expect(geo.isDrop(homeInRadius, onSlot: 0))
        #expect(geo.isDrop(fartherInRadius, onSlot: 0))
        #expect(!geo.isDrop(fartherInRadius, onSlot: 0, fromHome: homeInRadius))

        // Getting closer while already in the radius does assist.
        #expect(geo.isDrop(homeInRadius, onSlot: 0, fromHome: fartherInRadius))
    }

    @Test func trayRestDoesNotCountAsAssistedDropOntoAnySlot() {
        let geo = makeGeometry(slotCount: 3)
        for trayIndex in 0..<3 {
            let home = geo.trayCenter(trayIndex)
            for slotIndex in 0..<3 {
                #expect(!geo.isDrop(home, onSlot: slotIndex, fromHome: home))
            }
        }
    }
}
