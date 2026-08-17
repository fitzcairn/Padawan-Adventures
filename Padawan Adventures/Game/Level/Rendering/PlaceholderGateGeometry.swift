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

    /// Occluder for the 2-tile gate strip containing `coord`, keyed to the strip's
    /// canonical cell so both cells of a strip describe the same sprite.
    static func gateOccluder(at coord: GridCoord, in world: GameWorld) -> GateOccluder? {
        guard case .gate(let minigame) = world.tile(at: coord)?.kind,
              let strip = gateStrip(at: coord, minigame: minigame, in: world) else { return nil }
        let cell = strip.isCanonical ? coord : strip.partner
        let partner = strip.isCanonical ? strip.partner : coord
        return GateOccluder(
            axis: strip.axis,
            cell: cell,
            partner: partner,
            sortCoord: (cell.x + cell.y) >= (partner.x + partner.y) ? cell : partner
        )
    }

    /// Canonical gate strips in `world` on `story` (one entry per sprite, not per cell).
    static func gateOccluders(in world: GameWorld, story: Int) -> [GateOccluder] {
        var result: [GateOccluder] = []
        var seen = Set<GridCoord>()
        guard story >= 0, story < world.storyCount else { return result }
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard let occluder = gateOccluder(at: coord, in: world) else { continue }
                guard occluder.cell == coord else { continue }
                guard seen.insert(occluder.cell).inserted else { continue }
                seen.insert(occluder.partner)
                result.append(occluder)
            }
        }
        return result
    }

    /// Tiles of slack beyond the 2-cell strip for the *behind* cap only.
    ///
    /// Camera-front bumps do not use this box — `max(z, gateZ + bias)` is safe map-wide
    /// (poses that already beat the gate keep their natural z). The behind cap must stay
    /// local: without a bound it would bury every sprite sharing a lower depth line.
    static let gateSpanPadding: Double = 2

    /// Extra z so a camera-front / on-strip sprite beats the gate in SpriteKit's depth
    /// buffer. Must stay below one Y-stride (10_000) so it cannot leap a whole extra row
    /// of walls, and well above nested face/body biases (~0.03) and float32 ULP at the
    /// occlusion band.
    static let gateOcclusionZBias: CGFloat = 1_000

    /// Camera depth (`x + y`) of the strip's far corner — the back cell of the doorway.
    static func gateBackDepth(for gate: GateOccluder) -> Double {
        Double(min(gate.cell.x + gate.cell.y, gate.partner.x + gate.partner.y))
    }

    /// True when the pose sits on the strip's two cells (including fractional mid-move).
    static func entityIsOnGateStrip(
        entityX: Double,
        entityY: Double,
        gate: GateOccluder
    ) -> Bool {
        let minX = Double(min(gate.cell.x, gate.partner.x))
        let maxX = Double(max(gate.cell.x, gate.partner.x))
        let minY = Double(min(gate.cell.y, gate.partner.y))
        let maxY = Double(max(gate.cell.y, gate.partner.y))
        return entityX >= minX && entityX <= maxX && entityY >= minY && entityY <= maxY
    }

    /// True when a camera-behind entity is close enough that the gate art can cover it.
    ///
    /// Bounds both axes around the 2-cell strip. Used only for the behind cap — front
    /// bumps ignore this so lateral overhang past the old pad box still lifts the sprite.
    static func entityOverlapsGateSpan(
        entityX: Double,
        entityY: Double,
        gate: GateOccluder
    ) -> Bool {
        let minX = Double(min(gate.cell.x, gate.partner.x)) - gateSpanPadding
        let maxX = Double(max(gate.cell.x, gate.partner.x)) + gateSpanPadding
        let minY = Double(min(gate.cell.y, gate.partner.y)) - gateSpanPadding
        let maxY = Double(max(gate.cell.y, gate.partner.y)) + gateSpanPadding
        return entityX >= minX && entityX <= maxX && entityY >= minY && entityY <= maxY
    }

    /// True when the entity is on the camera-near side of the gate (should draw above it).
    ///
    /// Camera-near means higher `x + y` (bottom of the screen) or standing on the strip.
    /// The cobblestone lip is the south tip of the front cell; a player on the next tile
    /// south has feet on that lip, and Y-sort already puts them a full row above the gate.
    static func entityIsInFrontOfGate(
        entityX: Double,
        entityY: Double,
        gate: GateOccluder
    ) -> Bool {
        if entityIsOnGateStrip(entityX: entityX, entityY: entityY, gate: gate) {
            return true
        }
        return entityX + entityY > gateBackDepth(for: gate)
    }

    /// True when the entity is strictly camera-behind the gate (gate should draw above).
    static func entityIsBehindGate(
        entityX: Double,
        entityY: Double,
        gate: GateOccluder
    ) -> Bool {
        if entityIsInFrontOfGate(entityX: entityX, entityY: entityY, gate: gate) {
            return false
        }
        return entityX + entityY < gateBackDepth(for: gate)
    }

    /// Entity sort z adjusted so camera-near poses beat the gate and nearby camera-far
    /// poses lose to it.
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
            let gateZ = IsometricMath.wallSortValue(for: gate.sortCoord, config: config)
            // Front bump is map-wide: gate art overhangs several tiles past the strip, and
            // max() is a no-op when natural z already clears the gate.
            if entityIsInFrontOfGate(entityX: x, entityY: y, gate: gate) {
                aboveFloor = max(aboveFloor, gateZ + gateOcclusionZBias)
            } else if entityIsBehindGate(entityX: x, entityY: y, gate: gate),
                      entityOverlapsGateSpan(entityX: x, entityY: y, gate: gate) {
                belowCap = min(belowCap, gateZ - gateOcclusionZBias)
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
