// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudiobookLibrary",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AudiobookLibrary", targets: ["AudiobookLibrary"])
    ],
    targets: [
        .executableTarget(
            name: "AudiobookLibrary",
            resources: [.copy("Resources/kokoro_worker.py")]
        ),
        .testTarget(
            name: "AudiobookLibraryTests",
            dependencies: ["AudiobookLibrary"],
            resources: [.copy("Resources/test-book.txt")]
        )
    ]
)
