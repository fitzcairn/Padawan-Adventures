import SpriteKit
import UIKit

extension PlaceholderFactory {
    /// Descriptor for a 2-tile gate used when interleaving entity/gate draw order.
    struct GateOccluder: Equatable, Sendable {
        var axis: GateSpriteSet.Axis
        var cell: GridCoord
        var partner: GridCoord
        var sortCoord: GridCoord
    }

    /// Canonical gate strips in `world` on `story` (one entry per sprite, not per cell).
    static func gateOccluders(in world: GameWorld, story: Int) -> [GateOccluder] {
        var result: [GateOccluder] = []
        var seen = Set<GridCoord>()
        guard story >= 0, story < world.storyCount else { return result }
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard case .gate(let minigame) = world.tile(at: coord)?.kind else { continue }
                guard let strip = gateStrip(at: coord, minigame: minigame, in: world) else { continue }
                guard strip.isCanonical else { continue }
                guard seen.insert(coord).inserted else { continue }
                seen.insert(strip.partner)
                let sortCoord = (coord.x + coord.y) >= (strip.partner.x + strip.partner.y)
                    ? coord : strip.partner
                result.append(
                    GateOccluder(
                        axis: strip.axis,
                        cell: coord,
                        partner: strip.partner,
                        sortCoord: sortCoord
                    )
                )
            }
        }
        return result
    }

    /// Tiles of slack beyond the 2-cell strip where gate art can still overlap a sprite.
    static let gateSpanPadding: Double = 1

    /// True when the entity is close enough along the strip axis for the gate art to
    /// overlap it on screen.
    ///
    /// The near/far side tests below are half-planes, so without this bound a gate would
    /// reorder every sprite sharing its row or column — including sprites far away that
    /// the art cannot touch. Outside the span, plain depth sorting is correct.
    static func entityOverlapsGateSpan(
        entityX: Double,
        entityY: Double,
        gate: GateOccluder
    ) -> Bool {
        switch gate.axis {
        case .alongX:
            let low = Double(min(gate.cell.x, gate.partner.x)) - gateSpanPadding
            let high = Double(max(gate.cell.x, gate.partner.x)) + gateSpanPadding
            return entityX >= low && entityX <= high
        case .alongY:
            let low = Double(min(gate.cell.y, gate.partner.y)) - gateSpanPadding
            let high = Double(max(gate.cell.y, gate.partner.y)) + gateSpanPadding
            return entityY >= low && entityY <= high
        }
    }

    /// True when the entity is on the camera-near side of the gate (should draw above it).
    ///
    /// Gates are thin walls: `alongX` separates rooms in Y (near = higher Y), `alongY`
    /// separates rooms in X (near = higher X). Standing on the gate line is neither.
    static func entityIsInFrontOfGate(
        entityX: Double,
        entityY: Double,
        axis: GateSpriteSet.Axis,
        cell: GridCoord
    ) -> Bool {
        switch axis {
        case .alongX:
            return entityY > Double(cell.y)
        case .alongY:
            return entityX > Double(cell.x)
        }
    }

    /// True when the entity is on the camera-far side of the gate (gate should draw above).
    static func entityIsBehindGate(
        entityX: Double,
        entityY: Double,
        axis: GateSpriteSet.Axis,
        cell: GridCoord
    ) -> Bool {
        switch axis {
        case .alongX:
            return entityY < Double(cell.y)
        case .alongY:
            return entityX < Double(cell.x)
        }
    }

    /// Entity sort z adjusted so near-side poses beat the gate and far-side poses lose to it.
    ///
    /// Used for players, enemies, and pickup items alike — any sprite that shares the
    /// occlusion layer with gate art.
    static func entitySortValueAccountingForGates(
        x: Double,
        y: Double,
        story: Int,
        gates: [GateOccluder],
        config: IsometricConfig
    ) -> CGFloat {
        var z = IsometricMath.entitySortValue(x: x, y: y, story: story, config: config)
        guard !gates.isEmpty else { return z }

        var aboveFloor = -CGFloat.greatestFiniteMagnitude
        var belowCap = CGFloat.greatestFiniteMagnitude
        for gate in gates {
            guard entityOverlapsGateSpan(entityX: x, entityY: y, gate: gate) else { continue }
            let gateZ = IsometricMath.wallSortValue(for: gate.sortCoord, config: config)
            if entityIsInFrontOfGate(entityX: x, entityY: y, axis: gate.axis, cell: gate.cell) {
                aboveFloor = max(aboveFloor, gateZ + 0.5)
            } else if entityIsBehindGate(entityX: x, entityY: y, axis: gate.axis, cell: gate.cell) {
                belowCap = min(belowCap, gateZ - 0.5)
            }
        }
        if aboveFloor > -CGFloat.greatestFiniteMagnitude {
            z = max(z, aboveFloor)
        }
        if belowCap < CGFloat.greatestFiniteMagnitude {
            // Prefer staying visible when near one gate and far from another.
            if aboveFloor > belowCap {
                z = aboveFloor
            } else {
                z = min(z, belowCap)
            }
        }
        return z
    }
}
