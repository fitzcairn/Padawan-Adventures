import SpriteKit
import UIKit

/// Full-width, aspect-preserving backgrounds for gate minigames.
@MainActor
enum GateMinigameBackground {
    @MainActor
    private static var textureCache: [String: SKTexture] = [:]

    /// Decodes gate backgrounds into the texture cache (call during bootstrap).
    @MainActor
    @discardableResult
    static func preloadTextures(bundle: Bundle = .main) -> [SKTexture] {
        let specs = [
            ("letter_match-bg", "Sprites/Gate/letter_match"),
            ("spelling-bg", "Sprites/Gate/spelling"),
            ("word_plug_bg", "Sprites/Gate/word_plug"),
        ]
        var loaded: [SKTexture] = []
        for (name, root) in specs {
            if let existing = textureCache[cacheKey(name: name, root: root)] {
                loaded.append(existing)
                continue
            }
            guard let texture = loadTexture(named: name, root: root, bundle: bundle) else { continue }
            textureCache[cacheKey(name: name, root: root)] = texture
            loaded.append(texture)
        }
        return loaded
    }

    /// Letter-match art under `Sprites/Gate/letter_match/letter_match-bg.png`.
    static func letterMatch(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "letter_match-bg", root: "Sprites/Gate/letter_match", sceneSize: sceneSize)
    }

    /// Spelling art under `Sprites/Gate/spelling/spelling-bg.png`.
    static func spelling(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "spelling-bg", root: "Sprites/Gate/spelling", sceneSize: sceneSize)
    }

    /// Word-plug art under `Sprites/Gate/word_plug/word_plug_bg.png`.
    static func wordPlug(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "word_plug_bg", root: "Sprites/Gate/word_plug", sceneSize: sceneSize)
    }

    /// Scene-space frame of the letter-match background (width-fit, centered).
    static func letterMatchFrame(sceneSize: CGSize, bundle: Bundle = .main) -> CGRect? {
        frame(
            named: "letter_match-bg",
            root: "Sprites/Gate/letter_match",
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
