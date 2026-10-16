// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DisableKeyboard",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DisableKeyboard",
            path: "DisableKeyboard",
            // Compiled by actool in bin/build; SwiftPM can't bundle .icon files.
            exclude: ["Icon.icon"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
