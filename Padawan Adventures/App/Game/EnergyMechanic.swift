import Foundation

/// Gates the energy gameplay surface (pickups, HUD bolts, combat cost).
/// Underlying energy state / pickup / defeat code is kept for easy re-enable.
nonisolated enum EnergyMechanic {
    /// Production default. Tests override via `withEnabled(_:)`.
    private static let defaultEnabled = false

    @TaskLocal private static var enabledOverride: Bool?

    static var isEnabled: Bool {
        enabledOverride ?? defaultEnabled
    }

    /// Runs `body` with energy temporarily enabled (for tests covering dormant paths).
    static func withEnabled<T>(_ body: () throws -> T) rethrows -> T {
        try $enabledOverride.withValue(true, operation: body)
    }
}
