import UIKit

/// Word illustrations for word-plug plates (`Sprites/Words/<image>.png`).
@MainActor
enum GateWordPlugImageSprites {
    private static var cache: [String: UIImage] = [:]

    /// Loads a sprite by basename from `Sprites/Words/`. Returns nil when `name` is nil/empty or missing.
    static func image(named name: String?, bundle: Bundle = .main) -> UIImage? {
        guard let name else { return nil }
        let key = name.lowercased()
        guard !key.isEmpty else { return nil }
        if bundle === Bundle.main, let cached = cache[key] { return cached }
        guard let url = bundle.url(
            forResource: key,
            withExtension: "png",
            subdirectory: WordCatalog.imageRoot
        ), let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        if bundle === Bundle.main { cache[key] = image }
        return image
    }
}
