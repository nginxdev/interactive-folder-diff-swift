// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Interactive Folder Diff",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "InteractiveFolderDiff",
            targets: ["InteractiveFolderDiff"]),
    ],
    targets: [
        .executableTarget(
            name: "InteractiveFolderDiff",
            path: "Sources")
    ]
)
