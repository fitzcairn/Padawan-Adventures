import CoreGraphics
import Foundation
import SpriteKit
import UIKit

enum FloorSpriteLoader {
    /// Loads every terrain animation from the floor spritesheet + atlas.
    ///
    /// `onProgress` receives a 0...1 fraction after sheet prep and after each terrain.
    static func loadAll(
        catalog: TerrainCatalog,
        bundle: Bundle = .main,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> [String: SpriteAnimation] {
        let sprite = catalog.sprite
        let terrainCount = catalog.terrains.count
        // Sheet prep (decode + chroma) is one unit; each terrain is another.
        let totalUnits = max(terrainCount + 1, 1)
        await report(onProgress, 0)

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

        // Floors are static tiles: always slice frame 0 only (ignore multi-block atlas
        // layouts / duration_s animation timing used by character sheets).
        let terrains = catalog.terrains
        var completedUnits = 1
        await report(onProgress, Double(completedUnits) / Double(totalUnits))

        var result: [String: SpriteAnimation] = [:]
        result.reserveCapacity(terrains.count)

        for (id, definition) in terrains {
            guard let rect = atlas.frameRect(
                tileRow: definition.row,
                tileCol: definition.col,
                frameIndex: 0
            ) else {
                throw SpriteLoadError.frameOutOfBounds(
                    atlas: sprite.atlas,
                    frame: "\(id)#0",
                    rect: "(row \(definition.row), col \(definition.col))"
                )
            }
            guard rect.minX >= 0, rect.minY >= 0,
                  rect.maxX <= CGFloat(sheetWidth) + 0.5,
                  rect.maxY <= CGFloat(sheetHeight) + 0.5,
                  let piece = keyedImage.cropping(to: rect) else {
                throw SpriteLoadError.frameOutOfBounds(
                    atlas: sprite.atlas,
                    frame: "\(id)#0",
                    rect: "(\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height)))"
                )
            }

            let trimmed = SpriteSheetLoader.trimToSharedOpaqueBounds([piece])
            // Floor nodes skip AnimatedSpriteNode's yScale=-1 correction (so the
            // diamond stays below the tile origin), so do NOT flipAroundXAxis here —
            // that pair is only for player/item sprites. Mirror horizontally so
            // isometric faces match the sheet.
            let frames: [SpriteFrame] = trimmed.map { image in
                let displayImage = SpriteSheetLoader.flipAroundYAxis(image)
                return SpriteFrame(
                    texture: SpriteSheetLoader.makeFrameTexture(from: displayImage),
                    duration: 0
                )
            }
            result[id] = SpriteAnimation(frames: frames)

            completedUnits += 1
            await report(onProgress, Double(completedUnits) / Double(totalUnits))
        }

        return result
    }

    private static func report(
        _ onProgress: (@MainActor @Sendable (Double) -> Void)?,
        _ fraction: Double
    ) async {
        if let onProgress {
            await MainActor.run {
                onProgress(fraction)
            }
        }
        await Task.yield()
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
