// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawdCompanion",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClawdCompanion", targets: ["ClawdCompanion"])],
    targets: [
        .target(name: "ClawdLanguageResources", path: "Resources",
                exclude: ["Info.plist", "Clawd.icns", "ClawdDialogue.ttf", "MenuPet.png", "MenuPet@2x.png"],
                sources: ["LanguageResources.swift"], resources: [.copy("Languages")]),
        .executableTarget(name: "ClawdCompanion", dependencies: ["ClawdLanguageResources"]),
        .testTarget(name: "ClawdCompanionTests", dependencies: ["ClawdCompanion"])
    ]
)
