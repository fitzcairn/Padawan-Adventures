import SpriteKit
import UIKit

/// Full-width, aspect-preserving backgrounds for gate minigames.
@MainActor
enum GateMinigameBackground {
    @MainActor
    private static var textureCache: [String: SKTexture] = [:]

    /// Decodes the backgrounds for `kinds` into the texture cache.
    /// Call per level with only the kinds that level can spawn — each background is
    /// 2816x1536 (~17 MB decoded).
    @MainActor
    @discardableResult
    static func preloadTextures(
        kinds: Set<GateMinigameKind> = Set(GateMinigameKind.allCases),
        bundle: Bundle = .main
    ) -> [SKTexture] {
        var loaded: [SKTexture] = []
        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            let spec = backgroundSpec(for: kind)
            guard let texture = loadTexture(named: spec.name, root: spec.root, bundle: bundle) else {
                continue
            }
            loaded.append(texture)
        }
        return loaded
    }

    /// Drops cached backgrounds so the next access re-decodes from the bundle.
    static func release() {
        textureCache.removeAll()
    }

    /// Background art for each gate kind. `wordPlug` and `endingSoundPlug` share one image.
    private static func backgroundSpec(for kind: GateMinigameKind) -> (name: String, root: String) {
        switch kind {
        case .graphemeMatch:
            ("grapheme_match-bg", "Sprites/Gate/GraphemeSoundGate")
        case .soundOutWord:
            ("spelling-bg", "Sprites/Gate/SoundOutWordGate")
        case .wordPlug, .endingSoundPlug:
            ("word_plug_bg", "Sprites/Gate/StartingSoundGate")
        }
    }

    /// Letter-match art under `Sprites/Gate/GraphemeSoundGate/grapheme_match-bg.png`.
    static func graphemeMatch(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "grapheme_match-bg", root: "Sprites/Gate/GraphemeSoundGate", sceneSize: sceneSize)
    }

    /// Sound-out-word art under `Sprites/Gate/SoundOutWordGate/spelling-bg.png`.
    static func spelling(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "spelling-bg", root: "Sprites/Gate/SoundOutWordGate", sceneSize: sceneSize)
    }

    /// Starting/ending-sound art under `Sprites/Gate/StartingSoundGate/word_plug_bg.png`.
    static func wordPlug(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "word_plug_bg", root: "Sprites/Gate/StartingSoundGate", sceneSize: sceneSize)
    }

    /// Scene-space frame of the letter-match background (width-fit, centered).
    static func graphemeMatchFrame(sceneSize: CGSize, bundle: Bundle = .main) -> CGRect? {
        frame(
            named: "grapheme_match-bg",
            root: "Sprites/Gate/GraphemeSoundGate",
            sceneSize: sceneSize,
            bundle: bundle
        )
    }

    /// Scales the image to `sceneSize.width`, keeps aspect ratio, and centers it.
    private static func makeNode(
        named name: String,
        root: String,
        sceneSize: CGSize
    ) -> SKSpriteNode? {
        guard sceneSize.width > 1 else { return nil }
        guard let texture = loadTexture(named: name, root: root) else { return nil }

        let aspect = texture.size().height / max(texture.size().width, 1)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: sceneSize.width, height: sceneSize.width * aspect)
        node.position = CGPoint(x: sceneSize.width * 0.5, y: sceneSize.height * 0.5)
        node.zPosition = 0
        node.name = "background"
        node.isUserInteractionEnabled = false
        return node
    }

    private static func frame(
        named name: String,
        root: String,
        sceneSize: CGSize,
        bundle: Bundle
    ) -> CGRect? {
        guard sceneSize.width > 1 else { return nil }
        guard let texture = loadTexture(named: name, root: root, bundle: bundle) else { return nil }
        let aspect = texture.size().height / max(texture.size().width, 1)
        let height = sceneSize.width * aspect
        return CGRect(
            x: 0,
            y: (sceneSize.height - height) * 0.5,
            width: sceneSize.width,
            height: height
        )
    }

    private static func cacheKey(name: String, root: String) -> String {
        "\(root)/\(name)"
    }

    @MainActor
    private static func loadTexture(
        named name: String,
        root: String,
        bundle: Bundle = .main
    ) -> SKTexture? {
        let key = cacheKey(name: name, root: root)
        if let cached = textureCache[key] {
            return cached
        }

        let url: URL
        do {
            url = try SpriteSheetLoader.resourceURL(
                named: name,
                extensions: ["png"],
                root: root,
                bundle: bundle
            )
        } catch {
            return nil
        }

        guard let uiImage = UIImage(contentsOfFile: url.path)
            ?? (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)),
              let cgImage = uiImage.cgImage
        else {
            return nil
        }

        let texture = SKTexture(image: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        SpriteSheetLoader.prepareTextureForScaledDisplay(texture)
        textureCache[key] = texture
        return texture
    }
}
