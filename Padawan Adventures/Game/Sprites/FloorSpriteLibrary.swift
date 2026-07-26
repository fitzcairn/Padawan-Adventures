import Foundation

/// Session-scoped cache of floor terrain animations (all tiles loaded at game open).
///
/// Thin facade over `SpriteSheetLoader.loadNamedFrameAnimations` so existing call
/// sites keep `animation(id:)`, anchors, and progress reporting.
@MainActor
final class FloorSpriteLibrary {
    private var animations: [String: SpriteAnimation] = [:]
    private var anchors: [String: FloorAnchor] = [:]
    private(set) var terrainIDs: [String] = []
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
            let sprite = catalog.sprite
            let frameKeys = catalog.terrains.keys.sorted()
            let loaded = try await SpriteSheetLoader.loadNamedFrameAnimations(
                sheet: sprite.sheet,
                atlas: sprite.atlas,
                root: sprite.root,
                frameKeys: frameKeys,
                chromaKey: sprite.chromaKey,
                chromaKeyTolerance: sprite.chromaKeyTolerance,
                chromaKeyFeather: sprite.chromaKeyFeather,
                chromaKeySmooth: sprite.chromaKeySmooth,
                atlasRoot: sprite.atlasRoot,
                bundle: bundle,
                flipsHorizontally: true,
                onProgress: { fraction in
                    onProgress?(fraction)
                }
            )
            animations = loaded.animations
            anchors = loaded.anchors
            terrainIDs = animations.keys.sorted()
            isLoaded = true
            onProgress?(1)
        } catch {
            // Missing assets leave the library empty; floors fall back to shape placeholders.
            print("FloorSpriteLibrary: failed to load terrains — \(error)")
            animations = [:]
            anchors = [:]
            terrainIDs = []
            isLoaded = false
            onProgress?(1)
        }
    }

    /// Testing seam: mark loaded without reading the bundle.
    func seedForTesting(
        _ animations: [String: SpriteAnimation],
        anchors: [String: FloorAnchor] = [:]
    ) {
        self.animations = animations
        self.anchors = anchors
        self.terrainIDs = animations.keys.sorted()
        isLoaded = true
    }

    func animation(id: String) -> SpriteAnimation? {
        animations[id]
    }

    func anchor(of id: String) -> FloorAnchor? {
        anchors[id]
    }

    var animationCount: Int {
        animations.count
    }
}
