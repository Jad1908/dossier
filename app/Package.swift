// swift-tools-version:5.9
import PackageDescription

// Dossier — the macOS front end for the `dossier` CLI.
//
// Built as a Swift Package executable (not an Xcode .xcodeproj) so it compiles
// with the Swift toolchain alone. `make app` (see app/README.md) wraps the
// built binary into a runnable Dossier.app bundle.
let package = Package(
    name: "Dossier",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Dossier",
            dependencies: ["TOMLKit"]
        ),
    ]
)
