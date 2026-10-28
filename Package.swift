// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ImageSqueeze",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ImageSqueeze",
            path: "Sources/ImageSqueeze"
        )
    ]
)
