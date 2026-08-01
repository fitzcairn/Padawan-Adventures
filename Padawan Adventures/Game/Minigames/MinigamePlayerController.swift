import Foundation

/// Shared player-sprite warm-up for pit minigames that animate the padawan.
enum MinigamePlayerController {
    static func preparePlayerSprites(
        in library: SpriteLibrary,
        config: SpriteConfig?
    ) async {
        guard let config else { return }
        let missingNewClip =
            library.animation(id: "player", named: "jump_right") == nil
            || library.animation(id: "player", named: "celebrate_down") == nil
        if missingNewClip,
           library.animation(id: "player", named: "idle_right") != nil {
            library.invalidate(id: "player")
        }
        await library.ensureLoaded(config, id: "player")
    }
}
