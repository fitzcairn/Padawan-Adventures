import Foundation
import UIKit

extension ConfigAudit {
    static func checkSpriteConfig(
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

    static func checkMusicCue(
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

    static func checkFXTable(
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

    static func requireFX(
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

    /// Structural layout invariants for `Levels/`, where every directory is a playable level
    /// and its assets are found by name. These catch a level added by hand or by copying a
    /// sibling folder, which otherwise fails later as a missing-atlas error naming the
    /// wrong level.
    static func checkLevelLayout(bundle: Bundle = .main) -> [String] {
        var problems: [String] = []
        guard let root = bundle.resourceURL?.appendingPathComponent(
            ConfigPath.levelRoot,
            isDirectory: true
        ) else {
            return ["level layout: bundle has no resourceURL"]
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ["level layout: '\(ConfigPath.levelRoot)' is missing"]
        }

        var sawLevel = false
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory

            guard isDirectory == true else {
                // Only shared bases such as `_defaults.yaml` belong beside the level folders.
                if !name.hasPrefix("_") {
                    problems.append(
                        "level layout: '\(name)' must live inside a level folder"
                    )
                }
                continue
            }
            if name.hasPrefix("_") { continue }

            sawLevel = true
            problems.append(contentsOf: checkLevelFolder(at: entry, id: name))
        }

        if !sawLevel {
            problems.append("level layout: '\(ConfigPath.levelRoot)' holds no level folders")
        }
        return problems
    }

    /// A level folder holds its `level.yaml` plus art named after the level, so copying a
    /// sibling folder without renaming its files is caught here rather than at load.
    private static func checkLevelFolder(at url: URL, id: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return ["level layout: '\(id)' is unreadable"]
        }

        var problems: [String] = []
        let levelFile = "level.\(ConfigPath.level(id).fileExtension)"
        if !contents.contains(where: { $0.lastPathComponent == levelFile }) {
            problems.append("level layout: '\(id)' has no \(levelFile)")
        }

        // Assets are prefixed with the level's ordinal so treasures (`1-emitter-atlas`)
        // sit beside the sets derived from the full id (`1-tython-floor-atlas`).
        let prefix = "\(id.prefix(while: { $0 != "-" }))-"
        for asset in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let basename = asset.lastPathComponent
            guard basename != levelFile, !basename.hasPrefix(prefix) else { continue }
            problems.append(
                "level layout: '\(id)/\(basename)' must start with '\(prefix)'"
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

    /// Mirrors `SpriteSheetLoader.resourceURL` exactly: one lookup, in `root` only.
    /// Any laxer search here would pass assets the loader then fails to find.
    private static func resourceExists(
        named name: String,
        extensions: [String],
        root: String,
        bundle: Bundle
    ) -> Bool {
        (try? SpriteSheetLoader.resourceURL(
            named: name,
            extensions: extensions,
            root: root,
            bundle: bundle
        )) != nil
    }

    private static func directoryHasResources(root: String, bundle: Bundle) -> Bool {
        if let urls = bundle.urls(forResourcesWithExtension: nil, subdirectory: root),
           !urls.isEmpty {
            return true
        }
        for ext in imageExtensions {
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: root),
               !urls.isEmpty {
                return true
            }
        }
        return false
    }
}
