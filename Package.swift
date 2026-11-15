// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YouTubeDownloader",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "YouTubeDownloader", targets: ["YouTubeDownloader"])],
    targets: [.executableTarget(name: "YouTubeDownloader", path: "Sources/YouTubeDownloader")]
)
