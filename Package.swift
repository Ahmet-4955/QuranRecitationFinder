// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuranRecitationFinder",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "QuranRecitationFinder",
            targets: ["QuranRecitationFinder"]
        )
    ],
    targets: [
        .executableTarget(
            name: "QuranRecitationFinder",
            path: "Sources/QuranRecitationFinder"
        )
    ]
)
