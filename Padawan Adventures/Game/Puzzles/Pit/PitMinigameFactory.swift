import SwiftUI

enum PitMinigameFactory {
    @MainActor @ViewBuilder
    static func makeView(
        config: PitMinigameConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) -> some View {
        switch config {
        case .spelling(let spelling):
            PitMinigameView(
                puzzleConfig: spelling,
                pitFx: pitFx,
                hudConfig: hudConfig,
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
                hudConfig: hudConfig,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig,
                onFinished: onFinished
            )
        }
    }
}
