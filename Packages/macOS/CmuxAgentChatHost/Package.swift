// swift-tools-version: 6.0

import PackageDescription

// Host-side agent transcript registry types (session records, hook session store,
// transcript tailer, Codex rollout identity). Used by the app's local resume,
// search and current-work features. Moved out of CmuxMobileHost.
let package = Package(
    name: "CmuxAgentChatHost",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxAgentChatHost",
            targets: ["CmuxAgentChatHost"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../../Shared/CmuxAgentChat"),
    ],
    targets: [
        .target(
            name: "CmuxAgentChatHost",
            dependencies: [
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "CmuxAgentChat", package: "CmuxAgentChat"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
