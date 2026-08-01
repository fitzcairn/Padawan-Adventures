import Foundation
import SpriteKit
import UIKit

nonisolated enum AtlasLoadProgressStyle: Sendable {
    case everyIteration
    case everyNth(Int)
}

nonisolated protocol AtlasSpriteSetProviding: Sendable {
    associatedtype LoadedSet: Sendable
    static var assetKind: LevelAssetKind { get }
    static var logLabel: String { get }
    static var progressStyle: AtlasLoadProgressStyle { get }
    static func loadFromBundle(set name: String, bundle: Bundle) throws -> LoadedSet
    static func sheetDimensions(of set: LoadedSet) -> (w: Int, h: Int)
    static func textureKeys(of set: LoadedSet) -> [String]
    static func frameRect(of set: LoadedSet, key: String) -> (x: Int, y: Int, w: Int, h: Int)?
    static func setName(from set: LoadedSet) -> String
}

/// Session-scoped cache of one active atlas sprite set's textures.
@MainActor
final class AtlasSpriteSetLibrary<Provider: AtlasSpriteSetProviding> {
    private(set) var setName: String?
    private(set) var loadedSet: Provider.LoadedSet?
    private var textures: [String: SKTexture] = [:]
    private let bundle: Bundle

    var isLoaded: Bool { loadedSet != nil }

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads (or reloads) the named set. Drops prior textures when the name changes.
    func ensureLoaded(set name: String, onProgress: ((Double) -> Void)? = nil) async {
        if setName == name, loadedSet != nil {
            onProgress?(1)
            return
        }

        onProgress?(0)
        do {
            let loaded = try Provider.loadFromBundle(set: name, bundle: bundle)
            onProgress?(0.3)

            let sheetName = LevelAssetPaths.basename(set: name, Provider.assetKind, .spritesheet)
            let root = LevelAssetPaths.root(set: name, Provider.assetKind)
            let sheetURL = try SpriteSheetLoader.resourceURL(
                named: sheetName,
                extensions: ["png", "jpg", "jpeg"],
                root: root,
                bundle: bundle
            )
            guard let uiImage = UIImage(contentsOfFile: sheetURL.path),
                  let cgImage = uiImage.cgImage else {
                throw SpriteLoadError.invalidImage(sheetName)
            }
            onProgress?(0.5)

            let parent = SKTexture(image: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
            parent.filteringMode = .nearest
            parent.usesMipmaps = false

            let (sheetW, sheetH) = Provider.sheetDimensions(of: loaded)
            var nextTextures: [String: SKTexture] = [:]
            let keys = Provider.textureKeys(of: loaded)
            for (index, key) in keys.enumerated() {
                guard let frame = Provider.frameRect(of: loaded, key: key) else { continue }
                nextTextures[key] = SpriteSheetLoader.makeSubrectTexture(
                    x: frame.x,
                    y: frame.y,
                    w: frame.w,
                    h: frame.h,
                    sheetWidth: sheetW,
                    sheetHeight: sheetH,
                    parent: parent
                )
                reportProgress(index: index, keyCount: keys.count, onProgress: onProgress)
            }

            loadedSet = loaded
            setName = name
            textures = nextTextures
            onProgress?(1)
        } catch {
            GameLogger.error(.sprites, "\(Provider.logLabel): failed to load set '\(name)' — \(error)")
            loadedSet = nil
            setName = nil
            textures = [:]
            onProgress?(1)
        }
    }

    /// Clears the active set so level-exit can free its textures.
    func release() {
        loadedSet = nil
        setName = nil
        textures = [:]
    }

    func texture(_ key: String) -> SKTexture? {
        textures[key]
    }

    func allTextures() -> [SKTexture] {
        Array(textures.values)
    }

    /// Testing seam: inject a set without reading the bundle.
    func seedForTesting(set: Provider.LoadedSet, textures: [String: SKTexture]) {
        loadedSet = set
        setName = Provider.setName(from: set)
        self.textures = textures
    }

    private func reportProgress(index: Int, keyCount: Int, onProgress: ((Double) -> Void)?) {
        let count = max(keyCount, 1)
        switch Provider.progressStyle {
        case .everyIteration:
            onProgress?(0.5 + 0.5 * Double(index + 1) / Double(count))
        case .everyNth(let stride):
            guard index % stride == 0 else { return }
            onProgress?(0.5 + 0.5 * Double(index) / Double(count))
        }
    }
}

// MARK: - Providers

nonisolated enum FloorTileSetAtlas: AtlasSpriteSetProviding {
    typealias LoadedSet = FloorTileSet

    static var assetKind: LevelAssetKind { .floor }
    static var logLabel: String { "FloorTileSetLibrary" }
    static var progressStyle: AtlasLoadProgressStyle { .everyNth(16) }

    static func loadFromBundle(set name: String, bundle: Bundle) throws -> FloorTileSet {
        try FloorTileSet.loadFromBundle(set: name, bundle: bundle)
    }

    static func sheetDimensions(of set: FloorTileSet) -> (w: Int, h: Int) {
        (set.meta.size.w, set.meta.size.h)
    }

    static func textureKeys(of set: FloorTileSet) -> [String] {
        set.frames.keys.sorted()
    }

    static func frameRect(of set: FloorTileSet, key: String) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard let frame = set.frames[key] else { return nil }
        return (frame.x, frame.y, frame.w, frame.h)
    }

    static func setName(from set: FloorTileSet) -> String {
        set.meta.floorSet
    }
}

nonisolated enum GateSpriteSetAtlas: AtlasSpriteSetProviding {
    typealias LoadedSet = GateSpriteSet

    static var assetKind: LevelAssetKind { .gate }
    static var logLabel: String { "GateSpriteSetLibrary" }
    static var progressStyle: AtlasLoadProgressStyle { .everyIteration }

    static func loadFromBundle(set name: String, bundle: Bundle) throws -> GateSpriteSet {
        try GateSpriteSet.loadFromBundle(set: name, bundle: bundle)
    }

    static func sheetDimensions(of set: GateSpriteSet) -> (w: Int, h: Int) {
        (set.meta.size.w, set.meta.size.h)
    }

    static func textureKeys(of set: GateSpriteSet) -> [String] {
        set.axisIDs
    }

    static func frameRect(of set: GateSpriteSet, key: String) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard let frame = set.frames[key] else { return nil }
        return (frame.x, frame.y, frame.w, frame.h)
    }

    static func setName(from set: GateSpriteSet) -> String {
        set.meta.gateSet
    }
}

nonisolated enum LetterSpriteSetAtlas: AtlasSpriteSetProviding {
    typealias LoadedSet = LetterSpriteSet

    static var assetKind: LevelAssetKind { .letters }
    static var logLabel: String { "LetterSpriteSetLibrary" }
    static var progressStyle: AtlasLoadProgressStyle { .everyNth(8) }

    static func loadFromBundle(set name: String, bundle: Bundle) throws -> LetterSpriteSet {
        try LetterSpriteSet.loadFromBundle(set: name, bundle: bundle)
    }

    static func sheetDimensions(of set: LetterSpriteSet) -> (w: Int, h: Int) {
        (set.meta.size.w, set.meta.size.h)
    }

    static func textureKeys(of set: LetterSpriteSet) -> [String] {
        set.frames.keys.sorted()
    }

    static func frameRect(of set: LetterSpriteSet, key: String) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard let frame = set.frames[key] else { return nil }
        return (frame.x, frame.y, frame.w, frame.h)
    }

    static func setName(from set: LetterSpriteSet) -> String {
        set.meta.letterSet
    }
}

nonisolated enum PitSpriteSetAtlas: AtlasSpriteSetProviding {
    typealias LoadedSet = PitSpriteSet

    static var assetKind: LevelAssetKind { .pit }
    static var logLabel: String { "PitSpriteSetLibrary" }
    static var progressStyle: AtlasLoadProgressStyle { .everyNth(4) }

    static func loadFromBundle(set name: String, bundle: Bundle) throws -> PitSpriteSet {
        try PitSpriteSet.loadFromBundle(set: name, bundle: bundle)
    }

    static func sheetDimensions(of set: PitSpriteSet) -> (w: Int, h: Int) {
        (set.meta.size.w, set.meta.size.h)
    }

    static func textureKeys(of set: PitSpriteSet) -> [String] {
        set.tileIDs
    }

    static func frameRect(of set: PitSpriteSet, key: String) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard let frame = set.frames[key] else { return nil }
        return (frame.x, frame.y, frame.w, frame.h)
    }

    static func setName(from set: PitSpriteSet) -> String {
        set.meta.pitSet
    }
}
