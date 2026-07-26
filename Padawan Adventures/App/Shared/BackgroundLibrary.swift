import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of still background images under `Resources/Backgrounds/`.
@MainActor
final class BackgroundLibrary {
    static let subdirectory = "Backgrounds"

    private var images: [String: UIImage] = [:]
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Number of cached backgrounds (tests / diagnostics).
    var count: Int { images.count }

    func uiImage(named name: String) -> UIImage? {
        images[name]
    }

    func texture(named name: String) -> SKTexture? {
        guard let image = images[name] else { return nil }
        return SKTexture(image: image)
    }

    /// Loads `name` from the bundle into the cache when missing.
    ///
    /// Missing resources are skipped so bootstrap / level prepare still complete.
    func ensureLoaded(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, images[trimmed] == nil else { return }

        guard let image = Self.loadImage(named: trimmed, bundle: bundle) else { return }
        images[trimmed] = image
        await Task.yield()
    }

    /// Ensures each unique name is loaded; reports 0...1 progress across the set.
    func ensureLoaded(
        names: [String],
        onProgress: ((Double) -> Void)? = nil
    ) async {
        let unique = Self.uniqueNames(names)
        guard !unique.isEmpty else {
            onProgress?(1)
            return
        }

        let total = unique.count
        for (index, name) in unique.enumerated() {
            await ensureLoaded(named: name)
            onProgress?(Double(index + 1) / Double(total))
        }
        onProgress?(1)
    }

    /// Collects unique non-empty `background:` values from every Screens YAML.
    static func screenBackgroundNames(bundle: Bundle = .main) -> [String] {
        let urls = screenConfigURLs(bundle: bundle)
        var names: [String] = []
        for url in urls {
            let resourceName = url.deletingPathExtension().lastPathComponent
            guard let config = try? ScreenConfig.loadFromBundle(
                named: resourceName,
                withExtension: url.pathExtension.isEmpty ? "yaml" : url.pathExtension
            ) else {
                continue
            }
            if let background = normalizedName(config.background) {
                names.append(background)
            }
        }
        return uniqueNames(names)
    }

    static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in names {
            guard let normalized = normalizedName(name), seen.insert(normalized).inserted else {
                continue
            }
            ordered.append(normalized)
        }
        return ordered
    }

    static func normalizedName(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func loadImage(named name: String, bundle: Bundle) -> UIImage? {
        let extensions = ["png", "jpg", "jpeg"]
        for ext in extensions {
            if let url = bundle.url(
                forResource: name,
                withExtension: ext,
                subdirectory: subdirectory
            ) ?? bundle.url(forResource: name, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) ?? (try? Data(contentsOf: url)).flatMap({
                   UIImage(data: $0)
               }) {
                return image
            }
        }
        return nil
    }

    private static func screenConfigURLs(bundle: Bundle) -> [URL] {
        if let nested = bundle.urls(
            forResourcesWithExtension: "yaml",
            subdirectory: ScreenConfig.subdirectory
        ), !nested.isEmpty {
            return nested
        }
        // Flattened bundle: known screen basenames at root.
        let known = [
            "loading",
            "preparing",
            "menu",
            "settings",
            "level_select",
            "player_select",
            "player_selfie",
            "you_win",
            "defeat",
        ]
        return known.compactMap { bundle.url(forResource: $0, withExtension: "yaml") }
    }
}
