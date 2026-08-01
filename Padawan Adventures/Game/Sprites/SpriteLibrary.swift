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
    /// Fraction of `os_proc_available_memory()` captured at first budget check.
    private static let byteBudgetFraction = 0.20
    private var byteBudget: Int?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Resident-texture tripwire derived from launch-time headroom; diagnostic only.
    var byteBudgetLimit: Int {
        if let byteBudget { return byteBudget }
        let available = MemoryProbe.availableBytes()
        let budget = max(Int(Double(available) * Self.byteBudgetFraction), 1)
        byteBudget = budget
        return budget
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
    /// Marks `id` loaded only when every configured animation is present (sheets and
    /// resolved `flip_of` targets). Partial loads stay unloaded so a later call can retry.
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
                // Missing assets are skipped; incomplete ids stay unloaded for retry.
                GameLogger.error(.sprites, "failed to load \(entry.name) for \(id) — \(error)")
            }
            onProgress?(Double(index + 1) / Double(total))
            await Task.yield()
        }

        Self.resolveFlipAnimations(into: &loaded, flipSources: flipSources)

        let expected = Set(config.animations.keys)
        let missing = expected.subtracting(loaded.keys)
        guard missing.isEmpty else {
            GameLogger.error(
                .sprites,
                "incomplete load for \(id) — missing \(missing.sorted().joined(separator: ", "))"
            )
            onProgress?(1)
            return
        }

        animationsByID[id] = loaded
        bytesByID[id] = Self.textureBytes(of: loaded)
        loadedIDs.insert(id)
        onProgress?(1)
        checkByteBudget()
    }

    /// Configured animation names not yet resident for `id` (sorted).
    func missingAnimations(id: String, config: SpriteConfig) -> [String] {
        let loaded = animationsByID[id] ?? [:]
        return config.animations.keys.filter { loaded[$0] == nil }.sorted()
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
        checkByteBudget()
    }

    /// Logs when resident texture bytes exceed the launch-time budget; never evicts.
    private func checkByteBudget() {
        let resident = residentBytes
        let budget = byteBudgetLimit
        guard resident > budget else { return }
        let breakdown = bytesByID
            .sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        GameLogger.fault(
            .sprites,
            "residentBytes \(resident) exceeds budget \(budget): [\(breakdown)]"
        )
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

    /// Test seam: entries in the all-frames UIImage cache (must stay 0 after `uiImage`).
    var uiImagesCacheCount: Int { uiImagesCache.count }

    /// First frame as a UIKit image oriented for SwiftUI / UIKit.
    ///
    /// Undoes the SpriteKit prep flip applied in `SpriteSheetLoader.loadAnimation`.
    /// Converts only frame 0 — does not materialise the full clip via `uiImages`.
    func uiImage(id: String, named name: String = "idle") -> UIImage? {
        let key = "\(id)|\(name)"
        if let cached = uiImageCache[key] {
            return cached
        }
        guard let animation = animation(id: id, named: name),
              let frame = animation.frames.first else {
            return nil
        }
        let cgImage = frame.texture.cgImage()
        let upright = SpriteSheetLoader.flipAroundXAxis(cgImage)
        let image = UIImage(cgImage: upright, scale: 1, orientation: .up).preparedForScreen()
        uiImageCache[key] = image
        return image
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
            let image = UIImage(cgImage: upright, scale: 1, orientation: .up).preparedForScreen()
            return (image, frame.duration)
        }
        uiImagesCache[key] = frames
        if let first = frames.first {
            uiImageCache["\(id)|\(name)"] = first.image
        }
        return frames
    }
}
