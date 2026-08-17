import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct GateWordPlugTrayGeometryTests {
    private func geometry(
        count: Int,
        diameter: CGFloat,
        width: CGFloat,
        height: CGFloat = 800,
        inset: CGFloat = 10
    ) -> GateWordPlugTrayGeometry {
        GateWordPlugTrayGeometry(
            count: count,
            diameter: diameter,
            sceneSize: CGSize(width: width, height: height),
            leftInset: inset,
            rightInset: inset
        )
    }

    @Test func shortRowStaysOneLine() {
        let geo = geometry(count: 3, diameter: 40, width: 400)
        #expect(geo.rowCount == 1)
        let homes = geo.homes(bottomInset: 20, boardBottomY: 240)
        #expect(homes.count == 3)
        #expect(Set(homes.map(\.y)).count == 1)
        let radius = geo.radius
        for home in homes {
            #expect(home.x >= 10 + radius - 0.001)
            #expect(home.x <= 400 - 10 - radius + 0.001)
        }
    }

    @Test func overflowingRowWrapsToTwoCenteredRows() {
        let geo = geometry(count: 8, diameter: 50, width: 200, inset: 10)
        #expect(geo.rowCount == 2)
        #expect(geo.topRowCount == 4)
        #expect(geo.bottomRowCount == 4)
        let homes = geo.homes(bottomInset: 20, boardBottomY: 400)
        #expect(homes.count == 8)
        let rows = Dictionary(grouping: homes, by: { $0.y })
        #expect(rows.count == 2)
        let ys = rows.keys.sorted()
        #expect(rows[ys[1]]?.count == 4)
        #expect(rows[ys[0]]?.count == 4)
        #expect(ys[1] > ys[0])
    }

    @Test func fivePlugsPutTheExtraOnTheBottomRow() {
        let geo = geometry(count: 5, diameter: 60, width: 180, inset: 8)
        #expect(geo.rowCount == 2)
        #expect(geo.topRowCount == 2)
        #expect(geo.bottomRowCount == 3)
    }

    @Test func homesStayInsideHorizontalInsets() {
        let geo = geometry(count: 8, diameter: 48, width: 220, inset: 12)
        let homes = geo.homes(bottomInset: 16, boardBottomY: 300)
        let minX = 12 + geo.radius
        let maxX = 220 - 12 - geo.radius
        for home in homes {
            #expect(home.x >= minX - 0.001)
            #expect(home.x <= maxX + 0.001)
        }
    }

    @Test func fittedDiameterShrinksUntilTwoRowsFit() {
        let diameter = GateWordPlugTrayGeometry.fittedDiameter(
            count: 8,
            boardDiameter: 80,
            sceneSize: CGSize(width: 220, height: 800),
            leftInset: 10,
            rightInset: 10,
            bottomInset: 0,
            boardBottomY: 200
        )
        #expect(diameter <= 80)
        let geo = GateWordPlugTrayGeometry(
            count: 8,
            diameter: diameter,
            sceneSize: CGSize(width: 220, height: 800),
            leftInset: 10,
            rightInset: 10
        )
        #expect(geo.fitsHorizontally())
        #expect(geo.fitsVertically(boardBottomY: 200, bottomInset: 0))
    }

    @Test func fittedDiameterAccountsForBottomInset() {
        let sceneSize = CGSize(width: 400, height: 800)
        let unconstrained = GateWordPlugTrayGeometry.fittedDiameter(
            count: 4,
            boardDiameter: 80,
            sceneSize: sceneSize,
            leftInset: 10,
            rightInset: 10,
            bottomInset: 0,
            boardBottomY: 160
        )
        let constrained = GateWordPlugTrayGeometry.fittedDiameter(
            count: 4,
            boardDiameter: 80,
            sceneSize: sceneSize,
            leftInset: 10,
            rightInset: 10,
            bottomInset: 90,
            boardBottomY: 160
        )
        #expect(constrained <= unconstrained)
        let geo = GateWordPlugTrayGeometry(
            count: 4,
            diameter: constrained,
            sceneSize: sceneSize,
            leftInset: 10,
            rightInset: 10
        )
        #expect(geo.fitsVertically(boardBottomY: 160, bottomInset: 90))
    }
}
