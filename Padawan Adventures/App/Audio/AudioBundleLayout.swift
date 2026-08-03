import Foundation

/// Bundle subdirectories searched for one-shot FX, in priority order.
/// `Resources/Audio` ships as a folder reference, so nested folders keep their
/// paths in the bundle and `Bundle.url(forResource:subdirectory:)` — which is not
/// recursive — must be given each one explicitly.
nonisolated enum AudioBundleLayout {
    static let fxSubdirectories = [
        "Audio/FX",
        "Audio/FX/Phonics",
        "Audio/FX/Words",
        "Audio/FX/UI",
    ]
    static let musicSubdirectories = ["Audio/Music"]
}
