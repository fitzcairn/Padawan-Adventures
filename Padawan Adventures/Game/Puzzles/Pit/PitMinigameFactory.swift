import SwiftUI

enum PitMinigameFactory {
    @MainActor @ViewBuilder
    static func makeView(
        config: PitMinigameConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        hudConfig _: HudConfig,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) -> some View {
        // HUD lives in the scene prompt for sound-out-word; keep the param for callers.
        switch config {
        case .soundOutWord(let soundOut):
            PitSoundOutWordMinigameView(
                soundOutConfig: soundOut,
                pitFx: pitFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig,
                onFinished: onFinished
            )
        case .bridge(let bridge):
            PitBridgeMinigameView(
                bridgeConfig: bridge,
                pitFx: pitFx,
                playerFx: playerFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig,
                onFinished: onFinished
            )
        }
    }

    @MainActor @ViewBuilder
    static func makeDemoView(
        config: PitMinigameConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        hudConfig _: HudConfig,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        leadInSeconds: TimeInterval
    ) -> some View {
        switch config {
        case .soundOutWord(let soundOut):
            MinigameDemoView(
                prepare: {
                    await MinigamePlayerController.preparePlayerSprites(
                        in: spriteLibrary, config: playerSpriteConfig
                    )
                },
                make: { size in
                    PitSoundOutWordScene(
                        size: size,
                        soundOutConfig: soundOut,
                        pitFx: pitFx,
                        floorTileSetLibrary: floorTileSetLibrary,
                        isoConfig: isoConfig,
                        spriteLibrary: spriteLibrary,
                        playerSpriteConfig: playerSpriteConfig
                    )
                },
                leadInSeconds: leadInSeconds
            )
        case .bridge(let bridge):
            MinigameDemoView(
                prepare: {
                    await MinigamePlayerController.preparePlayerSprites(
                        in: spriteLibrary, config: playerSpriteConfig
                    )
                },
                make: { size in
                    PitBridgeScene(
                        size: size,
                        bridgeConfig: bridge,
                        pitFx: pitFx,
                        playerFx: playerFx,
                        floorTileSetLibrary: floorTileSetLibrary,
                        isoConfig: isoConfig,
                        spriteLibrary: spriteLibrary,
                        playerSpriteConfig: playerSpriteConfig
                    )
                },
                leadInSeconds: leadInSeconds
            )
        }
    }
}
