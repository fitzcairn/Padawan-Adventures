import CoreGraphics
import Foundation
import SpriteKit
import UIKit

enum FloorSpriteLoader {
    /// Loads every terrain animation from the floor spritesheet + atlas.
    static func loadAll(
        catalog: TerrainCatalog,
        bundle: Bundle = .main
    ) throws -> [String: SpriteAnimation] {
        let sprite = catalog.sprite
        let sheetURL = try resourceURL(
            named: sprite.sheet,
            extensions: ["png", "jpg", "jpeg"],
            subdirectory: sprite.root,
            bundle: bundle
        )
        let atlasURL = try resourceURL(
            named: sprite.atlas,
            extensions: ["json"],
            subdirectory: sprite.atlasRoot,
            bundle: bundle
        )

        let atlas = try FloorAtlas.decode(from: Data(contentsOf: atlasURL))
        let sheetData = try Data(contentsOf: sheetURL)
        guard let uiImage = UIImage(contentsOfFile: sheetURL.path) ?? UIImage(data: sheetData),
              let cgImage = uiImage.cgImage else {
            throw SpriteLoadError.invalidImage(sprite.sheet)
        }

        let keyedImage: CGImage
        if let chromaKey = sprite.chromaKey, let rgb = SpriteSheetLoader.parseHexRGB(chromaKey) {
            keyedImage = SpriteSheetLoader.applyChromaKey(
                to: cgImage,
                key: rgb,
                tolerance: sprite.chromaKeyTolerance,
                feather: sprite.chromaKeyFeather,
                smoothRadius: sprite.chromaKeySmooth
            )
        } else {
            keyedImage = cgImage
        }

        let sheetWidth = keyedImage.width
        let sheetHeight = keyedImage.height
        guard sheetWidth > 0, sheetHeight > 0 else {
            throw SpriteLoadError.invalidImage(sprite.sheet)
        }

        let frameCount = atlas.frameCount
        let duration = atlas.frameDurationSeconds()
        var result: [String: SpriteAnimation] = [:]
        result.reserveCapacity(catalog.terrains.count)

        for (id, definition) in catalog.terrains {
            var cropped: [CGImage] = []
            cropped.reserveCapacity(frameCount)

            for frameIndex in 0..<frameCount {
                guard let rect = atlas.frameRect(
                    tileRow: definition.row,
                    tileCol: definition.col,
                    frameIndex: frameIndex
                ) else {
                    throw SpriteLoadError.frameOutOfBounds(
                        atlas: sprite.atlas,
                        frame: "\(id)#\(frameIndex)",
                        rect: "(row \(definition.row), col \(definition.col))"
                    )
                }
                guard rect.minX >= 0, rect.minY >= 0,
                      rect.maxX <= CGFloat(sheetWidth) + 0.5,
                      rect.maxY <= CGFloat(sheetHeight) + 0.5,
                      let piece = keyedImage.cropping(to: rect) else {
                    throw SpriteLoadError.frameOutOfBounds(
                        atlas: sprite.atlas,
                        frame: "\(id)#\(frameIndex)",
                        rect: "(\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height)))"
                    )
                }
                cropped.append(piece)
            }

            let trimmed = SpriteSheetLoader.trimToSharedOpaqueBounds(cropped)
            // Floor nodes skip AnimatedSpriteNode's yScale=-1 correction (so the
            // diamond stays below the tile origin), so do NOT flipAroundXAxis here —
            // that pair is only for player/item sprites. Mirror horizontally so
            // isometric faces match the sheet.
            let frames: [SpriteFrame] = trimmed.map { image in
                let displayImage = SpriteSheetLoader.flipAroundYAxis(image)
                return SpriteFrame(
                    texture: SpriteSheetLoader.makeFrameTexture(from: displayImage),
                    duration: max(duration, 0.000_001)
                )
            }
            result[id] = SpriteAnimation(frames: frames)
        }

        return result
    }

    private static func resourceURL(
        named name: String,
        extensions: [String],
        subdirectory: String,
        bundle: Bundle
    ) throws -> URL {
        for ext in extensions {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        throw SpriteLoadError.missingResource("\(subdirectory)/\(name)")
    }
}
