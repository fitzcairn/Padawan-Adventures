import Foundation
import UIKit

nonisolated enum ConfigAuditError: Error, Equatable, CustomStringConvertible {
    case detail(String)

    var description: String {
        switch self {
        case .detail(let message):
            return message
        }
    }
}

/// Cross-file checks no single decoder can see (ids, audio basenames, sprites, symbols).
nonisolated enum ConfigAudit {
    private static let audioExtensions = ["m4a", "caf", "wav", "mp3"]
    private static let imageExtensions = ["png", "jpg", "jpeg"]

    /// Cross-file checks no single decoder can see. Throws `ConfigAuditError` with details.
    @MainActor
    static func run(
        app: AppConfig,
        levels: [LevelConfig],
        enemies: EnemyConfig,
        items: ItemsConfig,
        words: WordCatalog,
        letters: LetterCatalog,
        audio: SoundSettings,
        screens: ScreensConfig?,
        player: PlayerConfig? = nil,
        bundle: Bundle = .main
    ) throws {
        _ = app

        var problems: [String] = []

        for (index, level) in levels.enumerated() {
            let label = "levels[\(index)] (\(level.name))"
            problems.append(contentsOf: checkFloorSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkLetterSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkPitSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkGateSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkEnemyTypes(level: level, enemies: enemies, label: label))
            problems.append(contentsOf: checkWordIDs(level: level, words: words, label: label))
            problems.append(contentsOf: checkLetterIDs(level: level, letters: letters, label: label))
            problems.append(contentsOf: checkArtifact(level.artifact, label: label))
            problems.append(contentsOf: checkTreasureID(level: level, items: items, label: label, bundle: bundle))
            problems.append(contentsOf: checkLevelSprite(level.sprite, label: label, bundle: bundle))
            problems.append(contentsOf: checkMusicCue(level.musicCue, kind: "music", label: label, bundle: bundle))
            problems.append(contentsOf: checkMusicCue(
                level.gameMusic.combatCue, kind: "game_music.combat", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkMusicCue(
                level.gameMusic.pitCue, kind: "game_music.pit", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkMusicCue(
                level.gameMusic.gateCue, kind: "game_music.gate", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkFXTable(
                level.pit.fx, kind: "pit.fx", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkFXTable(
                level.gate.fx, kind: "gate.fx", label: label, bundle: bundle
            ))
            for (idx, minigame) in level.gate.minigames.enumerated() {
                switch minigame {
                case .spelling(let c):
                    problems.append(contentsOf: checkFXTable(
                        c.fx, kind: "gate.minigames[\(idx)].fx", label: label, bundle: bundle
                    ))
                    if let music = c.music {
                        problems.append(contentsOf: checkMusicCue(
                            MusicCue.parse(music),
                            kind: "gate.minigames[\(idx)].music",
                            label: label,
                            bundle: bundle
                        ))
                    }
                case .letterMatch(let c):
                    problems.append(contentsOf: checkFXTable(
                        c.fx, kind: "gate.minigames[\(idx)].fx", label: label, bundle: bundle
                    ))
                    if let music = c.music {
                        problems.append(contentsOf: checkMusicCue(
                            MusicCue.parse(music),
                            kind: "gate.minigames[\(idx)].music",
                            label: label,
                            bundle: bundle
                        ))
                    }
                }
            }
        }

        problems.append(contentsOf: checkFXTable(audio.fx, kind: "audio.fx", label: "audio", bundle: bundle))

        if let player {
            problems.append(contentsOf: checkFXTable(
                player.fx, kind: "player.fx", label: "player", bundle: bundle
            ))
            if let sprite = player.sprite {
                problems.append(contentsOf: checkSpriteConfig(
                    sprite, label: "player.sprite", bundle: bundle
                ))
            }
            if let combatSprite = player.combatSprite {
                problems.append(contentsOf: checkSpriteConfig(
                    combatSprite, label: "player.combat_sprite", bundle: bundle
                ))
            }
        }

        for (enemyID, enemy) in enemies.enemies.sorted(by: { $0.key < $1.key }) {
            problems.append(contentsOf: checkFXTable(
                enemy.fx, kind: "fx", label: "enemies.\(enemyID)", bundle: bundle
            ))
            for (letter, shot) in enemy.shotTypes.sorted(by: { $0.key < $1.key }) {
                problems.append(contentsOf: checkFXTable(
                    shot.fx,
                    kind: "shot_types.\(letter).fx",
                    label: "enemies.\(enemyID)",
                    bundle: bundle
                ))
            }
        }

        for word in words.words {
            problems.append(contentsOf: requireFX(
                word.spelling, kind: "words.\(word.word).spelling", bundle: bundle
            ))
            for (prefix, track) in word.progressive.sorted(by: { $0.key < $1.key }) {
                problems.append(contentsOf: requireFX(
                    track, kind: "words.\(word.word).progressive.\(prefix)", bundle: bundle
                ))
            }
        }

        for letter in letters.letters {
            problems.append(contentsOf: requireFX(
                letter.pronunciation, kind: "letters.\(letter.letter).pronunciation", bundle: bundle
            ))
            problems.append(contentsOf: requireFX(
                letter.name, kind: "letters.\(letter.letter).name", bundle: bundle
            ))
        }

        if let screens {
            for (screenID, screen) in screens.screens.sorted(by: { $0.key < $1.key }) {
                problems.append(contentsOf: checkMusicCue(
                    screen.musicCue,
                    kind: "music",
                    label: "screens.\(screenID)",
                    bundle: bundle
                ))
            }
        }

        problems.append(contentsOf: checkAudioLayout(bundle: bundle))

        if !problems.isEmpty {
            throw ConfigAuditError.detail(problems.joined(separator: "; "))
        }
    }

    // MARK: - Checks

    private static func checkFloorSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.floor.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).floor.set: empty"]
        }
        do {
            let tileSet = try FloorTileSet.loadFromBundle(set: setName, bundle: bundle)
            if tileSet.floorTileIDs.isEmpty {
                return ["\(label).floor.set: '\(setName)' has no role=floor tiles"]
            }
        } catch {
            return ["\(label).floor.set: missing or invalid atlas for '\(setName)' (\(error))"]
        }
        if level.floor.decorProb < 0 || level.floor.decorProb > 1 {
            return ["\(label).floor.decor_prob: \(level.floor.decorProb) out of 0...1"]
        }
        return []
    }

    private static func checkLetterSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.letters.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).letters.set: empty"]
        }
        do {
            let letterSet = try LetterSpriteSet.loadFromBundle(set: setName, bundle: bundle)
            if letterSet.frames.count != 52 {
                return [
                    "\(label).letters.set: '\(setName)' has \(letterSet.frames.count) frames, expected 52"
                ]
            }
            let missing = letterSet.missingKeys
            if !missing.isEmpty {
                return [
                    "\(label).letters.set: '\(setName)' missing glyphs \(missing.joined(separator: ","))"
                ]
            }
        } catch {
            return ["\(label).letters.set: missing or invalid atlas for '\(setName)' (\(error))"]
        }
        return []
    }

    /// Pit platforms share the floor set name (`Sprites/Pit/{floor.set}/`).
    private static func checkPitSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.floor.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).floor.set: empty (required for pit sprites)"]
        }
        do {
            let pitSet = try PitSpriteSet.loadFromBundle(set: setName, bundle: bundle)
            if pitSet.frames.isEmpty {
                return ["\(label).pit set '\(setName)': has no platform tiles"]
            }
        } catch {
            return ["\(label).pit set '\(setName)': missing or invalid atlas (\(error))"]
        }
        return []
    }

    /// World gate walls share the floor set name (`Sprites/Gate/Floor/{floor.set}/`).
    private static func checkGateSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.floor.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).floor.set: empty (required for gate sprites)"]
        }
        do {
            let gateSet = try GateSpriteSet.loadFromBundle(set: setName, bundle: bundle)
            let axes = Set(gateSet.axisIDs)
            let expected = Set(GateSpriteSet.Axis.allCases.map(\.rawValue))
            if axes != expected {
                return [
                    "\(label).gate set '\(setName)': expected frames \(expected.sorted()), got \(axes.sorted())"
                ]
            }
        } catch {
            return ["\(label).gate set '\(setName)': missing or invalid atlas (\(error))"]
        }
        return []
    }

    private static func checkEnemyTypes(
        level: LevelConfig,
        enemies: EnemyConfig,
        label: String
    ) -> [String] {
        guard let spawn = level.enemies else { return [] }
        return spawn.types.compactMap { typeID in
            guard enemies.type(named: typeID) != nil else {
                return "\(label).enemies.types: unknown enemy id '\(typeID)'"
            }
            return nil
        }
    }

    private static func checkTreasureID(
        level: LevelConfig,
        items: ItemsConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        guard let id = level.treasure else { return [] }
        guard let sprite = items.items[id]?.sprite else {
            return ["\(label).treasure: unknown item id '\(id)' in items.yaml"]
        }
        return checkSpriteConfig(sprite, label: "\(label).treasure.sprite", bundle: bundle)
    }

    private static func checkWordIDs(
        level: LevelConfig,
        words: WordCatalog,
        label: String
    ) -> [String] {
        var problems: [String] = []
        if let ids = level.pit.wordIDs {
            for id in ids where words.word(named: id) == nil {
                problems.append("\(label).pit.words: unknown word id '\(id)'")
            }
        }
        for (idx, minigame) in level.gate.minigames.enumerated() {
            if case .spelling(let c) = minigame, let ids = c.wordIDs {
                for id in ids where words.word(named: id) == nil {
                    problems.append("\(label).gate.minigames[\(idx)].words: unknown word id '\(id)'")
                }
            }
        }
        return problems
    }

    private static func checkLetterIDs(
        level: LevelConfig,
        letters: LetterCatalog,
        label: String
    ) -> [String] {
        var problems: [String] = []
        for (idx, minigame) in level.gate.minigames.enumerated() {
            if case .letterMatch(let c) = minigame, let ids = c.letterIDs {
                for id in ids {
                    if letters.letter(named: id) == nil {
                        problems.append(
                            "\(label).gate.minigames[\(idx)].letters: unknown letter id '\(id)'"
                        )
                    }
                }
            }
        }
        return problems
    }

    @MainActor
    private static func checkArtifact(_ artifact: String, label: String) -> [String] {
        let trimmed = artifact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["\(label).artifact: must be non-empty"]
        }
        guard UIImage(systemName: trimmed) != nil else {
            return ["\(label).artifact: '\(trimmed)' is not a valid SF Symbol"]
        }
        return []
    }

    private static func checkLevelSprite(
        _ sprite: SpriteConfig?,
        label: String,
        bundle: Bundle
    ) -> [String] {
        guard let sprite else { return [] }
        return checkSpriteConfig(sprite, label: "\(label).sprite", bundle: bundle)
    }

    private static func checkSpriteConfig(
        _ sprite: SpriteConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        var problems: [String] = []
        let root = sprite.root.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else {
            return ["\(label).root: must be non-empty"]
        }

        var sawSheet = false
        for (animationName, source) in sprite.animations.sorted(by: { $0.key < $1.key }) {
            guard case .sheet(let sheet, _) = source else { continue }
            sawSheet = true
            let sheetName = sheet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sheetName.isEmpty else {
                problems.append("\(label).animations.\(animationName).sheet: must be non-empty")
                continue
            }
            if !resourceExists(
                named: sheetName,
                extensions: imageExtensions,
                root: root,
                bundle: bundle
            ) {
                problems.append(
                    "\(label).animations.\(animationName): missing sheet '\(root)/\(sheetName)'"
                )
            }
        }

        if !sawSheet, !directoryHasResources(root: root, bundle: bundle) {
            problems.append("\(label).root: no bundled resources under '\(root)'")
        }
        return problems
    }

    private static func checkMusicCue(
        _ cue: MusicCue,
        kind: String,
        label: String,
        bundle: Bundle
    ) -> [String] {
        switch cue {
        case .unchanged, .silence:
            return []
        case .track(let basename):
            return requireMusic(basename, kind: "\(label).\(kind)", bundle: bundle)
        }
    }

    private static func checkFXTable(
        _ table: SoundEffectTable,
        kind: String,
        label: String,
        bundle: Bundle
    ) -> [String] {
        table.events.sorted(by: { $0.key < $1.key }).flatMap { event, basename in
            requireFX(basename, kind: "\(label).\(kind).\(event)", bundle: bundle)
        }
    }

    private static func requireMusic(
        _ basename: String,
        kind: String,
        bundle: Bundle
    ) -> [String] {
        let trimmed = basename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["\(kind): music basename must be non-empty"]
        }
        guard let url = resolveAudioURL(
            basename: trimmed,
            subdirectories: AudioBundleLayout.musicSubdirectories,
            bundle: bundle
        ) else {
            return ["\(kind): missing music track '\(trimmed)'"]
        }
        if !url.path.contains("/Audio/Music/") {
            return ["\(kind): music track '\(trimmed)' must resolve under Audio/Music"]
        }
        return []
    }

    private static func requireFX(
        _ basename: String,
        kind: String,
        bundle: Bundle
    ) -> [String] {
        let trimmed = basename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["\(kind): fx basename must be non-empty"]
        }
        guard let url = resolveAudioURL(
            basename: trimmed,
            subdirectories: AudioBundleLayout.fxSubdirectories,
            bundle: bundle
        ) else {
            return ["\(kind): missing fx track '\(trimmed)'"]
        }
        if !url.path.contains("/Audio/FX/") {
            return ["\(kind): fx track '\(trimmed)' must resolve under Audio/FX"]
        }
        return []
    }

    /// Structural layout invariants for bundled audio (folder scoping + no flat collisions).
    static func checkAudioLayout(bundle: Bundle = .main) -> [String] {
        var problems: [String] = []
        guard let resourceURL = bundle.resourceURL else {
            return ["audio layout: bundle has no resourceURL"]
        }

        // 1) No audio flattened into the bundle root (non-recursive).
        if let rootEntries = try? FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in rootEntries where isAudioFile(url) {
                problems.append(
                    "audio layout: '\(url.lastPathComponent)' must not sit at the bundle root"
                )
            }
        }

        // 2) Both searched directories present and non-empty (recursive).
        for subdirectory in ["Audio/FX", "Audio/Music"] {
            let audioFiles = audioFiles(under: subdirectory, in: resourceURL)
            if audioFiles.isEmpty {
                problems.append("audio layout: '\(subdirectory)' is missing or empty")
            }
        }

        // 3) No basename collisions between searchable Music and FX trees
        // (includes nested Phonetics/ and UI/ under FX).
        var locationsByBasename: [String: Set<String>] = [:]
        for subdirectory in ["Audio/Music", "Audio/FX"] {
            for url in audioFiles(under: subdirectory, in: resourceURL) {
                let basename = url.deletingPathExtension().lastPathComponent
                locationsByBasename[basename, default: []].insert(subdirectory)
            }
        }
        for basename in locationsByBasename.keys.sorted() {
            guard let locations = locationsByBasename[basename], locations.count > 1 else { continue }
            let joined = locations.sorted().joined(separator: ", ")
            problems.append(
                "audio layout: basename '\(basename)' appears in multiple directories (\(joined))"
            )
        }

        return problems
    }

    /// Recursively lists audio files under `subdirectory` of the bundle resource root.
    private static func audioFiles(under subdirectory: String, in resourceURL: URL) -> [URL] {
        let root = resourceURL.appendingPathComponent(subdirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where isAudioFile(url) {
            urls.append(url)
        }
        return urls
    }

    // MARK: - Bundle helpers

    private static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    private static func resolveAudioURL(
        basename: String,
        subdirectories: [String],
        bundle: Bundle
    ) -> URL? {
        for subdirectory in subdirectories {
            for ext in audioExtensions {
                if let url = bundle.url(
                    forResource: basename,
                    withExtension: ext,
                    subdirectory: subdirectory
                ) {
                    return url
                }
            }
        }
        return nil
    }

    private static func resourceExists(
        named name: String,
        extensions: [String],
        root: String,
        bundle: Bundle
    ) -> Bool {
        let folderHint = animationFolderName(from: name)
        let searchRoots = bundleSearchRoots(for: root)
        var subdirectories: [String] = []
        for searchRoot in searchRoots {
            subdirectories.append("\(searchRoot)/Baked")
            subdirectories.append("\(searchRoot)/\(folderHint)/Baked")
            subdirectories.append(searchRoot)
            subdirectories.append("\(searchRoot)/\(folderHint)")
        }
        subdirectories.append(folderHint)
        subdirectories.append("")
        var seen = Set<String>()
        subdirectories = subdirectories.filter { seen.insert($0).inserted }

        for ext in extensions {
            for subdirectory in subdirectories {
                if subdirectory.isEmpty {
                    if bundle.url(forResource: name, withExtension: ext) != nil {
                        return true
                    }
                } else if bundle.url(
                    forResource: name,
                    withExtension: ext,
                    subdirectory: subdirectory
                ) != nil {
                    return true
                }
            }
        }
        return false
    }

    private static func directoryHasResources(root: String, bundle: Bundle) -> Bool {
        for searchRoot in bundleSearchRoots(for: root) {
            if let urls = bundle.urls(forResourcesWithExtension: nil, subdirectory: searchRoot),
               !urls.isEmpty {
                return true
            }
            for ext in imageExtensions {
                if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: searchRoot),
                   !urls.isEmpty {
                    return true
                }
            }
        }
        return false
    }

    /// Enemy YAML roots are `Enemies/<Type>`; bundled under `Sprites/Enemies/<Type>`.
    private static func bundleSearchRoots(for root: String) -> [String] {
        if root == "Enemies" || root.hasPrefix("Enemies/") {
            return ["Sprites/\(root)", root]
        }
        return [root]
    }

    private static func animationFolderName(from resourceName: String) -> String {
        let suffixes = ["-spritesheet", "-atlas"]
        for suffix in suffixes where resourceName.hasSuffix(suffix) {
            return String(resourceName.dropLast(suffix.count))
        }
        return resourceName
    }
}
