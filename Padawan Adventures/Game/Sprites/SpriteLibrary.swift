import Foundation

/// Session-scoped cache of sliced sprite animations.
@MainActor
final class SpriteLibrary {
    private var loadedIDs: Set<String> = []
    private var animationsByID: [String: [String: SpriteAnimation]] = [:]
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads all animations for `config` under `id` if not already loaded.
    ///
    /// `onProgress` receives a 0...1 fraction after each sheet animation is processed.
    func ensureLoaded(
        _ config: SpriteConfig,
        id: String,
        onProgress: ((Double) -> Void)? = nil
    ) async {
        guard !loadedIDs.contains(id) else {
            onProgress?(1)
            return
        }

        var loaded: [String: SpriteAnimation] = [:]
        var sheetSources: [(name: String, sheet: String, atlas: String)] = []
        var flipSources: [(name: String, source: String)] = []

        for (name, source) in config.animations {
            switch source {
            case .sheet(let sheet, let atlas):
                sheetSources.append((name, sheet, atlas))
            case .flipOf(let other):
                flipSources.append((name, other))
            }
        }

        let total = max(sheetSources.count, 1)
        if sheetSources.isEmpty {
            onProgress?(1)
        }

        for (index, entry) in sheetSources.enumerated() {
            do {
                loaded[entry.name] = try SpriteSheetLoader.loadAnimation(
                    sheet: entry.sheet,
                    atlas: entry.atlas,
                    root: config.root,
                    chromaKey: config.chromaKey,
                    chromaKeyTolerance: config.chromaKeyTolerance,
                    chromaKeyFeather: config.chromaKeyFeather,
                    chromaKeySmooth: config.chromaKeySmooth,
                    bundle: bundle
                )
            } catch {
                // Missing assets are skipped so worlds still load while sheets arrive.
            }
            onProgress?(Double(index + 1) / Double(total))
            await Task.yield()
        }

        Self.resolveFlipAnimations(into: &loaded, flipSources: flipSources)

        animationsByID[id] = loaded
        loadedIDs.insert(id)
        onProgress?(1)
    }

    /// Resolves `flip_of` entries against already-loaded sheet animations.
    static func resolveFlipAnimations(
        into loaded: inout [String: SpriteAnimation],
        flipSources: [(name: String, source: String)]
    ) {
        var pending = flipSources
        for _ in 0..<pending.count + 1 {
            guard !pending.isEmpty else { break }
            var stillPending: [(name: String, source: String)] = []
            for entry in pending {
                if let source = loaded[entry.source] {
                    loaded[entry.name] = source.flipped()
                } else {
                    stillPending.append(entry)
                }
            }
            if stillPending.count == pending.count { break }
            pending = stillPending
        }
    }

    /// Testing seam: mark `id` loaded without reading the bundle.
    func seedForTesting(id: String, animations: [String: SpriteAnimation]) {
        animationsByID[id] = animations
        loadedIDs.insert(id)
    }

    func isLoaded(id: String) -> Bool {
        loadedIDs.contains(id)
    }

    func animation(id: String, named name: String) -> SpriteAnimation? {
        animationsByID[id]?[name]
    }

    /// Convenience for the common single-library playback case after `ensureLoaded`.
    func animation(named name: String, in id: String = "player") -> SpriteAnimation? {
        animation(id: id, named: name)
    }

    func animationCount(for id: String) -> Int {
        animationsByID[id]?.count ?? 0
    }
}
