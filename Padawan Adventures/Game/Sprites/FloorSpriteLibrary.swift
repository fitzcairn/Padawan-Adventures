import Foundation

/// Session-scoped cache of floor terrain animations (all tiles loaded at game open).
@MainActor
final class FloorSpriteLibrary {
    private var animations: [String: SpriteAnimation] = [:]
    private(set) var isLoaded = false
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads every terrain animation from `catalog` once.
    func ensureLoaded(
        catalog: TerrainCatalog,
        onProgress: ((Double) -> Void)? = nil
    ) async {
        guard !isLoaded else {
            onProgress?(1)
            return
        }
        do {
            animations = try await FloorSpriteLoader.loadAll(
                catalog: catalog,
                bundle: bundle,
                onProgress: { fraction in
                    onProgress?(fraction)
                }
            )
            isLoaded = true
            onProgress?(1)
        } catch {
            // Missing assets leave the library empty; floors fall back to shape placeholders.
            print("FloorSpriteLibrary: failed to load terrains — \(error)")
            animations = [:]
            isLoaded = true
            onProgress?(1)
        }
    }

    /// Testing seam: mark loaded without reading the bundle.
    func seedForTesting(_ animations: [String: SpriteAnimation]) {
        self.animations = animations
        isLoaded = true
    }

    func animation(id: String) -> SpriteAnimation? {
        animations[id]
    }

    var animationCount: Int {
        animations.count
    }

    var terrainIDs: [String] {
        Array(animations.keys).sorted()
    }
}
