// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeOAuthPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeOAuthPlugin", type: .dynamic, targets: ["ClaudeOAuthPlugin"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/TypeWhisper/TypeWhisperPluginSDK.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "ClaudeOAuthPlugin",
            dependencies: [
                .product(name: "TypeWhisperPluginSDK", package: "TypeWhisperPluginSDK"),
            ]
        ),
    ]
)
