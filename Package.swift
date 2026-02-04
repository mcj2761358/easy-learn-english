// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EasyLearnEnglish",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EasyLearnEnglish", targets: ["EasyLearnEnglish"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "EasyLearnEnglish",
            path: "Sources/EasyLearnEnglish"
        )
    ]
)
