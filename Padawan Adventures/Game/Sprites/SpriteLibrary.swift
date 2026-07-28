import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of sliced sprite animations.
@MainActor
final class SpriteLibrary {
    private var loadedIDs: Set<String> = []
    private var animationsByID: [String: [String: SpriteAnimation]] = [:]
    private var bytesByID: [String: Int] = [:]
    private var uiImageCache: [String: UIImage] = [:]
    private var uiImagesCache: [String: [(image: UIImage, duration: TimeInterval)]] = [:]
    private var actionCache: [String: SKAction] = [:]
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Approximate resident texture bytes (RGBA8), for eviction and diagnostics.
    var residentBytes: Int {
        bytesByID.values.reduce(0, +)
    }

    /// RGBA8 bytes for a set of animations, counting each texture once.
    ///
    /// `flip_of` animations share their source's textures, so a naive sum double-counts.
    private static func textureBytes(of animations: [String: SpriteAnimation]) -> Int {
        var seen = Set<ObjectIdentifier>()
        var bytes = 0
        for animation in animations.values {
            for frame in animation.frames where seen.insert(ObjectIdentifier(frame.texture)).inserted {
                let size = frame.texture.size()
                bytes += Int(size.width * size.height) * 4
            }
        }
        return bytes
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
                    bundle: bundle,
                    trim: config.trim
                )
            } catch {
                // Missing assets are skipped so worlds still load while sheets arrive.
                print("SpriteLibrary: failed to load \(entry.name) for \(id) — \(error)")
            }
            onProgress?(Double(index + 1) / Double(total))
            await Task.yield()
        }

        Self.resolveFlipAnimations(into: &loaded, flipSources: flipSources)

        animationsByID[id] = loaded
        bytesByID[id] = Self.textureBytes(of: loaded)
        if !loaded.isEmpty || config.animations.isEmpty {
            loadedIDs.insert(id)
        }
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
        bytesByID[id] = Self.textureBytes(of: animations)
        loadedIDs.insert(id)
    }

    /// Drops one loaded id so the next `ensureLoaded` re-reads its sheets.
    func invalidate(id: String) {
        loadedIDs.remove(id)
        animationsByID[id] = nil
        bytesByID[id] = nil
        uiImageCache = uiImageCache.filter { !$0.key.hasPrefix("\(id)|") }
        uiImagesCache = uiImagesCache.filter { !$0.key.hasPrefix("\(id)|") }
        actionCache = actionCache.filter { !$0.key.hasPrefix("\(id)|") }
    }

    /// Drops every loaded id outside `keep`, freeing its textures.
    ///
    /// Declarative on purpose: callers state what the current context needs rather
    /// than remembering to release what it no longer needs.
    func retain(ids keep: Set<String>) {
        for id in loadedIDs where !keep.contains(id) {
            animationsByID[id] = nil
            bytesByID[id] = nil
        }
        loadedIDs.formIntersection(keep)
        uiImageCache = uiImageCache.filter { entry in
            guard let id = entry.key.split(separator: "|").first else { return false }
            return keep.contains(String(id))
        }
        uiImagesCache = uiImagesCache.filter { entry in
            guard let id = entry.key.split(separator: "|").first else { return false }
            return keep.contains(String(id))
        }
        actionCache = actionCache.filter { entry in
            guard let id = entry.key.split(separator: "|").first else { return false }
            return keep.contains(String(id))
        }
    }

    /// Every distinct texture currently resident, for GPU pre-upload.
    func allTextures() -> [SKTexture] {
        var seen = Set<ObjectIdentifier>()
        var textures: [SKTexture] = []
        for animations in animationsByID.values {
            for animation in animations.values {
                for frame in animation.frames where seen.insert(ObjectIdentifier(frame.texture)).inserted {
                    textures.append(frame.texture)
                }
            }
        }
        return textures
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

    /// Cached looping `SKAction` for a multi-frame animation, shared across nodes.
    func action(id: String, named name: String) -> SKAction? {
        let key = "\(id)|\(name)"
        if let cached = actionCache[key] {
            return cached
        }
        guard let animation = animation(id: id, named: name),
              animation.frames.count > 1 else {
            return nil
        }
        let built = AnimatedSpriteNode.makeLoopingAction(for: animation)
        actionCache[key] = built
        return built
    }

    /// First frame as a UIKit image oriented for SwiftUI / UIKit.
    ///
    /// Undoes the SpriteKit prep flip applied in `SpriteSheetLoader.loadAnimation`.
    func uiImage(id: String, named name: String = "idle") -> UIImage? {
        let key = "\(id)|\(name)"
        if let cached = uiImageCache[key] {
            return cached
        }
        guard let frames = uiImages(id: id, named: name), let first = frames.first else {
            return nil
        }
        uiImageCache[key] = first.image
        return first.image
    }

    /// All frames as upright UIKit images with per-frame durations (for SwiftUI looping).
    func uiImages(id: String, named name: String = "idle") -> [(image: UIImage, duration: TimeInterval)]? {
        let key = "\(id)|\(name)|all"
        if let cached = uiImagesCache[key] {
            return cached
        }
        guard let animation = animation(id: id, named: name), !animation.frames.isEmpty else {
            return nil
        }
        let frames: [(image: UIImage, duration: TimeInterval)] = animation.frames.map { frame in
            let cgImage = frame.texture.cgImage()
            let upright = SpriteSheetLoader.flipAroundXAxis(cgImage)
            let image = UIImage(cgImage: upright, scale: 1, orientation: .up)
            return (image, frame.duration)
        }
        uiImagesCache[key] = frames
        if let first = frames.first {
            uiImageCache["\(id)|\(name)"] = first.image
        }
        return frames
    }
}
