import Foundation

extension ConfigAudit {
    /// One audio basename config can ask for, and which bundled tree must hold it.
    nonisolated struct AudioReference: Equatable, Sendable {
        enum Tree: Equatable, Sendable {
            case music
            case fx
        }

        /// Config path used in audit messages, e.g. `levels[0] (Tython).pit.fx.land`.
        let kind: String
        let basename: String
        let tree: Tree

        /// Trims on the way in so the existence check and the orphan check compare the
        /// same string; an all-whitespace basename stays empty and is reported as missing.
        init(kind: String, basename: String, tree: Tree) {
            self.kind = kind
            self.basename = basename.trimmingCharacters(in: .whitespacesAndNewlines)
            self.tree = tree
        }
    }

    /// Every audio basename reachable from decoded config.
    ///
    /// Both directions read this one list: `run` checks each reference resolves to a file, and
    /// `checkOrphanAudio` checks every file is reachable. Gathering them once means a newly
    /// added cue cannot be covered by one direction and silently missed by the other.
    ///
    static func audioReferences(
        levels: [LevelConfig],
        enemies: EnemyConfig,
        words: WordCatalog,
        letters: GraphemeCatalog,
        audio: SoundSettings,
        screens: ScreensConfig?,
        player: PlayerConfig?,
        strings: StringCatalog,
        npcs: NpcsConfig? = nil
    ) -> [AudioReference] {
        var references: [AudioReference] = []

        for (index, level) in levels.enumerated() {
            let label = "levels[\(index)] (\(level.name))"
            references.append(contentsOf: musicReferences(level.musicCue, kind: "\(label).world.music"))
            references.append(contentsOf: musicReferences(
                MusicCue.parse(level.combat.music), kind: "\(label).combat.music"
            ))
            references.append(contentsOf: musicReferences(
                MusicCue.parse(level.pit.music), kind: "\(label).pit.music"
            ))
            references.append(contentsOf: musicReferences(
                MusicCue.parse(level.gate.music), kind: "\(label).gate.music"
            ))
            references.append(contentsOf: fxReferences(level.pit.fx, kind: "\(label).pit.fx"))
            references.append(contentsOf: fxReferences(level.gate.fx, kind: "\(label).gate.fx"))

            for (idx, minigame) in level.gate.minigames.enumerated() {
                let minigameKind = "\(label).gate.minigames[\(idx)]"
                let fx: SoundEffectTable
                let music: String?
                switch minigame {
                case .soundOutWord(let config):
                    fx = config.fx
                    music = config.music
                case .graphemeMatch(let config):
                    fx = config.fx
                    music = config.music
                case .wordPlug(let config):
                    fx = config.fx
                    music = config.music
                }
                references.append(contentsOf: fxReferences(fx, kind: "\(minigameKind).fx"))
                if let music {
                    references.append(contentsOf: musicReferences(
                        MusicCue.parse(music), kind: "\(minigameKind).music"
                    ))
                }
            }
        }

        references.append(contentsOf: fxReferences(audio.fx, kind: "audio.audio.fx"))

        if let player {
            references.append(contentsOf: fxReferences(player.fx, kind: "player.player.fx"))
        }

        for (enemyID, enemy) in enemies.enemies.sorted(by: { $0.key < $1.key }) {
            references.append(contentsOf: fxReferences(enemy.fx, kind: "enemies.\(enemyID).fx"))
            for (letter, shot) in enemy.shotTypes.sorted(by: { $0.key < $1.key }) {
                references.append(contentsOf: fxReferences(
                    shot.fx, kind: "enemies.\(enemyID).shot_types.\(letter).fx"
                ))
            }
        }

        for word in words.words {
            references.append(
                AudioReference(kind: "words.\(word.word).sfx", basename: word.sfx, tree: .fx)
            )
        }

        for (id, entry) in strings.entries.sorted(by: { $0.key < $1.key }) {
            let basename = entry.sfx.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !basename.isEmpty else { continue }
            references.append(
                AudioReference(kind: "strings.\(id).sfx", basename: basename, tree: .fx)
            )
        }

        for grapheme in letters.graphemes {
            references.append(
                AudioReference(
                    kind: "graphemes.\(grapheme.grapheme).pronunciation",
                    basename: grapheme.pronunciation,
                    tree: .fx
                )
            )
            references.append(
                AudioReference(
                    kind: "graphemes.\(grapheme.grapheme).name",
                    basename: grapheme.name,
                    tree: .fx
                )
            )
        }

        if let screens {
            for (screenID, screen) in screens.screens.sorted(by: { $0.key < $1.key }) {
                references.append(contentsOf: musicReferences(
                    screen.musicCue, kind: "screens.\(screenID).music"
                ))
            }
        }

        references.append(
            AudioReference(kind: "merchant.music", basename: "merchant", tree: .music)
        )
        references.append(
            AudioReference(kind: "merchant.fx.purchase", basename: "merchant-purchase", tree: .fx)
        )

        if let npcs {
            for (id, table) in npcs.fx.sorted(by: { $0.key < $1.key }) {
                references.append(contentsOf: fxReferences(table, kind: "npcs.fx.\(id)"))
            }
        }

        return references
    }

    /// Tracks deliberately shipped without an active config reference. Every entry states why,
    /// because an allowlist that grows without reasons quietly turns the check off.
    static let intentionallyUnreferencedAudio: Set<String> = [
        // Opt-in `switch_push` override shown in the commented letter_match example in
        // `Levels/_defaults.yaml`; a level enables it by uncommenting that block.
        "gate-grapheme_match-switch-push",
        // Pit falling SFX bundled for future use; no level currently references it via `pit.fx`.
        "pit-falling",
    ]

    /// Flags bundled audio that no config can reach.
    ///
    /// An unreachable file is dead weight in the shipped bundle, not a load failure, so this is
    /// a bundle-hygiene invariant for tests rather than part of `run`. Failing app start over an
    /// unused file would be wrong, and `run` is also called with a single level in places, where
    /// every other level's music would look unreferenced.
    ///
    /// Pass the references gathered from the *complete* bundled config.
    static func checkOrphanAudio(
        references: [AudioReference],
        bundle: Bundle = .main
    ) -> [String] {
        guard let resourceURL = bundle.resourceURL else {
            return ["orphan audio: bundle has no resourceURL"]
        }

        let referenced = Set(references.map(\.basename))
        var problems: [String] = []
        var bundled: Set<String> = []
        for subdirectory in ["Audio/Music", "Audio/FX"] {
            for url in audioFiles(under: subdirectory, in: resourceURL) {
                let basename = url.deletingPathExtension().lastPathComponent
                bundled.insert(basename)
                guard !referenced.contains(basename),
                      !intentionallyUnreferencedAudio.contains(basename) else {
                    continue
                }
                problems.append(
                    "orphan audio: '\(basename)' is bundled but no config references it"
                )
            }
        }

        // Keep the allowlist honest: an entry whose file is gone only hides future orphans.
        for allowed in intentionallyUnreferencedAudio.subtracting(bundled).sorted() {
            problems.append(
                "orphan audio: allowlisted '\(allowed)' is no longer bundled; drop it from"
                    + " intentionallyUnreferencedAudio"
            )
        }
        return problems.sorted()
    }

    private static func musicReferences(_ cue: MusicCue, kind: String) -> [AudioReference] {
        guard case .track(let basename) = cue else { return [] }
        return [AudioReference(kind: kind, basename: basename, tree: .music)]
    }

    private static func fxReferences(_ table: SoundEffectTable, kind: String) -> [AudioReference] {
        table.events.sorted(by: { $0.key < $1.key }).map { event, basename in
            AudioReference(kind: "\(kind).\(event)", basename: basename, tree: .fx)
        }
    }
}
