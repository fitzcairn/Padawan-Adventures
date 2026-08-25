import SpriteKit

extension GameScene {
    static let bridgeFadeDuration: TimeInterval = 0.6

    /// Fills a nearby pit blob and cross-fades pit art into ordinary floor.
    func useBridge(_ result: BridgePitUse.Result) {
        isPausedForEncounter = true
        pendingInput = PendingInput()
        movement.reset()
        SoundEffectsController.shared.play(event: "bridge", from: playerFx)

        let coords = BridgePitUse.fadeCoords(for: result, in: world)
        let outgoing = renderer.takeFloorNodes(at: coords)
        _ = world.fillPit(at: result.seed)
        renderer.render(world: world, focus: viewportFocus)
        let incoming = coords.compactMap { renderer.floorNodes[$0] }
        for node in incoming {
            node.alpha = 0
            node.run(.fadeIn(withDuration: Self.bridgeFadeDuration))
        }
        for node in outgoing {
            node.run(.sequence([
                .fadeOut(withDuration: Self.bridgeFadeDuration),
                .removeFromParent(),
            ]))
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.bridgeFadeDuration * 1_000_000_000))
            guard let self else { return }
            self.captureContinueAndSave()
            self.isPausedForEncounter = false
        }
    }
}
