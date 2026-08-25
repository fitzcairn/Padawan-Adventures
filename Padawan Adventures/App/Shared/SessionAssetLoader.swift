import Foundation
import SpriteKit
import UIKit

extension AppSession {
    /// Ensures player sprite animations are loaded for this session.
    func ensurePlayerSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        if let sprite = playerConfig.sprite {
            await spriteLibrary.ensureLoaded(sprite, id: "player", onProgress: onProgress)
        }
        if let combat = playerConfig.combatSprite {
            await spriteLibrary.ensureLoaded(combat, id: "player_combat")
        }
        if playerConfig.sprite == nil {
            onProgress?(1)
        }
    }

    /// Ensures the vector flyover ship is loaded for inventory use.
    func ensureVectorSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        guard let config = try? VectorSpritesConfig.loadFromBundle() else {
            onProgress?(1)
            return
        }
        for entry in config.entries {
            await spriteLibrary.ensureLoaded(entry.config, id: entry.id, onProgress: onProgress)
        }
    }

    /// Ensures item pickup sprite animations are loaded for this session.
    ///
    /// By default warms shared pickups plus every level treasure part (bootstrapped at load).
    func ensureItemSpritesLoaded(
        includeAllTreasures: Bool = true,
        onProgress: ((Double) -> Void)? = nil
    ) async {
        var requiredIDs: Set<String> = [
            PickupKind.health.rawValue,
            PickupKind.energy.rawValue,
            PickupKind.treasure.rawValue,
        ]
        if includeAllTreasures {
            requiredIDs.formUnion(LevelCatalog.loadFromBundle().compactMap(\.treasure))
        } else if let treasureID = selectedLevel.treasure {
            requiredIDs.insert(treasureID)
        }

        let entries = itemsConfig.items
            .filter { requiredIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
            .compactMap { id, item -> (String, SpriteConfig)? in
                guard let sprite = item.sprite else { return nil }
                return (id, sprite)
            }
        guard !entries.isEmpty else {
            onProgress?(1)
            return
        }

        let total = entries.count
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
        }
        onProgress?(1)
    }

    /// Warms level-select inventory icons for the given treasure item ids.
    func ensureTreasureIconsLoaded(ids: [String]) async {
        for id in ids {
            guard let sprite = itemsConfig.spriteConfig(id: id) else { continue }
            await spriteLibrary.ensureLoaded(sprite, id: id)
        }
    }

    /// Sprite ids warmed at bootstrap and kept across levels.
    ///
    /// Enemy, projectile, and `player_combat` sprites are level-scoped: loaded by
    /// `GameWorldPreparer.prepareLaunch` and dropped by `releaseLevelScopedAssets()`.
    var persistentSpriteIDs: Set<String> {
        // `logo` and `menu_icons` stay pinned — MenuView reads them. `kam`/`yoda` are
        // loading-screen-only and are invalidated when the player leaves LoadingView.
        var ids: Set<String> = [
            "player",
            "energy",
            "health",
            "coin",
            "treasure",
            "logo",
            MenuSpritesConfig.iconsID,
            "merchant",
            VectorSpritesConfig.libraryID,
        ]
        let levels = LevelCatalog.loadFromBundle()
        ids.formUnion(levels.map(\.resourceName))
        return ids
    }

    /// Frees cutscene character clips after the cutscene ends; video preload stays warm.
    func releaseCutsceneSprites() {
        spriteLibrary.invalidate(id: CutsceneSpritesConfig.playerID)
        spriteLibrary.invalidate(id: CutsceneSpritesConfig.yodaID)
        MemoryProbe.mark("cutscene-sprites-released sprites=\(spriteLibrary.residentBytes / 1_048_576)MB")
    }

    /// Frees enemy, per-level treasure, atlas sets, gate art, and screen backgrounds after leaving a level.
    func releaseLevelScopedAssets() {
        spriteLibrary.retain(ids: persistentSpriteIDs)
        floorTileSetLibrary.release()
        letterSpriteSetLibrary.release()
        pitSpriteSetLibrary.release()
        gateSpriteSetLibrary.release()
        releaseGateMinigameArt()
        // Keep no backgrounds at level exit — the next screen reloads what it needs.
        backgroundLibrary.retain(names: [])
        MemoryProbe.mark("level-assets-released sprites=\(spriteLibrary.residentBytes / 1_048_576)MB")
    }

    /// Decodes only the gate art the selected level can actually spawn.
    ///
    /// Weight-0 kinds are never baked onto a tile by the generation bag,
    /// so they are unreachable and their art (a 17 MB background each) is not decoded.
    /// Returns the textures so the caller can include them in one `SKTexture.preload`.
    @discardableResult
    func ensureGateMinigameArtLoaded() -> [SKTexture] {
        let kinds = Set(
            selectedGateConfig.weightedMinigameKinds
                .filter { appConfig.demoMode || $0.weight > 0 }
                .map(\.kind)
        )
        var textures = GateMinigameBackground.preloadTextures(kinds: kinds)
        if kinds.contains(.soundOutWord), let capacitor = GateSpellingCapacitorSprites.load() {
            textures.append(capacitor)
        }
        if kinds.contains(.graphemeMatch), let switches = GateGraphemeMatchSwitchSprites.load() {
            textures.append(switches.off)
            textures.append(switches.on)
        }
        if kinds.contains(.wordPlug) || kinds.contains(.endingSoundPlug) {
            if let sockets = GateWordPlugSocketSprites.load() {
                textures.append(contentsOf: sockets)
            }
            if let plugs = GateWordPlugPlugSprites.load() {
                textures.append(contentsOf: plugs)
            }
        }
        return textures
    }

    /// Drops every gate minigame static texture cache.
    func releaseGateMinigameArt() {
        GateMinigameBackground.release()
        GateSpellingCapacitorSprites.release()
        GateGraphemeMatchSwitchSprites.release()
        GateWordPlugSocketSprites.release()
        GateWordPlugPlugSprites.release()
    }

    /// Drops level-scoped textures under memory pressure.
    ///
    /// Safe outside a level; during play the enemy sprites are in use, so this is
    /// registered only while no game is presented.
    func startObservingMemoryPressure() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                MemoryProbe.mark("memory-warning")
                self?.releaseLevelScopedAssets()
            }
        }
    }

    func stopObservingMemoryPressure() {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        memoryWarningObserver = nil
    }

    /// Ensures enemy sprite animations for the selected level's spawn list are loaded.
    ///
    /// Scoped rather than loading every catalog sprite: the full set is ~160 sheets.
    /// Returns `false` if any sprite is still incomplete after one retry — callers must
    /// not present the level until this returns `true`.
    @discardableResult
    func ensureEnemySpritesLoaded(onProgress: ((Double) -> Void)? = nil) async -> Bool {
        let typeIDs = generationConfig.enemies?.types ?? []
        let spriteIDs = Set(typeIDs.compactMap { enemyConfig.enemies[$0]?.sprite })
        // Sorted so progress reporting is deterministic across launches.
        let entries = enemyConfig.sprites
            .filter { spriteIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
        guard !entries.isEmpty else {
            onProgress?(1)
            return true
        }

        let total = entries.count
        var allReady = true
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            func reportLocal(_ local: Double) {
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
            await spriteLibrary.ensureLoaded(entry.value, id: entry.key, onProgress: reportLocal)
            if !spriteLibrary.isLoaded(id: entry.key) {
                await spriteLibrary.ensureLoaded(entry.value, id: entry.key, onProgress: reportLocal)
            }
            if !spriteLibrary.isLoaded(id: entry.key) {
                let missing = spriteLibrary.missingAnimations(id: entry.key, config: entry.value)
                GameLogger.error(
                    .sprites,
                    "enemy sprite '\(entry.key)' incomplete after retry — missing \(missing.joined(separator: ", "))"
                )
                allReady = false
            }
        }
        // Projectiles are level-scoped, unlike enemy bodies: all eight sheets at native
        // resolution are ~137 MB, so only the current level's are kept resident.
        for typeID in Set(typeIDs) {
            guard let projectile = enemyConfig.projectileSpriteConfig(for: typeID) else { continue }
            await spriteLibrary.ensureLoaded(projectile.config, id: projectile.id)
            if !spriteLibrary.isLoaded(id: projectile.id) {
                GameLogger.error(.sprites, "projectile sprite '\(projectile.id)' incomplete")
            }
        }
        onProgress?(1)
        return allReady
    }

    /// Ensures NPC sprite animations (currently the merchant) are loaded.
    func ensureNpcSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let entries = npcsConfig.sprites.sorted { $0.key < $1.key }
        guard !entries.isEmpty else {
            onProgress?(1)
            return
        }
        let total = entries.count
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            await spriteLibrary.ensureLoaded(entry.value, id: entry.key) { local in
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
        }
        onProgress?(1)
    }

    /// Loads the baked floor tile set for the currently selected level.
    func ensureFloorTileSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await floorTileSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Loads the baked letter glyph set for the currently selected level.
    func ensureLetterSpriteSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.letters.set
        await letterSpriteSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Loads the baked pit platform tile set for the currently selected level.
    /// Uses the same set name as the level floor set (`1-tython`, …).
    func ensurePitSpriteSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await pitSpriteSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Loads the baked world gate wall sprites for the currently selected level.
    /// Uses the same set name as the level floor set (`1-tython`, …).
    func ensureGateSpriteSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await gateSpriteSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Ensures level-select planet sprites are loaded for this session.
    func ensureUISpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let entries = LevelCatalog.loadFromBundle().compactMap { level -> (String, SpriteConfig)? in
            guard let sprite = level.sprite else { return nil }
            return (level.resourceName, sprite)
        }
        guard !entries.isEmpty else {
            onProgress?(1)
            return
        }

        let total = entries.count
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
        }
        onProgress?(1)
    }
}
