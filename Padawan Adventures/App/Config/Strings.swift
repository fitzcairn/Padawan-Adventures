import Foundation

/// UI copy from `Config/Catalogs/strings.yaml`.
nonisolated enum Strings {
    /// Process-lifetime cache; tests replace it via `_resetForTesting`.
    private nonisolated(unsafe) static var loaded: StringCatalog?

    static var catalog: StringCatalog {
        if let loaded { return loaded }
        let value = ConfigStore.loadOrFallback("strings", fallback: StringCatalog.fallback) {
            let catalog = try StringCatalog.loadFromBundle()
            try catalog.validate()
            return catalog
        }
        loaded = value
        return value
    }

    /// Copy for `id`. Missing ids trap in Debug and render the id in Release.
    static func text(_ id: String, _ args: [String: String] = [:]) -> String {
        guard let entry = catalog.entry(id) else {
            assertionFailure("unknown string id '\(id)'")
            return id
        }
        var result = entry.text
        for (key, value) in args {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// Plays the entry's voice-over clip. Missing ids and missing assets are ignored.
    @MainActor
    static func speak(_ id: String) {
        guard let entry = catalog.entry(id) else { return }
        SoundEffectsController.shared.play(trackID: entry.sfx)
    }

    /// Test helper: replace the cached catalog (or clear with `nil`).
    static func _resetForTesting(_ catalog: StringCatalog? = nil) {
        loaded = catalog
    }
}
