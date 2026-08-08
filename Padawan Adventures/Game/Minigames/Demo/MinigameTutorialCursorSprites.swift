import SpriteKit
import UIKit

/// Hand cursor art for the minigame tutorial demo (`Sprites/UI/Tutorials/*`).
@MainActor
enum MinigameTutorialCursorSprites {
    enum Pose: String, CaseIterable {
        case pointer, swipe, tap
    }

    struct Art {
        let texture: SKTexture
        /// Contact point, normalised on the untrimmed frame (SpriteKit bottom-left origin).
        let anchor: CGPoint
    }

    private static let root = "Sprites/UI/Tutorials"
    private static var cached: [Pose: Art]?
    private static var didAttemptLoad = false

    /// Fingertip (pointer, swipe) or ring centre (tap), measured on the 500x500
    /// source art. Valid only while the sprites bake with `trim: false`.
    static func anchor(for pose: Pose) -> CGPoint {
        switch pose {
        case .pointer: CGPoint(x: 0.578, y: 0.096)
        case .swipe: CGPoint(x: 0.868, y: 0.270)
        case .tap: CGPoint(x: 0.572, y: 0.184)
        }
    }

    /// Loads baked hand sheets; returns nil unless all three poses succeed.
    static func load(bundle: Bundle = .main) -> [Pose: Art]? {
        if bundle === Bundle.main {
            if didAttemptLoad { return cached }
            didAttemptLoad = true
        }

        var result: [Pose: Art] = [:]
        for pose in Pose.allCases {
            guard let art = loadPose(pose, bundle: bundle) else {
                return nil
            }
            result[pose] = art
        }

        if bundle === Bundle.main {
            cached = result
        }
        return result
    }

    private static func loadPose(_ pose: Pose, bundle: Bundle) -> Art? {
        let sheetName = pose.rawValue
        let atlasName = "\(pose.rawValue)-atlas"

        let sheetURL: URL
        let atlasURL: URL
        do {
            sheetURL = try SpriteSheetLoader.resourceURL(
                named: sheetName,
                extensions: ["png", "jpg", "jpeg"],
                root: root,
                bundle: bundle
            )
            atlasURL = try SpriteSheetLoader.resourceURL(
                named: atlasName,
                extensions: ["json"],
                root: root,
                bundle: bundle
            )
        } catch {
            return nil
        }

        guard let atlasData = try? Data(contentsOf: atlasURL),
              let atlas = try? SpriteAtlas.decode(from: atlasData),
              let first = atlas.orderedFrames.first,
              let uiImage = UIImage(contentsOfFile: sheetURL.path)
              ?? (try? Data(contentsOf: sheetURL)).flatMap(UIImage.init(data:)),
              let cgImage = uiImage.cgImage
        else {
            return nil
        }

        let sheetW = cgImage.width
        let sheetH = cgImage.height
        guard sheetW > 0, sheetH > 0 else { return nil }

        let frame = first.frame
        guard frame.w > 0, frame.h > 0,
              frame.x >= 0, frame.y >= 0,
              frame.x + frame.w <= sheetW,
              frame.y + frame.h <= sheetH
        else {
            return nil
        }

        let parent = SKTexture(image: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        SpriteSheetLoader.prepareTextureForScaledDisplay(parent)
        let texture = SpriteSheetLoader.makeSubrectTexture(
            x: frame.x,
            y: frame.y,
            w: frame.w,
            h: frame.h,
            sheetWidth: sheetW,
            sheetHeight: sheetH,
            parent: parent
        )
        return Art(texture: texture, anchor: anchor(for: pose))
    }
}
