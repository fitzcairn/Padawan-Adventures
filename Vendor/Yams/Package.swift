// swift-tools-version:5.7
import PackageDescription

// Vendored Yams 5.4.0 (https://github.com/jpsim/Yams). Kept local so Xcode
// does not fetch SourcePackages/artifacts for this dependency.
let package = Package(
    name: "Yams",
    products: [
        .library(name: "Yams", targets: ["Yams"])
    ],
    targets: [
        .target(
            name: "CYaml",
            cSettings: [.define("YAML_DECLARE_STATIC")]
        ),
        .target(
            name: "Yams",
            dependencies: ["CYaml"],
            cSettings: [.define("YAML_DECLARE_STATIC")]
        )
    ]
)
